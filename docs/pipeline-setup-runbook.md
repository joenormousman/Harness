# Harness Salesforce Pipeline — Setup Runbook

End-to-end setup, from empty Harness project to a green pipeline run against both orgs. **~1-1.5 hours** if nothing surprises us.

**Prerequisite:** You already have a Kubernetes cluster (any distribution — GKE / EKS / AKS / minikube / kind / Docker Desktop with K8s) with a Harness Delegate running in it. The pipeline stages target `KubernetesDirect` infrastructure using that delegate — NOT `runtime.type: Cloud`, because Harness Free tier gates Cloud runtime behind sales-contact and delegate-executed pipelines are unrestricted. If you don't yet have a delegate, follow the Harness lab tutorial ([Kubernetes CI/CD quickstart](https://developer.harness.io/tutorials/cd-pipelines/kubernetes/manifest)) to set one up first.

**Terminology note:** Modern Salesforce (2024+) hides the "New Connected App" button in the App Manager UI. This runbook uses the newer **External Client App (ECA)** flow, which is functionally equivalent for JWT bearer auth. If you're setting up in an older org that still exposes Connected App creation, either pattern works — `sf org login jwt` doesn't care which underlying app type the client ID came from.

## Values you will need throughout

Keep this section open in a scratch pad while you work. Fill in the blanks as you go — several later phases paste values captured in earlier ones.

| Value | Source | Placeholder |
|---|---|---|
| Harness account URL | You | `https://app.harness.io/ng/account/YCn0jwaIRAy69HbA0IFaXw/` |
| Harness org | Harness | `default` |
| Harness project | Harness | `default_project` |
| GitHub repo | You | `https://github.com/joenormousman/Harness` |
| SF dev org URL | You | `https://orgfarm-5734ab275a-dev-ed.develop.lightning.force.com` |
| SF uat org URL | You | `https://orgfarm-b62abd18e9-dev-ed.develop.lightning.force.com` |
| SF instance URL (both) | Fact | `https://login.salesforce.com` (Dev Editions log in here, **not** test.salesforce.com) |
| JWT cert (`server.crt`) | Scratchpad | `C:\Users\joeno\AppData\Local\Temp\claude\c--Users-joeno-OneDrive-Documents-Harness\d118484a-1561-421e-99f6-4d37bd94a3fe\scratchpad\harness-jwt\server.crt` |
| JWT key base64 (`server.key.b64`) | Scratchpad | Same folder as above, `server.key.b64` |
| Dev org Consumer Key | Filled in Phase 1 | `_____` |
| Dev org integration username | Filled in Phase 1 | `_____` |
| Uat org Consumer Key | Filled in Phase 2 | `_____` |
| Uat org integration username | Filled in Phase 2 | `_____` |

**A note on secret counts.** The pipeline YAML references 9 secret identifiers (3 sets × 3 fields: `client_id`, `username`, `jwt_key_b64` for each of `validation`, `sandbox`, `prod`). In the 2-org demo layout, the `sandbox` and `prod` secret sets hold **the same values** — both point at the uat org. That's slightly wasteful but keeps the pipeline YAML clean; in a real customer engagement you'd either consolidate the pipeline references or point each set at a distinct org.

---

## Phase 1 — Salesforce External Client App: dev org

Full step-by-step in [`connected-app-setup.md`](connected-app-setup.md) (which describes the modern ECA flow). Summary here for continuity:

1. **Log in** to https://orgfarm-5734ab275a-dev-ed.develop.lightning.force.com as the admin. Note: your login username is the `.agentforce.com`-suffixed variant (Setup → Users → Users → **Username** column), NOT your display email.
2. **Setup gear (top right) → Setup → left-sidebar Quick Find `External Client Apps` → External Client App Manager → New External Client App**.
3. **Basic Information:**
   - External Client App Name: `Harness DX Deployer`
   - API Name: `Harness_DX_Deployer` (auto-fills)
   - Contact Email: your email
   - Distribution State: Local (default)
4. **Expand "API (Enable OAuth Settings)" section:**
   - Enable OAuth: **✅**
   - Callback URL: `http://localhost:1717/OauthRedirect` (never called for JWT, just required)
   - Use digital signatures: **✅** → **Upload `server.crt`** from the scratchpad path in the values table above
   - Selected OAuth Scopes (add all 3):
     - `Manage user data via APIs (api)`
     - `Manage user data via Web browsers (web)`
     - `Perform requests at any time (refresh_token, offline_access)`
   - Require Secret for Web Server Flow: **uncheck**
   - Require Secret for Refresh Token Flow: **uncheck**
5. **Click Create.** Salesforce warns "can take up to 10 min" — usually done in ~2 min. You land on the new ECA's page with **Policies** / **Settings** / **Package Defaults** tabs.
6. **Policies tab → Edit:**
   - App Authorization: `Admin approved users are pre-authorized` *(critical — JWT bearer will fail with `invalid_grant: user hasn't approved this consumer` if left at "All users can self-authorize")*
   - Expand OAuth Policies:
     - IP Relaxation: `Relax IP restrictions`
     - Refresh Token Policy: `Refresh token is valid until revoked`
   - **Save.**
7. **Assign profile:** on the same Policies page after saving, look for **"Manage Profiles"** (or check the Settings tab / fall back to Setup → Connected Apps OAuth Usage → Manage). Add **System Administrator**.
8. **Settings tab → Consumer Key & Secret → View** (may prompt for a 6-digit verification code emailed to your display email):
   - **Copy Consumer Key** (~85 chars starting `3MVG9…`). Fill it into your values table under `Dev org Consumer Key`.
   - You do NOT need the Consumer Secret — JWT bearer doesn't use it.
9. Fill in `Dev org integration username` from Setup → Users → Users → **Username** column.

**Checkpoint:** You have `Dev org Consumer Key` and `Dev org integration username` recorded.

---

## Phase 2 — Salesforce External Client App: uat org

Same steps as Phase 1, in the uat org. **Reuse the same `server.crt`** (one cert, both orgs — the demo can afford the shared trust; a customer engagement would generate per-org certs).

1. Log in to https://orgfarm-b62abd18e9-dev-ed.develop.lightning.force.com. **First login from a new browser/IP triggers a 6-digit email verification code** to your display email — grab it and check "Don't ask again" so subsequent sessions skip the challenge.
2. Repeat steps 2-9 from Phase 1.
3. Fill in `Uat org Consumer Key` and `Uat org integration username` in your values table.

**Checkpoint:** All 4 org-specific values in the table are populated.

---

## Phase 3 — Local JWT sanity test (highly recommended)

Prove JWT auth works from your laptop before wiring Harness. If this fails locally, it will fail in the pipeline for the same reason — but locally you can iterate fast.

Open PowerShell:

```powershell
$scratchDir = "C:\Users\joeno\AppData\Local\Temp\claude\c--Users-joeno-OneDrive-Documents-Harness\d118484a-1561-421e-99f6-4d37bd94a3fe\scratchpad\harness-jwt"
$env:SF_CLIENT_ID = "<paste Dev org Consumer Key>"
$env:SF_USERNAME = "<paste Dev org integration username>"
$env:SF_JWT_KEY_BASE64 = (Get-Content "$scratchDir\server.key.b64" -Raw).Trim()
$env:SF_INSTANCE_URL = "https://login.salesforce.com"
$env:SF_ORG_ALIAS = "validation"
cd "c:\Users\joeno\OneDrive\Documents\Harness"
bash scripts/auth-salesforce-jwt.sh
```

**Expected output:**
```
Authenticated Salesforce org alias: validation
```

Then verify:
```powershell
sf org display --target-org validation
```

Should show org details. **Repeat once for the uat org** (change `SF_ORG_ALIAS=uat` and use uat values).

**If it fails**, see the "Common gotchas" section in [`connected-app-setup.md`](connected-app-setup.md). Do not proceed to Phase 4 until this works — it will save you 30 min of debugging in the Harness UI.

**Checkpoint:** `sf org display` succeeds for both org aliases.

---

## Phase 4 — Harness secrets (×9)

In the Harness UI at https://app.harness.io/ng/account/YCn0jwaIRAy69HbA0IFaXw/:

1. **Navigate:** Project Setup (left sidebar) → **Secrets** → **New Secret → Text**.
2. **Create these 9 secrets**, each as a Text secret in `default_project`:

| Secret name | Value |
|---|---|
| `sf_validation_client_id` | Dev org Consumer Key |
| `sf_validation_username` | Dev org integration username |
| `sf_validation_jwt_key_b64` | Entire contents of `server.key.b64` (single line) |
| `sf_sandbox_client_id` | Uat org Consumer Key |
| `sf_sandbox_username` | Uat org integration username |
| `sf_sandbox_jwt_key_b64` | Same as `sf_validation_jwt_key_b64` (shared cert) |
| `sf_prod_client_id` | Uat org Consumer Key (same as sandbox) |
| `sf_prod_username` | Uat org integration username (same as sandbox) |
| `sf_prod_jwt_key_b64` | Same as `sf_validation_jwt_key_b64` |

Copy the base64 key exactly as it sits in `server.key.b64` — one line, no wrapping, no whitespace at the ends. In PowerShell:
```powershell
Get-Content "$scratchDir\server.key.b64" -Raw | Set-Clipboard
```
Then paste into the Harness secret value field.

**Checkpoint:** All 9 secrets visible under Project Setup → Secrets, each with a green "encrypted" indicator.

---

## Phase 5 — Import pipeline from GitHub

**IMPORTANT — choose "Import From Git", NOT "Create new Pipeline".** These are two different flows in Harness and they collide differently with an existing YAML file in git:

- **Import From Git** — Harness reads the existing YAML file at the specified path and treats it as authoritative. Save does a git-*update*-file API call. Works when the file already exists.
- **Create new Pipeline** with "Third-party Git provider" — Harness treats the location as *"a place to write a new file"* and does a git-*create*-file call, which errors with `.harness/…yaml does not match — File with given filepath already exists in Github` if the file is already there. Recovery is annoying.

Steps:

1. **Navigate:** Left sidebar → **Continuous Integration** or **Continuous Delivery** module (either works — the pipeline stages are CI-typed).
2. **Pipelines → New Pipeline → Import From Git.**
3. **Fill in:**
   - Pipeline Name: `Salesforce DX Governed Release`
   - GitHub Connector: `account.GitHub` (create if it doesn't exist — Personal Access Token is more reliable than OAuth for the initial setup)
   - Repository: `Harness` (just the repo name when the connector's URL includes the owner; use `joenormousman/Harness` if the connector is repo-scoped)
   - Branch: `main`
   - Yaml Path: `.harness/salesforce-dx-governed-release.yaml`
   - Pipeline Identifier: `Salesforce_DX_Governed_Release` (this must match the identifier in the YAML)
4. **Save & Import.**

If prompted about the GitHub connector, create one at `account.GitHub` (account-scoped). **Scope trap:** to create an account-scoped connector, first navigate to Account Settings → Account Resources → Connectors BEFORE clicking "New Connector". Creating one while inside a Project silently produces a project-scoped connector, no matter what the URL Type field says — that field describes GitHub URL layout (account URL vs repo URL), NOT Harness connector scope.

**Also import the input set** if the UI offers to: point at `.harness/release-candidate-input-set.yaml`. Otherwise create it manually later.

**Checkpoint:** Pipeline appears in the Pipelines list with a **Repository** code source badge (NOT Inline); opening it shows the 5 stages in the visual editor.

**Repeat for the second pipeline** at `.harness/feature-package-deploy.yaml` if you want the dep-resolver pipeline visible in the Harness UI too.

---

## Phase 6 — First run: Validate PR only

Prove the plumbing works end-to-end (sf CLI installs into the workspace on the delegate, JWT auth succeeds, `sf project deploy validate` runs against the dev org) before you dare production stages.

1. **Open the pipeline → Run.**
2. **In the input dialog** (the pipeline variables tab may need to be toggled to YAML view since `deployToSandbox`/`deployToProduction` have concrete defaults, not runtime inputs):
   - `deployToSandbox`: `false`
   - `deployToProduction`: `false`
   - Codebase inputs should auto-fill from the pipeline defaults (`account.GitHub`, `Harness`, branch `main`)
   - Leave everything else at defaults.
3. **Run.**

**Expected timing on a KubernetesDirect delegate (not Cloud runtime):**
- Pod scheduling + image pull for `node:22-slim`: 10-30s (first run per node), <5s cached
- Install Salesforce CLI (workspace install via `npm install --prefix ./sf-cli`): ~60s
- Check Salesforce Project: <5s
- Authenticate Validation Org: ~3s (with diagnostics printing the public-key SHA256 for verification)
- Validate Metadata: ~30-60s (deploy check + Apex tests via `sf project deploy validate --test-level RunLocalTests`)

**Total:** ~3-5 min for a green Validate PR run (includes pod scheduling).

**If it fails at Authenticate Validation Org with `invalid assertion`:** the base64 key in the Harness secret doesn't cryptographically match the cert uploaded to the SF ECA. Look at the diagnostic block in the step log — it prints the SHA256 of the public key derived from the decoded private key. Compare against the SHA256 of the cert you uploaded to the ECA (`openssl x509 -in server.crt -pubkey -noout | openssl pkey -pubin -pubout -outform DER | sha256sum`). If they don't match, one of them is wrong — either the secret was pasted incorrectly or the wrong cert was uploaded. If they DO match and JWT still fails, the ECA's App Authorization isn't set to "Admin approved users are pre-authorized" OR the System Administrator profile isn't assigned to the app.

**If it fails at Authenticate with `invalid_grant: audience`:** instance URL mismatch — Dev Editions use `login.salesforce.com`, sandboxes use `test.salesforce.com`. Confirm the pipeline variable defaults.

**If it fails at Install Salesforce CLI with `TypeError: webidl.util.markAsUncloneable is not a function`:** the base image is too old. Modern `sf` CLI's transitive `undici` dep requires Node 22+. Confirm the pipeline YAML uses `image: node:22-slim`, not `node:20-slim`.

**Checkpoint:** Green checkmark on the Validate PR stage. Screenshot this for the interview.

---

## Phase 7 — Full run: all 5 stages

Now the fun part. Deploys metadata into the uat org (as "sandbox"), validates the same org again (as "production"), waits for your approval, then quick-deploys.

1. **Open the pipeline → Run.**
2. **This time set:**
   - `deployToSandbox`: `true`
   - `deployToProduction`: `true`
   - `codebase.repoName`: `joenormousman/Harness`
   - `codebase.build`: `Branch` → `main`
3. **Run.**

**Timing:**
- Validate PR: ~2-3 min
- Deploy Sandbox: ~2-3 min (deploy + smoke test)
- Validate Production: ~2 min
- **Approve Production: WAITS FOR YOU** — the approval message shows validation status + job ID + Apex test counts. Approve it.
- Deploy Production: ~1-2 min (quick deploy, no re-run of tests)

**Total: ~10-15 min including the human approval pause.**

**Checkpoint:** Green pipeline. Screenshot the approval message — that's the "governance evidence" moment that lands well in the interview.

---

## Troubleshooting appendix

**"user hasn't approved this consumer"** at the JWT auth step
→ You skipped Phase 1 step 6 (assign profile). Go back to App Manager → Manage → Manage Profiles → check System Administrator.

**"invalid_grant: audience"**
→ Instance URL mismatch. Dev Editions use `login.salesforce.com`. Confirm the input set overrides all three instance URL variables to `https://login.salesforce.com`.

**"invalid_client_id"**
→ You copied the Consumer *Secret* instead of Consumer *Key*. Only the Key matters for JWT.

**Pipeline can't find the connector `account.GitHub`**
→ Create it: Account Settings → Connectors → New Connector → Code Repositories → GitHub → OAuth flow. Save with identifier `GitHub` (which becomes `account.GitHub` when referenced from a project pipeline).

**Pipeline errors on `Import from Git`: "identifier mismatch"**
→ The Pipeline Identifier in the UI must match `identifier: Salesforce_DX_Governed_Release` in the YAML. Retry with that exact string.

**Approval stage says "no approvers found"**
→ The default `account._account_all_users` group exists in every Harness account, but pipeline execution respects `disallowPipelineExecutor: true` — so *someone else* on your team must be able to approve. In a solo demo, temporarily set `disallowPipelineExecutor: false` in the pipeline YAML, or add a second user to the account.

**Deploy fails because the target org already has the metadata**
→ Fine — `sf project deploy validate` and `sf project deploy start` are idempotent for metadata like classes/fields/permsets. The pipeline will succeed as long as no destructive changes are pending.

---

## After Phase 7 succeeds

You have a fully functional 5-stage governed Salesforce release pipeline running on your Harness Delegate. That's the "traditional" pipeline. The **`Salesforce Feature Package Deploy`** pipeline (the dep-resolver demo — the interview differentiator) is a separate import — same steps as Phase 5, but pointing at `.harness/feature-package-deploy.yaml`. Uses the same delegate, same secrets, same GitHub connector — nothing new to provision.
