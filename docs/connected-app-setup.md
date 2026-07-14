# Salesforce Connected App Setup (JWT Bearer Flow)

This walkthrough sets up one Connected App per org so the Harness pipeline can authenticate non-interactively via JWT bearer. Repeat for each of validation, sandbox, and production orgs.

**Total time:** ~10-15 min per org after the first (first one takes ~20 min while you learn the screens).

**One cert or three?** The pipeline works either way. For the demo, reusing one cert across all three orgs is fine and simpler. For production-real, generate a separate cert per org. The scaffold already generated one cert; instructions below assume you're reusing it. If you want per-org certs, regenerate with a different `CN=` per org.

---

## Prerequisites

- Cert already generated: `server.crt` and `server.key` (see below for location).
- Cert location on this machine:
  `C:\Users\joeno\AppData\Local\Temp\claude\c--Users-joeno-OneDrive-Documents-Harness\d118484a-1561-421e-99f6-4d37bd94a3fe\scratchpad\harness-jwt\`
- Base64-encoded private key: `server.key.b64` (single line, no newlines) — goes into Harness secrets.
- **Never commit the private key to git.** The repo's `.gitignore` already excludes `*.key` and `*.pem`.

---

## Steps per org

### 1. Log into the target org

For each org, log in as the admin (the account you used to sign up):

- Validation (`dev`): https://orgfarm-5734ab275a-dev-ed.develop.lightning.force.com
- Sandbox (`uat`): https://orgfarm-b62abd18e9-dev-ed.develop.lightning.force.com
- Production: (spin up a 3rd Dev Edition, TBD)

### 2. Create the Connected App

Setup (gear icon top right) → App Manager → **New Connected App** → **Create a Connected App**.

Fill in:

- **Connected App Name:** `Harness DX Deployer`
- **API Name:** `Harness_DX_Deployer` (auto-fills)
- **Contact Email:** your email
- **Enable OAuth Settings:** ✅ check
- **Callback URL:** `http://localhost:1717/OauthRedirect` (never actually called for JWT flow, but required)
- **Use digital signatures:** ✅ check → Upload the `server.crt` file from the scratch location above
- **Selected OAuth Scopes:** add these:
  - `Manage user data via APIs (api)`
  - `Manage user data via Web browsers (web)`
  - `Perform requests at any time (refresh_token, offline_access)`
- **Require Secret for Web Server Flow:** uncheck (JWT bypasses this)
- **Require Secret for Refresh Token Flow:** uncheck

Save → wait ~2 minutes for the app to provision (Salesforce warns you it can take up to 10 min; usually seconds to 2 min).

### 3. Configure OAuth policies (crucial — controls who can auth via JWT)

Setup → App Manager → find your app → dropdown arrow → **Manage** → **Edit Policies**.

Set:

- **Permitted Users:** `Admin approved users are pre-authorized`
- **IP Relaxation:** `Relax IP restrictions`
- **Refresh Token Policy:** `Refresh token is valid until revoked`

Save.

### 4. Assign the app to a profile or permission set

Same page (Manage view) → scroll to **Profiles** section → **Manage Profiles** → check `System Administrator` → Save.

(Or **Manage Permission Sets** if you want to be more granular — for demo, System Admin is fine.)

### 5. Capture the Consumer Key (client_id)

Setup → App Manager → your app → dropdown → **View** → **Manage Consumer Details** (may require Salesforce to email you a verification code).

Copy the **Consumer Key** — this is your `SF_CLIENT_ID`. It looks like:
`3MVG9...`  (~85 characters)

### 6. Capture the integration username

For a Dev Edition, this is the email address you signed up with (also visible under Setup → Users). Copy it verbatim (case-sensitive).

### 7. Store in Harness secrets

In Harness (once you have the account URL), create the three secrets for this org:

| Secret identifier | Value |
|---|---|
| `sf_<role>_client_id` | Consumer Key from step 5 |
| `sf_<role>_username` | Integration username from step 6 |
| `sf_<role>_jwt_key_b64` | Contents of `server.key.b64` (paste as one line) |

Where `<role>` is one of `validation`, `sandbox`, or `prod` — matching the pipeline variable names.

### 8. Local sanity test (optional but recommended)

Before wiring up Harness, verify JWT auth works locally using the same script the pipeline runs:

```powershell
$env:SF_CLIENT_ID = "<consumer-key-from-step-5>"
$env:SF_USERNAME = "<username-from-step-6>"
$env:SF_JWT_KEY_BASE64 = (Get-Content "<path-to-server.key.b64>" -Raw).Trim()
$env:SF_INSTANCE_URL = "https://login.salesforce.com"  # Dev Editions use login.salesforce.com; test.salesforce.com is for sandboxes
$env:SF_ORG_ALIAS = "validation"
bash scripts/auth-salesforce-jwt.sh
```

If successful, you'll see: `Authenticated Salesforce org alias: validation` and `sf org display --target-org validation` will show the org details.

**Note:** For fresh Dev Editions, the instance URL is `https://login.salesforce.com`, not `https://test.salesforce.com`. The pipeline YAML currently defaults `validationInstanceUrl` and `sandboxInstanceUrl` to `test.salesforce.com` — override these in the input set to `login.salesforce.com` for Dev Edition orgs, or update the pipeline defaults.

---

## Common gotchas

- **"user hasn't approved this consumer"** — you skipped step 4 (assign to profile). Go back and assign System Administrator.
- **"invalid_grant: audience"** — instance URL mismatch. Dev Editions use `login.salesforce.com`; sandboxes use `test.salesforce.com`.
- **"invalid_client_id"** — you copied the Consumer Secret instead of the Consumer Key. Only the Consumer Key matters for JWT.
- **"invalid_grant: user hasn't approved this consumer"** on first auth after creating the app — sometimes Salesforce needs 2-10 min to propagate the profile assignment. Wait and retry.

---

## Interview talking point

When explaining this in the interview, the key pattern is:

> Salesforce doesn't have first-class OIDC or short-lived tokens for service accounts. The industry-standard non-interactive auth pattern is JWT bearer flow with a self-signed cert uploaded to a Connected App per org. Harness stores the base64-encoded private key as a secret and injects it into the pipeline at runtime. This is the same pattern Copado and Gearset use under the hood — the difference is that they wrap it in a UI so admins never see it, while Harness today expects you to know it.
