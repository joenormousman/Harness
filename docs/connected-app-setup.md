# Salesforce External Client App Setup (JWT Bearer Flow)

This walkthrough sets up one External Client App (ECA) per org so the Harness pipeline can authenticate non-interactively via JWT bearer. Repeat for each of validation, sandbox, and production orgs (or, in a 2-org demo layout, dev and uat).

**Total time:** ~10-15 min per org after the first (first one takes ~20 min while you learn the screens).

## Why External Client Apps, not Connected Apps

Modern Salesforce (2024+) hides "New Connected App" creation in the UI. App Manager exposes only *New Lightning App* and *New External Client App* buttons; the classic `/setup/mgmt/newconnectedapp.apexp` URL is intercepted and redirects. External Client Apps are Salesforce's canonical replacement — they support the same JWT bearer flow, the same `Consumer Key`/`Consumer Secret` pair, and the same certificate-based auth. `sf org login jwt` accepts an ECA's client_id transparently.

If you're setting this up in an older org that still allows Connected App creation, either pattern works — the pipeline is auth-mechanism-agnostic.

## Prerequisites

- Cert generated: `server.crt` and `server.key` (see the setup runbook for `openssl` generation).
- Base64-encoded private key: `server.key.b64` (single line, no newlines) — goes into Harness secrets.
- **Never commit the private key to git.** The repo's `.gitignore` excludes `*.key` and `*.pem`.

**One cert or per-org?** For the demo, reusing one cert across all orgs is fine and simpler. For production-real, generate a separate cert per org. Instructions below assume you're reusing one; if you want per-org certs, regenerate with a different `CN=` per org.

---

## Steps per org

### 1. Log into the target org as admin

Each org has a login URL like `https://orgfarm-<hash>-dev-ed.develop.lightning.force.com`. Log in with the admin account you signed up with (Dev Editions add a suffix to your display email — the login username looks like `joe.24c4020f12c1@agentforce.com`, not `joe@yourdomain.com`; check under Setup → Users → Users → your row → **Username** column if you're not sure).

### 2. Navigate to External Client App Manager

Setup gear (top right) → Setup → left-sidebar **Quick Find** → type `External Client Apps` → click **External Client App Manager**.

Direct URL if the sidebar navigation is slow: `/lightning/setup/NavigationMenus/home` will take you to App Manager, from which the **New External Client App** button lives at top-right.

### 3. Click **New External Client App**

You land on the create form with an expanded **Basic Information** section and several collapsed sections below (API/OAuth, SAML, Canvas, Mobile, Push, Notifications).

### 4. Fill Basic Information

| Field | Value |
|---|---|
| External Client App Name | `Harness DX Deployer` |
| API Name | `Harness_DX_Deployer` (auto-fills — leave as-is) |
| Contact Email | your email |
| Distribution State | Local (default) |

Leave Contact Phone, URLs, Logo, Icon, Description empty.

### 5. Expand **API (Enable OAuth Settings)** and configure

Click the section header to expand.

- **Enable OAuth**: ✅ check
- **Callback URL**: `http://localhost:1717/OauthRedirect` (never actually called for JWT bearer flow, but the form requires a value)
- **Use digital signatures**: ✅ check → **Upload File** → select your `server.crt` from the scratchpad location
- **Selected OAuth Scopes** (move all three from Available → Selected):
  - `Manage user data via APIs (api)`
  - `Manage user data via Web browsers (web)`
  - `Perform requests at any time (refresh_token, offline_access)`
- **Require Secret for Web Server Flow**: ❌ uncheck
- **Require Secret for Refresh Token Flow**: ❌ uncheck

### 6. Create

Click **Create** at the bottom. Salesforce may warn "propagation can take up to 10 min" — usually done in ~2 min. You'll land on the app's summary page.

### 7. Configure Policies (critical for JWT to work)

You're on the **Policies** tab of your new app.

1. Click the **Edit** button (top right of the Policies section)
2. Change **App Authorization** from *"All users can self-authorize"* to **"Admin approved users are pre-authorized"** — this is the ECA equivalent of the classic Connected App's "Permitted Users" policy, and is **required** for JWT bearer to work non-interactively
3. Expand the **OAuth Policies** subsection (the collapsed one at the bottom of the Policies tab):
   - **IP Relaxation**: `Relax IP restrictions`
   - **Refresh Token Policy**: `Refresh token is valid until revoked`
4. Click **Save**

**If you skip this step**, the pipeline auth will fail at runtime with `invalid_grant: user hasn't approved this consumer`.

### 8. Assign the app to your integration user's profile

Because step 7 flipped App Authorization to "Admin approved users are pre-authorized", nobody can auth via this app until you explicitly authorize them. Two possible places in the ECA UI (SF is still shipping this feature):

- **Option A:** On the Policies page, look for a **"Manage Profiles"** or **"Profile Access"** link/button
- **Option B:** Click over to the **Settings** tab — look for a "Manage Profiles" / "App Access" section
- **Option C fallback:** Setup → Quick Find `Connected Apps OAuth Usage` → find `Harness DX Deployer` in the list → click **Manage**

Add **System Administrator** as the authorized profile. Save.

### 9. Capture the Consumer Key

1. On the app page, click the **Settings** tab
2. Find the **Consumer Key & Secret** section
3. Click **View** (may prompt for a 6-digit verification code emailed to the org admin — grab it and paste)
4. **Copy the Consumer Key** — a long string starting `3MVG9...` (~85 chars). This becomes the `sf_*_client_id` Harness secret.
5. **You do NOT need the Consumer Secret** — JWT bearer flow doesn't use it. It's fine to leave it in place, but if it hits a chat log or an email, rotate it via the same Settings screen post-demo.

### 10. Local sanity test (optional but recommended)

Before wiring up Harness, verify JWT auth works locally using the same script the pipeline runs:

```powershell
$scratchDir = "C:\Users\joeno\AppData\Local\Temp\claude\c--Users-joeno-OneDrive-Documents-Harness\d118484a-1561-421e-99f6-4d37bd94a3fe\scratchpad\harness-jwt"
$env:SF_CLIENT_ID = "<paste Consumer Key from step 9>"
$env:SF_USERNAME = "<the .agentforce.com login username, not your display email>"
$env:SF_JWT_KEY_BASE64 = (Get-Content "$scratchDir\server.key.b64" -Raw).Trim()
$env:SF_INSTANCE_URL = "https://login.salesforce.com"  # Dev Editions use login; sandboxes use test.salesforce.com
$env:SF_ORG_ALIAS = "validation"
bash scripts/auth-salesforce-jwt.sh
```

Expected output: `Authenticated Salesforce org alias: validation`. Then `sf org display --target-org validation` shows the org details.

**If it fails**, see "Common gotchas" below. Do not proceed to wiring Harness until this works — it will save you 30 min of debugging in the Harness UI.

---

## Common gotchas

**`invalid_grant: user hasn't approved this consumer`**
→ You skipped Step 7 (App Authorization → Admin approved) or Step 8 (profile assignment). Go back and complete both.

**`invalid_grant: audience`**
→ Instance URL mismatch. Dev Editions use `login.salesforce.com`; sandboxes use `test.salesforce.com`. Confirm your pipeline input set overrides all three instance URL variables to match your org type.

**`invalid_client_id`**
→ You copied the Consumer **Secret** instead of Consumer **Key**. Only the Key matters for JWT.

**Verification code prompt at step 9 loops or times out**
→ Salesforce sometimes emails the code to the org admin's *display email*, not the login username. Check the inbox at the email address you signed up with.

**"Profile already has this connected app" message during step 8**
→ Fine — the app was already assigned. Move on.

---

## Interview talking point

When explaining this in the interview, the pattern is:

> Salesforce doesn't have first-class OIDC or short-lived tokens for service accounts. The industry-standard non-interactive auth pattern is JWT bearer flow with a self-signed cert uploaded to a Connected App or External Client App per org. Harness stores the base64-encoded private key as a secret and injects it into the pipeline at runtime.

> This is the same pattern Copado and Gearset use under the hood — the difference is that they wrap it in a UI so admin-developers never see it. Harness today expects you to know it, which is a real friction point for the admin-developer audience. That's part of the wedge — a better first-class Salesforce credential setup wizard in Harness would remove the biggest onboarding hurdle for those customers.
