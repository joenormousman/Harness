#!/usr/bin/env bash
set -euo pipefail

: "${TARGET_ORG:?Set TARGET_ORG to a Salesforce org alias or username.}"

SOURCE_DIR="${SOURCE_DIR:-force-app}"
TEST_LEVEL="${TEST_LEVEL:-RunLocalTests}"
WAIT_MINUTES="${WAIT_MINUTES:-60}"
PREVIEW_PATH="${PREVIEW_PATH:-deployment-preview.json}"
REPORT_PATH="${REPORT_PATH:-deployment-validation.json}"

sf project deploy preview \
  --target-org "$TARGET_ORG" \
  --source-dir "$SOURCE_DIR" \
  --json > "$PREVIEW_PATH"

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
