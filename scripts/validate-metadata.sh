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

# preview: writes JSON to file, but if it fails we want to see WHY, not silently exit.
echo "=== sf project deploy preview ==="
set +e
sf project deploy preview \
  --target-org "$TARGET_ORG" \
  --source-dir "$SOURCE_DIR" \
  --json > "$PREVIEW_PATH"
preview_exit=$?
set -e
if [[ "$preview_exit" -ne 0 ]]; then
  echo "PREVIEW FAILED with exit ${preview_exit}. JSON error follows:"
  cat "$PREVIEW_PATH" 2>&1 | sed 's/^/  /'
  exit "$preview_exit"
fi
echo "preview completed OK"

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
