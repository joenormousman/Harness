#!/usr/bin/env bash
set -euo pipefail

: "${TARGET_ORG:?Set TARGET_ORG to a Salesforce org alias or username.}"

SOURCE_DIR="${SOURCE_DIR:-force-app}"
TEST_LEVEL="${TEST_LEVEL:-RunLocalTests}"
WAIT_MINUTES="${WAIT_MINUTES:-60}"
PREVIEW_PATH="${PREVIEW_PATH:-deployment-preview.json}"
REPORT_PATH="${REPORT_PATH:-deployment-validation.json}"

# --- Pre-flight diagnostics (safe to log; no secrets exposed) ---
echo "=== validate-metadata pre-flight ==="
echo "  TARGET_ORG:  ${TARGET_ORG}"
echo "  SOURCE_DIR:  ${SOURCE_DIR}"
echo "  HOME:        ${HOME:-<unset>}"
echo "  PWD:         ${PWD}"
echo "  sf version:  $(sf --version 2>&1 | head -1)"
echo "  ~/.sf/ contents (should have config.json + orgs/ if auth persisted):"
ls -la "${HOME}/.sf/" 2>&1 | sed 's/^/    /' || echo "    (no ~/.sf/ directory found — auth state did NOT persist across step containers)"
echo "  sf org list --json (looking for the '${TARGET_ORG}' alias):"
sf org list --json 2>&1 | head -50 | sed 's/^/    /' || echo "    (sf org list failed)"
echo "=== end pre-flight ==="
echo ""

# preview: informational only ("here's what would deploy"). Requires source
# tracking, which Dev Edition orgs don't have (only scratch orgs and
# source-tracking-enabled sandboxes). Non-blocking — if preview fails we
# log it and move on; the actual validate below is what gates the pipeline.
echo "=== sf project deploy preview (informational, non-blocking) ==="
set +e
sf project deploy preview \
  --target-org "$TARGET_ORG" \
  --source-dir "$SOURCE_DIR" \
  --json > "$PREVIEW_PATH" 2>&1
preview_exit=$?
set -e
if [[ "$preview_exit" -ne 0 ]]; then
  echo "preview skipped (exit ${preview_exit}) — this is expected on Dev Editions and other non-source-tracked orgs. Continuing to validate:"
  cat "$PREVIEW_PATH" 2>&1 | sed 's/^/  /' | head -20
else
  echo "preview completed OK"
fi

set +e
sf project deploy validate \
  --target-org "$TARGET_ORG" \
  --source-dir "$SOURCE_DIR" \
  --test-level "$TEST_LEVEL" \
  --wait "$WAIT_MINUTES" \
  --json > "$REPORT_PATH"
deploy_exit=$?
set -e

node scripts/extract-salesforce-deploy-result.mjs "$REPORT_PATH" > deployment-validation.env
source deployment-validation.env

echo "Validation status: ${DEPLOY_STATUS}"
echo "Validation job ID: ${VALIDATION_JOB_ID}"
echo "Apex tests run: ${DEPLOY_TESTS_TOTAL}"
echo "Apex test failures: ${DEPLOY_TESTS_FAILED}"

if [[ "$deploy_exit" -ne 0 ]]; then
  cat "$REPORT_PATH"
  exit "$deploy_exit"
fi
