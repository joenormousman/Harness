# Salesforce Harness Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a technical Salesforce DX demo that shows a governed Harness pipeline from validation through production quick deploy.

**Architecture:** Use a small Salesforce DX metadata project plus reusable Bash scripts. Harness CI stages call those scripts on Harness Cloud runners and pass the production validation job ID through output variables into approval and quick deploy stages.

**Tech Stack:** Harness CI/CD YAML, Salesforce CLI, Salesforce DX source format, Bash, Node.js helper scripts.

## Global Constraints

- Keep credentials out of source; use Harness secrets only.
- Use JWT auth for non-interactive Salesforce org login.
- Use `sf project deploy validate` before production approval.
- Use `sf project deploy quick` for production deployment.
- Keep metadata intentionally small so the pipeline remains the focus.

---

### Task 1: Salesforce DX Project

**Files:**
- Create: `sfdx-project.json`
- Create: `.forceignore`
- Create: `manifest/package.xml`
- Create: `force-app/main/default/classes/HarnessReleaseHealth.cls`
- Create: `force-app/main/default/classes/HarnessReleaseHealthTest.cls`
- Create: `force-app/main/default/permissionsets/Harness_Release_Observer.permissionset-meta.xml`

- [x] Add minimal deployable metadata with Apex test coverage.
- [x] Add package manifest and Salesforce DX project config.
- [x] Keep generated files, keys, and local Salesforce state ignored.

### Task 2: CI Scripts

**Files:**
- Create: `scripts/install-salesforce-cli.sh`
- Create: `scripts/auth-salesforce-jwt.sh`
- Create: `scripts/validate-metadata.sh`
- Create: `scripts/deploy-metadata.sh`
- Create: `scripts/run-apex-smoke-test.sh`
- Create: `scripts/check-salesforce-project.mjs`
- Create: `scripts/extract-salesforce-deploy-result.mjs`

- [x] Install a pinned Salesforce CLI version.
- [x] Authenticate to target orgs with JWT and base64 key material from secrets.
- [x] Validate, deploy, quick deploy, and smoke test through separate scripts.
- [x] Export deployment job IDs and statuses for Harness output variables.

### Task 3: Harness Pipeline

**Files:**
- Create: `.harness/salesforce-dx-governed-release.yaml`
- Create: `.harness/release-candidate-input-set.yaml`
- Create: `config/harness-secrets.example.json`

- [x] Add PR validation stage.
- [x] Add sandbox deployment stage.
- [x] Add production validation stage that exports the validation job ID.
- [x] Add production approval stage with validation evidence.
- [x] Add production quick deploy stage.

### Task 4: Interview Docs

**Files:**
- Create: `README.md`
- Create: `docs/interview-talk-track.md`

- [x] Document setup steps.
- [x] Document the demo walkthrough.
- [x] Include product-team discussion points.
- [x] Include source references.
