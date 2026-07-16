# Harness Salesforce DX Release Demo

This repo is a technical interview demo for a governed Salesforce release pipeline built on Harness.

It shows how Harness can make a Salesforce ecosystem better supported by giving Salesforce metadata the same delivery controls as product code: repeatable validation, secret-backed org authentication, sandbox promotion, production approval, quick deploy, smoke testing, and auditable release evidence.

## What The Demo Builds

The demo has six parts:

- Salesforce DX metadata in `force-app/` — Apex + PermissionSet + `Release_Signal__c` object with real cross-dependencies (custom field → validation rule → permission set).
- Reusable CI scripts in `scripts/` (7 shell + 2 Node helpers + 1 Python dep-resolver).
- **Governed release pipeline** at `.harness/salesforce-dx-governed-release.yaml` — 5 stages, JWT-authenticated, approval-gated quick-deploy pattern.
- **Feature package deploy pipeline** at `.harness/feature-package-deploy.yaml` — single-stage pipeline that runs the metadata dep-resolver against a seed manifest, expands it to a full package.xml, and deploys only the resolved subset. This is the interview differentiator.
- Setup runbooks in `docs/` (Connected App / External Client App setup, 7-phase pipeline setup, dep-graph architecture, and a 1-page product brief).
- Setup and interview notes in this README.

The two pipelines together answer *"what does Harness Salesforce support look like today, and what does the missing intelligence layer look like once it's built?"*

## Pipeline Flow

1. `Validate Pull Request`

   Harness clones the repo, installs a pinned Salesforce CLI, runs local project checks, authenticates to a validation org with JWT, previews the deployment, and runs `sf project deploy validate`.

2. `Deploy Sandbox`

   If `deployToSandbox` is `true`, Harness deploys the metadata into a release sandbox with `sf project deploy start`, then runs `HarnessReleaseHealthTest` as a smoke test.

3. `Validate Production`

   If `deployToProduction` is `true`, Harness performs a production check-only validation and exports the Salesforce validated deployment job ID.

4. `Approve Production`

   A Harness approval stage shows the production validation status, commit, test count, and validation job ID before release managers approve. The executor is blocked from approving their own production run.

5. `Deploy Production`

   Harness uses `sf project deploy quick` with the validated production job ID, then runs the smoke test against production.

## Harness Setup

Create or update these Harness resources:

- Git connector referenced by the pipeline as `account.GitHub`.
- Runtime repo input in the format `<github-org>/<repo>`.
- Project `default_project` under org `default` (the pipeline YAML uses these identifiers; adjust if your account differs).
- A production approver group, then set `productionApproverGroup`.
- Harness text secrets listed in `config/harness-secrets.example.json`.

Expected secret identifiers:

- `sf_validation_client_id`
- `sf_validation_username`
- `sf_validation_jwt_key_b64`
- `sf_sandbox_client_id`
- `sf_sandbox_username`
- `sf_sandbox_jwt_key_b64`
- `sf_prod_client_id`
- `sf_prod_username`
- `sf_prod_jwt_key_b64`

The JWT key secrets are base64-encoded private keys. On macOS or Linux:

```bash
base64 -w 0 server.key
```

On PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("server.key"))
```

## Salesforce Setup

For each target org:

1. Create or reuse a Salesforce connected app.
2. Enable OAuth settings.
3. Upload the certificate that matches the JWT private key.
4. Grant the integration user access to the connected app.
5. Store the connected app consumer key, integration username, and base64 private key in Harness secrets.

The pipeline uses these CLI commands:

- `sf org login jwt` for non-interactive org authentication.
- `sf project deploy preview` for release visibility.
- `sf project deploy validate` for check-only validation.
- `sf project deploy start` for sandbox deployment.
- `sf project deploy quick` for production deployment after validation.
- `sf apex run test` for a post-deploy smoke test.

## Local Checks

Run the repo sanity check locally:

```bash
node scripts/check-salesforce-project.mjs
```

Run a validation locally after setting org auth:

```bash
export TARGET_ORG=validation
export SOURCE_DIR=force-app
export TEST_LEVEL=RunLocalTests
bash scripts/validate-metadata.sh
```

## Interview Talk Track

The short version:

> Salesforce changes are often business-critical but managed outside the same delivery governance as app code. I would use Harness to standardize Salesforce delivery around reusable pipeline templates, org-specific secrets, validation-first production releases, approval evidence, and post-deploy smoke tests. That gives product teams a foundation for safer Salesforce ecosystem support without slowing release teams down.

The technical version:

> The important design choice is separating validation, deployment, and approval. Production deploy is not a blind deploy; it is a quick deploy from a successful check-only validation, and the approval step is tied to the validation evidence. That creates an audit trail, reduces production deploy time, and lets Harness become the system of record for Salesforce release governance.

Product direction to discuss:

- Native Salesforce DX pipeline templates for common org topologies.
- First-class Salesforce org environments and deployment evidence.
- Metadata diff summaries in approval messages.
- Reusable connected-app/JWT setup guidance.
- Package promotion support for unlocked packages and managed packages.
- Salesforce-specific rollback playbooks, including destructive changes and package version rollback.
- Release dashboards that connect Harness executions to Salesforce deployment IDs, Apex test results, and org-level health.

## Files To Open In The Interview

- `.harness/salesforce-dx-governed-release.yaml`
- `scripts/validate-metadata.sh`
- `scripts/deploy-metadata.sh`
- `scripts/auth-salesforce-jwt.sh`
- `force-app/main/default/classes/HarnessReleaseHealthTest.cls`

## Source References

- Harness CI Run steps: https://developer.harness.io/docs/continuous-integration/use-ci/run-step-settings/
- Harness Cloud build infrastructure: https://developer.harness.io/docs/continuous-integration/use-ci/set-up-build-infrastructure/use-harness-cloud-build-infrastructure/
- Harness manual approval stages: https://developer.harness.io/docs/platform/approvals/adding-harness-approval-stages/
- Harness secrets: https://developer.harness.io/docs/platform/secrets/add-use-text-secrets
- Salesforce deploy start: https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_deploy_start.html
- Salesforce deploy preview: https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_deploy_preview.html
