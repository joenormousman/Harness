# Pipeline Build — Findings & Lessons Learned

This document captures the surprises, blockers, and non-obvious decisions from building the two Salesforce pipelines and the metadata dep-resolver in this repo. Written contemporaneously — every finding here is something the reference documentation either doesn't mention, mentions in the wrong place, or misrepresents.

**Timeframe:** Two working days ahead of the Harness Senior Implementation Engineer interview (2026-07-17). Built by one engineer against fresh accounts on both platforms.

**Bias:** These findings are honest, including the ones that make Harness or Salesforce look bad — because the interview panel will spot glossing, and a truthful implementation report lands stronger than a marketing gloss.

---

## Section 1 — Modern Salesforce is aggressively pushing External Client Apps over Connected Apps

### The finding

Every current Salesforce document for Harness (and every doc on Copado / Gearset / Flosum's integration guides) says *"create a Connected App with JWT bearer flow."* In a **modern Salesforce org (2024+)**, that is not directly possible via the UI.

- `Setup → App Manager → New Lightning App / New External Client App` are the only options — no "New Connected App" button
- The classic URLs `/app/mgmt/newconnectedapp.apexp` and `/setup/mgmt/newconnectedapp.apexp` are intercepted by Lightning routing and redirect to Personal Information
- Direct-navigating to `/_ui/core/application/force/connectedapp/ForceConnectedApplicationPage/e` lands on an *edit* page for an existing Connected App, not a create form

### What actually works

**External Client Apps (ECAs).** Functionally equivalent for JWT bearer flow:

- Same Consumer Key / Consumer Secret pair
- Same certificate-based signing
- Same OAuth scopes model
- `sf org login jwt --client-id <ECA_client_id> ...` works transparently

### What this means for the interview

- **Every "Connected App" doc on the internet for Harness + SF is now subtly wrong** for new-org customers.
- Harness has an opportunity to ship an ECA-first setup guide — customers will hit this within their first hour on the platform.
- Existing customers with pre-2024 Connected Apps can keep them; new customers must use ECAs. Any "Salesforce for Harness" tutorial content needs both paths documented.

### Migration signal

The `AIGIS MCP JWT` Connected App already in the dev org (from a prior project) is legacy. New apps of that shape can't be created in that same org anymore via the UI. Salesforce is *forcing* the ECA migration even for existing orgs — old apps continue to work, but new setup can't follow the old pattern.

---

## Section 2 — Modern SF Dev Edition usernames have a hidden suffix

### The finding

Signing up for a Dev Edition at `developer.salesforce.com/signup` with email `joe@governed.dev` produces a **login username of `joe.<uuid>@agentforce.com`**, not the display email. E.g.:

- Display email: `joe@governed.dev`
- Actual login username: `joe.24c4020f12c1@agentforce.com`

### Why this matters

- JWT auth fails with `check your username and password` if you use the display email
- The `sf_*_username` Harness secret must hold the `.agentforce.com` variant
- Documentation for older SF signups mentions the suffix pattern but with `.salesforce.com` domain; SF quietly rebranded to `.agentforce.com` when they pivoted the platform toward Agentforce

### How to find your actual username

Setup → Users → Users → look at the **Username** column (not the Email column). It'll match the `.agentforce.com` pattern.

---

## Section 3 — Salesforce first-login email verification

### The finding

First browser login to a fresh Dev Edition from a new IP or user-agent triggers a **6-digit code emailed to the org admin's display email**. This gates access to Setup entirely; you can't even reach App Manager without completing verification.

### Impact on automation

Any Playwright / Selenium / API-based first-time setup will hit this. Options:

1. Human completes verification in the automation-driven browser (defeats headless setup)
2. Check "Don't ask again" during the challenge — survives future sessions on the same browser fingerprint
3. Whitelist the automation's IP under Setup → Security → Network Access — but this itself requires an authenticated Setup session, chicken-and-egg for first setup

### Interview signal

If a customer's Harness deployment includes automated org provisioning, this is a real blocker to script. Realistic customer implementations pair automation with a human confirmation on first-org access.

---

## Section 4 — Harness Free tier no longer has self-serve CC upgrade

### The finding

Harness's Free tier includes 2,000 Cloud Credits (their build-minute equivalent) and lists "Continuous Integration" as an included module. **But actual Cloud runtime execution is gated behind credit card validation, and there is no self-serve UI to add a card.** Attempting to run a pipeline stage with `runtime.type: Cloud` fails at the `Initialize` step:

> "To use Harness Cloud, you must provide a credit card to validate your account"

Meanwhile the Subscriptions tab shows:
- Plan: Free
- License Count: Unlimited Code Committers
- The only actionable button: **"Contact Sales"**

There is no "Add Payment Method" screen anywhere in Account Settings.

### What this means

Free-tier accounts today have three real options for Cloud runtime:

1. **Contact Sales** — enterprise sales cycle, weeks-to-months. Not viable for demo timelines.
2. **Self-hosted Delegate** — install Harness Delegate on your own Docker host, K8s cluster, or cloud VM. Bypasses the CC gate entirely. Setup: ~30-45 min for a fresh cloud VM install.
3. **Skip Cloud runtime entirely** — pipelines exist and are visible in the UI, but never execute end-to-end.

### Product observation

Harness's Free tier positioning is confused. It advertises Cloud Credits but doesn't let you spend them without a sales conversation. That's a bad first-impression for anyone evaluating Harness for a personal project or a POC — the exact segment that produces internal champions who later drive enterprise deals. **Fixing this is a small-scope, high-leverage product change.**

---

## Section 5 — Harness UI silently scopes new connectors to the current context

### The finding

Creating a connector while inside a Project's setup UI produces a **Project-scoped** connector regardless of what "scope" the user thinks they're choosing. The "Account" label in the URL type field is asking about the **GitHub URL layout**, not the Harness connector scope.

- URL Type = "Account" + URL = `https://github.com/joenormousman` = a **GitHub-account-scoped connector at Harness Project scope**
- URL Type = "Repository" + URL = `https://github.com/joenormousman/Harness` = a **GitHub-repo-scoped connector at Harness Project scope**

To get a **Harness Account-scoped** connector, you must:

1. Leave the Project context — click your account name in top-left to reach Account Settings
2. Navigate to Account Resources → Connectors
3. Create the connector from THAT location

If you try to create a "cross-scope" connector from within a Project, Harness silently downscopes without warning.

### Impact

Pipeline YAML that references `account.GitHub` (a common convention for reusable pipeline templates) fails to find the connector if the connector actually got saved at Project scope.

### Workaround we used

Made the pipeline's `connectorRef` a runtime input (`<+input>`). Portable across scopes — the pipeline runner picks any valid connector at run time. Loses some coupling but is more flexible.

### Product observation

The word "scope" is heavily overloaded in the Harness connector UI. The URL Type field, the connector scope, and the OAuth authorization scope are three separate concepts, all called "scope" in different tooltips. A clarifying rename or a scope diagram in the connector wizard would prevent this.

---

## Section 6 — GitHub connector URL Test Repository is trailing-space sensitive

### The finding

The Test Repository field in the Harness GitHub Account connector wizard is a plain text field with **no input sanitization for trailing whitespace**. A single trailing space causes the connection test to fail with:

```
Illegal character in path at index 47: https://github.com/joenormousman/Harness/Github /info/refs?service=git-upload-pack
```

The parser errors at the space between `Github` and `/info/refs`. Debugging this the first time takes ~15 min because the error message names "Illegal character at index 47" without specifying which character is illegal.

### Mitigation

Retype these values directly into the field. Do not copy-paste from Notepad, Word, or any editor that might introduce non-visible characters. Autocomplete suggestions in the field can also introduce leading capitals or spaces.

---

## Section 7 — "Create new Pipeline" vs "Import from Git" are different flows with different collision semantics

### The finding

Harness has two flows for connecting a pipeline to a git repo:

1. **Create new Pipeline** with "Third-party Git provider" selected — Harness treats this as *"give me a location to write a new pipeline YAML file"*. When you Save, it does a **git-create-file API call**, which errors if the file exists at that path.
2. **Import from Git** — Harness reads the existing YAML file at the specified path and treats it as authoritative. Save does a **git-update-file API call**, which works even when the file exists.

Both flows land in the Pipeline Studio and look identical after import. The difference only surfaces when you Save.

### The trap we hit

We used "Create new Pipeline" (visually cleaner modal in the current UI) with a YAML path pointing at our pre-committed pipeline file. First save attempt errored with:

> `.harness/salesforce-dx-governed-release.yaml does not match` — "File with given filepath already exists in Github, thus couldn't create a new file."

### Recovery paths

1. **Delete the existing file from git**, push, retry Save — Harness's create-file API now succeeds because the file no longer exists.
2. **Discard the pipeline draft, delete it from the Pipelines list, re-enter via Import from Git**. Cleaner in git history (no delete-then-recreate commit), but slower.

We used option 1 because option 2's UI wasn't obviously present in the current Harness build.

### Product observation

The "Create new Pipeline" modal has three options: Harness Code Repository, Third-party Git provider, and — implicitly — Import. But "Import" as a distinct action isn't labeled at the top level. New users default to "Create" because it's the labeled action; only later do they discover Import as a separate button somewhere else in the UI.

---

## Section 8 — Harness re-serializes YAML on save (this is a good thing)

### The finding

When you Save a pipeline (in either flow above), Harness normalizes the YAML — reordering keys within blocks, standardizing quoting, applying its own indentation preferences. **Semantics preserved**, whitespace and ordering not.

### Impact

- Git diffs after Save are large (all lines "changed" visually even when content is unchanged)
- Repos storing pipeline YAML get frequent "Harness re-serialized" commits from anyone editing via UI

### Mitigation

- Configure the linter/pre-commit to skip pipeline YAML files
- Treat pipeline YAML files as machine-owned; edits go through Harness UI or code review only

### Product observation

A "keep original formatting" option on Save would be nice, but conflicts with Harness's schema evolution — they need to be able to add fields on Save without asking. This is a fair trade-off; teams just need to know.

---

## Section 9 — JWT cert generation on Git Bash / MSYS Windows needs `MSYS_NO_PATHCONV=1`

### The finding

Running:

```bash
openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 \
  -keyout server.key -out server.crt \
  -subj "/C=US/ST=Demo/L=Demo/O=Harness/OU=Demo/CN=harness-sfdx-demo"
```

...on Git Bash for Windows fails with:

> subject name is expected to be in the format /type0=value0/... — This name is not in that format: 'C:/Program Files/Git/C=US/ST=Demo/L=Demo/O=Harness/OU=Demo/CN=harness-sfdx-demo'

MSYS is trying to be helpful and path-translating the `/C=US/...` string as if it were a Windows path.

### Fix

Prefix the openssl invocation with `MSYS_NO_PATHCONV=1`:

```bash
MSYS_NO_PATHCONV=1 openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 \
  -keyout server.key -out server.crt \
  -subj "/C=US/ST=Demo/L=Demo/O=Harness/OU=Demo/CN=harness-sfdx-demo"
```

### Alternatives

- Run in PowerShell where the subj string isn't path-translated
- Run in WSL if available
- Provide the subject via `-config file.cnf` instead of `-subj` on the CLI

### Interview relevance

Cert setup is a first-hour task for any Harness Salesforce customer. This bug bites Windows developers specifically; docs mostly assume macOS or Linux.

---

## Section 10 — AMD SVM off in BIOS + WSL2 missing is a blocker for local Docker Delegate

### The finding

Attempting to run a local Docker-based Harness Delegate on a Windows box with AMD Ryzen 5900X:

- Docker Desktop refuses to start: "Virtualization support not detected"
- Root causes: AMD SVM (AMD's virtualization extension) is disabled in the motherboard BIOS + WSL2 isn't installed

### Debug commands

```powershell
Get-CimInstance Win32_Processor | Select-Object VirtualizationFirmwareEnabled
# False → SVM is off in BIOS

systeminfo | Select-String -Pattern 'Virtualization'
# "Virtualization Enabled In Firmware: No"

wsl --status
# Errors → WSL not installed
```

### Fix

1. Reboot into BIOS (typically Delete or F2 during POST on Ryzen boards)
2. Advanced → CPU Configuration → **SVM Mode → Enabled**
3. Save & Exit (F10)
4. Back in Windows: `wsl --install` (requires admin, needs another reboot)
5. Docker Desktop starts

### Interview relevance

This is the exact class of blocker enterprise customers hit when trying to run local delegates. **A cloud-VM-based delegate onboarding path removes this friction entirely** — Harness could ship a one-command "spin up a delegate on our free tier compute for you" experience. Would substantially lower the first-run friction for POC customers.

---

## Section 11 — Salesforce metadata references are asymmetric (dep-resolver core insight)

### The finding

Salesforce metadata files reference *outward* but not *inward*. This is the single biggest source of "why did my deploy break the target org" incidents.

Examples:

| Item file contains | Item file does NOT contain |
|---|---|
| `CustomField` file has its parent object (implicit via path) | `CustomField` has no list of ValidationRules that reference it |
| `ValidationRule` errorConditionFormula names the fields it uses | `CustomField` has no list of ValidationRules that use it |
| `PermissionSet` has `fieldPermissions` blocks naming fields | `CustomField` has no list of PermissionSets that grant it |

### Consequence for deploys

A user who says *"deploy this one field"* and gets exactly that field will have a broken target org: the ValidationRule that references the field either doesn't exist (silent behavior change) or references a field the target doesn't yet have (deploy fails).

### What a real resolver has to do

**Scan sibling files for inverse references.** Given a `CustomField`, walk every ValidationRule and every PermissionSet in the repo looking for references TO that field. In a real customer repo with 10k+ metadata items, this needs a persistent inverted index (Postgres, DuckDB, or similar) — per-query scans are O(N) and painful.

### Product observation

The **rationale trail** (which items were included and why) is the interview-differentiator. Any resolver that just spits out a package.xml is a black box. A resolver that shows *"included Field X because ValidationRule Y references it in formula"* is auditable, admin-developer trustable, and adds product value orthogonal to the dep-graph itself.

See `docs/dep-resolver-architecture.md` for full detail.

---

## Section 12 — Modern Harness CLI (`hc`) is scoped to Artifacts + IACM

### The finding

The current Harness CLI (`hc`, v1.3.30 as of 2026-07) covers only:

- `artifact` — Manage Harness Artifacts
- `auth` — Authentication
- `iacm` — Infrastructure as Code Management
- `registry` — Harness Artifact Registries
- `upgrade`, `version`, `help`, `completion` — housekeeping

It **does not have** `pipeline`, `deploy`, `secret`, or `connector` subcommands. Any workflow involving "apply this pipeline YAML from local disk" needs the REST API directly, the Terraform provider, or the web UI.

### What we assumed vs found

We assumed `hc pipeline apply` or `hc deploy` existed based on the naming pattern of similar CLIs (GitHub, GitLab, Circle). It doesn't. This is worth calling out explicitly to any team planning "CI/CD as code" workflows on Harness.

### Alternatives

- **REST API directly** — `curl` with an X-API-KEY header. Fully capable.
- **Terraform provider** — `harness/harness-platform` provider. Best for reproducible enterprise setups.
- **Web UI** — fastest for one-off setup.

---

## Section 13 — Harness VS Code extension footprint is minimal

### The finding

Total Harness official VS Code extensions on the marketplace: **4**.

| Extension | Publisher | Installs | Purpose |
|---|---|---|---|
| Harness AI Code Assistant | `harness-inc` | ~3k | AIDA in VS Code |
| Harness (main) | `harness-inc` | ~430 | Repo browsing, PR review against Harness Code |
| Harness Gitspaces | `harness-inc` | ~500 | Cloud dev environments |
| Harness OSS Gitspaces | `harness-inc` | ~950 | OSS version |

Plus one useful third-party: `epherusindustries.harness-syntax-highlighter` (~180 installs) for pipeline YAML.

### AIDA install oddity

The `harness-inc.harness-aida-code-assistant-vsx` marketplace listing exists but `code --install-extension harness-inc.harness-aida-code-assistant-vsx` fails with "not found." Workaround: download the .vsix directly from the marketplace REST API and install locally.

### Product observation

Compared to JetBrains coverage (deeper Harness integration for years), the VS Code experience is thin. Given VS Code's dominance among admin-developer-adjacent tooling (SFDX for Salesforce is VS Code first), this is a real gap. Fixing it would help onboard Salesforce customers specifically.

---

## Section 14 — Windows clipboard chain-of-custody for base64 secrets

### The finding

The base64-encoded JWT private key for a Harness secret is ~2312 characters. Manual paste operations risk truncation or trailing-newline injection.

### Reliable pattern

```powershell
(Get-Content "C:\path\to\server.key.b64" -Raw).Trim() | Set-Clipboard
```

- `-Raw` preserves the file's contents as a single string (default reads line-by-line)
- `.Trim()` removes any trailing newline from the base64 file
- `Set-Clipboard` puts the exact string on the clipboard
- Then Ctrl+V into the target field

### Windows clipboard visibility

The Windows clipboard is invisible by default. To verify contents before pasting into a secure field:

- **Notepad** — Ctrl+V, inspect, then close without saving
- **Windows+V** — opens clipboard history if enabled

### Interview relevance

Any customer implementing Harness JWT secrets on Windows will hit this exact issue. A "helper" PowerShell script in the Harness docs would save a lot of debugging.

---

## Section 15 — SF instance URL: Dev Editions use `login.salesforce.com`, NOT `test.salesforce.com`

### The finding

Salesforce sandboxes authenticate via `test.salesforce.com`. Every SF DevOps tutorial defaults to this URL. **Developer Editions are not sandboxes** — they authenticate via `login.salesforce.com`.

### The trap

Original pipeline YAML defaults set validationInstanceUrl and sandboxInstanceUrl to `test.salesforce.com` (correct for a real customer scenario with real sandboxes). Running against a Dev Edition with those defaults produces:

```
invalid_grant: audience
```

...on the Authenticate step. This is a misleading error — it doesn't say "wrong instance URL," it says "audience" which sounds like a JWT payload issue.

### Fix

Set all three instance URL pipeline variables to `https://login.salesforce.com` for the demo. Real customer engagements use `test.salesforce.com` for their sandbox orgs.

---

## Section 16 — Playwright automation of SF setup is slower than manual walkthrough

### The finding

We attempted to Playwright-drive the SF External Client App creation for both orgs. Blockers hit:

1. SF UI hides "New Connected App" (Section 1) — required pivoting to ECA mid-automation
2. Modern SF Setup pages are iframe-heavy — snapshot references stale between steps
3. Each Playwright interaction requires: snapshot → analyze refs → click/type → wait → re-snapshot
4. Human-in-the-loop still needed for: email verification codes, initial browser session bootstrap

For SF forms specifically, **manual walkthrough turned out faster** than Playwright automation. Estimated wall-clock: 45 min manual vs. 90+ min Playwright including the debugging of navigation issues.

### Where Playwright would have won

Repetitive, predictable Harness UI clicks — creating 9 secrets, each with the same "New Secret → Text → Name → Value → Save" pattern. About 15 min of manual clicking. Would have been faster to automate but not compellingly so.

### Interview relevance

For a real customer, a Terraform-based Harness setup + a bulk SF Connected App creation via Metadata API (not UI) would be the enterprise-scale answer. The Playwright-of-UIs approach only helps for one-off demos.

---

## Section 17 — The Custom Deployment Template alternative for Harness Salesforce

### The finding

Harness has two paradigms for supporting Salesforce:

- **CI-based (what this repo uses):** Salesforce treated as a generic build target. `sf` CLI runs in CI stages. Pipeline-as-code lives in `.harness/*.yaml`. Approvals, secrets, and quick-deploy are all wired via Harness's CI primitives.
- **CD-based with Custom Deployment Template (CDT):** Salesforce becomes a first-class deployable *target* in Harness's CD module. Services and Environments become the abstraction. Rollback strategies, deployment freezes, and environment promotion policies apply natively.

Joe's existing Harness account already has a Salesforce Custom Deployment Template in progress (found in the CD module during setup). CDT is the more "Harness-native" path.

### Tradeoff

| Dimension | CI-based | CDT-based |
|---|---|---|
| Time to ship | 1 day | 1-2 weeks (real customer engagement) |
| Familiarity for developers | High (looks like GitHub Actions) | Lower (learn Harness CD primitives) |
| Enterprise fit | Basic | Native (Services, Environments, Freezes) |
| Rollback / observability | Manual | First-class in CD module |
| Interview signal | "I know Harness CI" | "I know Harness the way F500 customers use it" |

### Recommendation for interview

Ship the CI-based demo now (it works, it's testable, it's fast). Talk about CDT as the roadmap in the interview conversation — "here's what I shipped in a week, here's what the correct long-term shape looks like." Both artifacts in the same account together tell a story that neither tells alone.

---

## Appendix — Chronological decision log

Compressed timeline of decisions and pivots during the build.

| When | Decision | Why |
|---|---|---|
| Tue morning | Chose Docker Desktop on Windows for local delegate | Enterprise-realistic pattern; user was familiar with it |
| Tue afternoon | Pivoted to Harness Cloud runtime | AMD SVM off in BIOS + WSL2 missing (Section 10) |
| Tue afternoon | Discovered prior session had scaffolded 5-stage pipeline | Rewrote plan to build the dep-resolver instead (bigger differentiator) |
| Tue afternoon | Chose 2-org demo layout (dev + uat) | Skipped signing up for a 3rd Dev Edition — one dep-resolver demo covers the value |
| Tue afternoon | Chose `default_project` instead of new `salesforce_ecosystem` project | Kept the demo alongside the existing Salesforce CDT — both visible together |
| Wed morning | Pivoted from Connected Apps to External Client Apps | Modern SF UI blocks Connected App creation (Section 1) |
| Wed morning | Made `connectorRef` a runtime input | Harness silently downscoped the connector (Section 5) |
| Wed morning | Deleted existing pipeline YAML from git to unblock Save | Create-new-Pipeline flow collided with existing file (Section 7) |
| Wed midday | Skipped live pipeline execution | Harness Free tier requires sales contact for Cloud VM (Section 4) |
| Wed afternoon | Doubled down on artifact polish over live run | Dep-resolver + architecture doc + product brief win the interview more than a green pipeline check |
| Thu (planned) | Import second pipeline into Harness UI, record demo video, prep CI-vs-CDT talking point | Interview polish |
| Thu stretch | Attempt Oracle Cloud VM + self-hosted delegate | Only if all other Thursday work wraps early |

---

## What I'd change if starting over

- **Skip Playwright entirely.** Manual walkthrough is faster for Salesforce forms and equivalent for Harness. Two-hour save.
- **Start with the dep-resolver, not the pipeline.** The dep-resolver is the interview differentiator. Building the 5-stage pipeline first was a sunk cost — the incumbents already do all of that. Building novel work first would have given more time to polish it.
- **Test the pipeline auth locally before wiring Harness.** The `docs/connected-app-setup.md` local sanity test would have caught the `login.salesforce.com` vs `test.salesforce.com` issue 20 minutes into setup instead of finding it during first pipeline run.
- **Assume Harness Free tier is production-toy tier.** Check the actual feature gates on Day 1, not Day 3. Would have discovered the Cloud VM CC gate before committing to Harness Cloud runtime.

---

## What Harness could ship that would have saved me the most time

Ranked by hours-saved-per-hour-of-Harness-eng-work:

1. **Working self-serve payment / free-tier upgrade path.** ~4 hours of my life. Small feature.
2. **First-class Salesforce Connected/External Client App setup wizard in the Harness UI.** ~2 hours of my life. Also unblocks admin-developer adoption at customer sites — huge cross-sell surface.
3. **A "Salesforce Metadata Package" resource type** (first-class dep-graph aware). Weeks-to-months of work; multi-year cross-sell revenue.
4. **Clearer connector scope UX** — the URL Type vs Connector Scope terminology overloading (Section 5). Small fix, high leverage.
5. **Import-from-Git flow distinct from Create-new-Pipeline flow.** Just a UI change. High confusion cost today.

## What Salesforce could ship that would help

Not Harness's problem to fix, but noted for completeness:

- **A "New Connected App (Legacy)" button** in App Manager for orgs that need one, even if hidden behind an advanced setting. Every DevOps tool's docs still say "Connected App."
- **`invalid_grant: audience` should say `wrong instance URL`.** The current error message costs customers debugging time.
- **`sf CLI init-jwt-app` command** that automates ECA creation with the right OAuth policies and profile assignment. Would eliminate the "user hasn't approved this consumer" class of errors entirely.
