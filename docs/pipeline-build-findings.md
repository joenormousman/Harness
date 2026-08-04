# Pipeline Build — Findings & Lessons Learned

This document captures the surprises, blockers, and non-obvious decisions from building three pipelines in this repo:

1. **DevOpsForce Site** — a Kubernetes CI/CD pipeline built following the Harness lab tutorial (Docker build+push → blue/green deploy to GKE). **Runs green end-to-end.**
2. **Salesforce DX Governed Release** — a 5-stage governed Salesforce release pipeline (validate → sandbox → validate prod → approval → quick-deploy). Imported to Harness, structurally complete, JWT auth debugging outstanding.
3. **Salesforce Feature Package Deploy** — dep-resolver as a Harness pipeline stage. YAML committed to git; resolver runs green locally.

Plus a ~350-line Python metadata dependency-resolver (`scripts/resolve-dependencies.py`) that's the interview's product-thesis differentiator.

Written contemporaneously — every finding here is something the reference documentation either doesn't mention, mentions in the wrong place, or misrepresents.

**Timeframe:** Three working days ahead of the Harness Senior Implementation Engineer interview (2026-07-17). Built by one engineer against a Harness Free-tier account, a GKE cluster with a self-hosted Delegate, and two Salesforce Developer Editions.

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

### What we actually did

Pivoted to option 2. Retargeted both Salesforce pipelines from `runtime.type: Cloud` to `KubernetesDirect` infrastructure using the existing `gke_devopsforce` delegate already installed on the GKE cluster from the DevOpsForce lab work. Same delegate that runs the DevOpsForce Site pipeline in production. **The DevOpsForce Site pipeline runs green with no CC gate involvement** — delegate-executed pipelines don't consume Harness Cloud credits.

This ended up being the correct posture anyway. Enterprise Harness customers overwhelmingly run delegates (they need to reach private resources like Salesforce sandboxes behind IP allowlists), not Cloud runtime. The Free-tier CC gate ended up pushing us to the more enterprise-realistic architecture.

### Product observation

Harness's Free tier positioning is confused. It advertises Cloud Credits but doesn't let you spend them without a sales conversation. That's a bad first-impression for anyone evaluating Harness for a personal project or a POC — the exact segment that produces internal champions who later drive enterprise deals. **Fixing this is a small-scope, high-leverage product change.** In the meantime, the docs should surface the delegate path as the primary self-serve option for evaluators — right now delegate setup reads as an advanced-user path in the tutorials, when it's actually the *only* self-serve path for real pipeline execution today.

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

### What we actually did

Didn't touch the BIOS. Discovered mid-week that the Harness account already had a healthy `gke_devopsforce` delegate running on a GKE cluster from prior work. Retargeted every pipeline to that delegate instead. Local Docker Delegate would have been genuinely useful for offline development but wasn't required — cloud K8s + delegate is closer to the enterprise deployment pattern anyway.

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

## Section 18 — Node.js 20 → 22 required for modern sf CLI (undici transitively needs `webidl.util.markAsUncloneable`)

### The finding

First pipeline run against the delegate failed at the Authenticate Validation Org step (AFTER install-salesforce-cli.sh had successfully installed sf CLI 2.143.6 to the workspace):

```
TypeError: webidl.util.markAsUncloneable is not a function
    at new CacheStorage (undici/lib/web/cache/cachestorage.js:20:17)
```

### Root cause

Modern `@salesforce/cli` transitively depends on `undici`, which requires Node.js 22's `webidl.util.markAsUncloneable` API. Our pipeline steps ran in `node:20-slim` base image — the API doesn't exist there.

### Fix

Bumped the base image `node:20-slim` → `node:22-slim` across every Run step in both Salesforce pipelines (16 replacements in the governed-release YAML + 5 in the feature-package-deploy YAML). Node 22 is LTS as of 2024-10; safe pin.

### Production version

Bake a custom image (`joenormous/harness-sf-runner:v1`) with `sf` CLI + Node 22 + any other needed tools pre-installed, pin the pipeline to that image tag. Eliminates the ~60s-per-step sf CLI install AND locks the Node+CLI version together atomically, preventing this class of drift.

### Interview relevance

Container image pinning surfaces dependency issues that don't manifest on developer laptops (which run whatever `nvm` selected). **Pipeline images are best pinned at a specific *custom-baked* tag, not a base image tag** — because base image versions still drift underneath you every time the pipeline runs (`node:22-slim` is a moving tag, `node:22.13.1-slim` is not; a custom-built `joenormous/harness-sf-runner:v1` is even more locked).

---

## Section 19 — Kubernetes CI stages run each step in a separate container (`npm install -g` doesn't persist)

### The finding

Original `install-salesforce-cli.sh` did `npm install --global @salesforce/cli`. That worked on `runtime.type: Cloud` (all steps run on the same VM, share `/usr/bin` and `/usr/local/lib/node_modules`). On `KubernetesDirect` infrastructure, it silently failed to persist across steps: step 1 successfully installed sf CLI, step 2 got "sf: command not found".

### Root cause

In Harness Kubernetes CI stages, all steps run in the same pod but each step is a separate CONTAINER. The workspace volume (`/harness`) is shared across all steps via a mount; anything installed OUTSIDE that volume — like a global npm install into `/usr/local/lib/node_modules` — is scoped to that single container and doesn't persist to the next step's fresh container.

### Fix

Rewrote `scripts/install-salesforce-cli.sh` to install sf CLI *into the workspace*:

```bash
mkdir -p "$SF_CLI_HOME"  # $PWD/sf-cli
cd "$SF_CLI_HOME"
npm install --no-audit --no-fund "@salesforce/cli@${SF_CLI_VERSION}"
# ...writes sf-cli.env to workspace root with the PATH export
cat > "$WORKSPACE_ROOT/sf-cli.env" <<EOF
export PATH="$SF_CLI_HOME/node_modules/.bin:\$PATH"
EOF
```

Every downstream Run step in the pipeline starts its command with `source sf-cli.env`. That prepends the workspace-installed sf CLI to PATH, making `sf` resolve.

### Interview relevance

**Two-layer isolation model to know cold**: pods share workspace volume; containers within a pod don't share anything else. This is a well-known Kubernetes concept but bites CI users specifically because *most* CI systems (GitHub Actions, GitLab CI, Circle, Cloud Build) run all steps in the same container. Harness Kubernetes CI is different — closer to Tekton's Task+Step model — because it maximizes step-level image flexibility (one step can use `alpine:3.20`, another `node:22-slim`, another `python:3.11-slim`) at the cost of losing implicit sharing of installed tools.

### Product observation

Harness CI docs should call this out prominently. The docs currently emphasize per-step image flexibility as a feature (correctly), but don't warn about the persistence trap. Every customer coming from a single-container CI system will hit this within their first day.

---

## Section 20 — GKE Pod Security admission requires numeric UID, not named user, to verify `runAsNonRoot`

### The finding

The DevOpsForce Site pipeline's Deploy stage failed steady-state check with the same error, hundreds of times per rollout attempt:

```
Error: container has runAsNonRoot and image has non-numeric user
(nginx), cannot verify user is non-root
```

Blue deployment pods created, image pulled successfully, then rejected at admission time by K8s. `progress deadline exceeded` on the deployment; rollback swap-back triggered by `failureStrategies`.

### Root cause

GKE Pod Security admission checks `runAsNonRoot: true` by inspecting the container image's declared user. The base image `nginxinc/nginx-unprivileged:1.27-alpine` runs as the *named* user "nginx", which under the hood maps to UID 101 — but K8s admission has no way to resolve the string "nginx" to a UID without running the container. So it plays safe and rejects.

The pod template's `securityContext` had `runAsNonRoot: true` but no `runAsUser`. Setting `runAsUser` explicitly with a number tells admission the numeric UID up front, without needing to inspect the image.

### Fix

Added 4 lines to the pod template's `securityContext`:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 101   # matches nginx-unprivileged's internal UID
  runAsGroup: 101
```

### Sub-finding: the fix was in the local working copy, but never pushed to the actual git repo Harness was building from

This one surprised me. My local `devopsforce-site/` folder had the correct `deployment.yaml` with all four lines. Every pipeline run kept using the OLD deployment manifest. Root cause: `devopsforce-site/` in the Harness (Salesforce) repo working directory was untracked — the folder was a local scratchpad copy, NOT the actual `joenormousman/DevOpsForce` repo that Harness's pipeline pulls from. I'd been editing files in the wrong place all along.

Cloned `joenormousman/DevOpsForce`, diffed against the local scratch copy (only the deployment.yaml was actually different), copied the fix over, committed and pushed to the real repo (commit `31633c5`). Next pipeline run went green.

### Interview relevance

Two lessons here worth naming out loud:

1. **`runAsNonRoot` and image UID metadata are two different systems.** The image can genuinely be non-root at runtime while still failing admission. Explicit numeric UIDs in the pod spec are the belt-and-suspenders fix that always works.
2. **"The fix is on disk but the pipeline doesn't see it" is one of the most common real-world CI/CD failure modes.** It's usually because the working copy someone's editing isn't the git repo the pipeline actually pulls from — a subtle failure that takes a `git status` in the right directory to catch. In this case, `devopsforce-site/` in the wrong repo's working tree looked authoritative but wasn't tracked anywhere.

---

## Section 21 — Pipeline "Inline" vs "Repository" code source (git storage) is a first-day governance decision

### The finding

Harness pipelines have two storage models:

- **Inline** — YAML lives in Harness's own database; editing the pipeline in the UI saves server-side. No git involved.
- **Repository** — YAML lives at `.harness/pipeline.yaml` (or similar) in an external git repo. Editing writes to git; opening reads from git.

The Harness lab tutorial defaults to Inline. Every pipeline created via "Create new Pipeline" without explicit "Import from Git" ends up Inline. Our DevOpsForce Site pipeline is Inline; our Salesforce pipelines are Repository (stored in `joenormousman/Harness` at `.harness/*.yaml`).

### Tradeoffs

| | Inline | Repository |
|---|---|---|
| Setup | Fastest (no connector needed for authoring) | Need a git connector first |
| Iteration | Fast (server-side save) | Slower (git round-trip) |
| Git blame / history | None | Full |
| PR review of pipeline changes | Impossible | Standard git PR flow |
| Cross-account portability | Locked to one account | Same YAML in any account |
| Multi-branch pipeline testing | Impossible | Feature-branch a pipeline change |
| Backup / recovery | Trusts Harness DB backups | Trusts git |
| Auditor-friendly | Only Harness activity logs | Commit signatures + git blame |

### Interview relevance

For any customer engagement, **Repository storage is the correct posture on day one** — same argument as Terraform vs. click-ops. The lab tutorial's Inline default is fine for learning; it's not fine for anything that persists past the demo. Migration cost is small (Pipeline Settings → Move to Git in Harness). Worth calling out to customers early because the migration cost grows with pipeline complexity.

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
| Wed midday | Skipped live SF pipeline execution against Cloud runtime | Harness Free tier requires sales contact for Cloud VM (Section 4) |
| Wed afternoon | Doubled down on artifact polish over live SF pipeline run | Dep-resolver + architecture doc + product brief win the interview more than a green SF pipeline check |
| Thu morning | Discovered existing `gke_devopsforce` delegate on GKE cluster from prior lab work | Unlocked pipeline execution without touching BIOS or paying for Cloud VMs (Section 4, Section 10 update) |
| Thu morning | Retargeted both SF pipelines to `KubernetesDirect` on the delegate | Uses same infrastructure DevOpsForce Site was already running on |
| Thu midday | Rewrote install-salesforce-cli.sh for workspace-install pattern | K8s CI runs each step in separate container; global npm installs don't persist (Section 19) |
| Thu midday | Bumped pipeline base image `node:20-slim` → `node:22-slim` | Modern sf CLI's undici dep needs Node 22 API (Section 18) |
| Thu afternoon | Fixed DevOpsForce Site deployment.yaml with `runAsUser: 101` — pushed to actual DevOpsForce repo | Local fix was in wrong repo; pipeline was still pulling old manifest (Section 20) |
| Thu afternoon | Regenerated JWT cert v2 + added public-key SHA256 fingerprint diagnostics to auth script | Prior cert failed with `invalid_assertion`; couldn't rule out cert/key mismatch without diagnostics |
| Thu afternoon | Deferred SF pipeline cert propagation (~15 min work) | Better ROI on interview cheat sheet + talk track polish given Fri interview |
| Thu afternoon | DevOpsForce Site pipeline green end-to-end | Lab items 1-4 satisfied; bonus item 5 satisfied by existing `K8s_HTTP_Health_Check` template already in use |
| Thu evening | Wrote interview cheat sheet, rewrote talk track, revised findings/runbook/brief | Fri interview readiness |

---

## What I'd change if starting over

- **Skip Playwright entirely.** Manual walkthrough is faster for Salesforce forms and equivalent for Harness. Two-hour save.
- **Start with the dep-resolver, not the pipeline.** The dep-resolver is the interview differentiator. Building the 5-stage pipeline first was a sunk cost — the incumbents already do all of that. Building novel work first would have given more time to polish it.
- **Test the pipeline auth locally before wiring Harness.** The `docs/connected-app-setup.md` local sanity test would have caught the `login.salesforce.com` vs `test.salesforce.com` issue 20 minutes into setup instead of finding it during first pipeline run.
- **Assume Harness Free tier is production-toy tier.** Check the actual feature gates on Day 1, not Day 3. Would have discovered the Cloud VM CC gate before committing to Harness Cloud runtime.
- **Bake a custom pipeline base image on day 1.** `joenormous/harness-sf-runner:v1` with sf CLI + Node 22 + Python 3 pre-installed. Saves 60s per stage on every future run AND prevents the Node-version drift class of bug (Section 18). Also lets me pin `sf` + Node + Python versions atomically as one image tag.
- **Verify which git repo the pipeline actually pulls from before editing anything.** The DevOpsForce fix took an extra round-trip because I was editing files in a local scratchpad that wasn't tracked in the pipeline's actual source repo (Section 20 sub-finding). One `git remote -v` at the start would have saved 20 minutes of "why doesn't the fix take."
- **Choose Repository (git-stored) pipelines from day one for anything past the tutorial.** Inline pipelines are fine for lab exercises; they're not fine for anything a customer will inherit or audit (Section 21).

---

## What Harness could ship that would have saved me the most time

Ranked by hours-saved-per-hour-of-Harness-eng-work:

1. **Working self-serve payment / free-tier upgrade path.** ~4 hours of my life. Small feature.
2. **First-class Salesforce Connected/External Client App setup wizard in the Harness UI.** ~2 hours of my life. Also unblocks admin-developer adoption at customer sites — huge cross-sell surface.
3. **A "Salesforce Metadata Package" resource type** (first-class dep-graph aware). Weeks-to-months of work; multi-year cross-sell revenue.
4. **Clearer connector scope UX** — the URL Type vs Connector Scope terminology overloading (Section 5). Small fix, high leverage.
5. **Import-from-Git flow distinct from Create-new-Pipeline flow.** Just a UI change. High confusion cost today (Section 7).
6. **Docs page on K8s CI's per-step-container model + workspace-install pattern.** Every customer coming from GitHub Actions / GitLab / Circle CI will hit the "tools installed in step 1 aren't in step 2" trap (Section 19). One good docs page prevents the problem entirely.
7. **Pipeline base-image recommendations for common stacks (Salesforce, Terraform, .NET, etc.).** Right now customers reinvent per-step base images and hit version drift like the Node 20 vs 22 issue (Section 18). A small `harness/base-images` GitHub org with maintained tags would cover this.
8. **A `runbook` / `field guide` doc series** written for the "just discovered the delegate model can bypass Cloud runtime CC gate" moment — because right now delegate setup reads as an advanced-user path in the tutorials when it's actually the *only* self-serve path for real pipeline execution today.

## What Salesforce could ship that would help

Not Harness's problem to fix, but noted for completeness:

- **A "New Connected App (Legacy)" button** in App Manager for orgs that need one, even if hidden behind an advanced setting. Every DevOps tool's docs still say "Connected App."
- **`invalid_grant: audience` should say `wrong instance URL`.** The current error message costs customers debugging time.
- **`sf CLI init-jwt-app` command** that automates ECA creation with the right OAuth policies and profile assignment. Would eliminate the "user hasn't approved this consumer" class of errors entirely.
