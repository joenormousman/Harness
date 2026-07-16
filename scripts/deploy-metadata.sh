#!/usr/bin/env bash
set -euo pipefail

: "${TARGET_ORG:?Set TARGET_ORG to a Salesforce org alias or username.}"

SOURCE_DIR="${SOURCE_DIR:-force-app}"
MANIFEST_PATH="${MANIFEST_PATH:-}"
TEST_LEVEL="${TEST_LEVEL:-RunLocalTests}"
WAIT_MINUTES="${WAIT_MINUTES:-60}"
DEPLOY_MODE="${DEPLOY_MODE:-standard}"
REPORT_PATH="${REPORT_PATH:-deployment-start.json}"

if [[ "$DEPLOY_MODE" == "quick" ]]; then
  : "${VALIDATION_JOB_ID:?Set VALIDATION_JOB_ID for a production quick deploy.}"

  sf project deploy quick \
    --job-id "$VALIDATION_JOB_ID" \
    --target-org "$TARGET_ORG" \
    --wait "$WAIT_MINUTES" \
    --json > "$REPORT_PATH"
elif [[ -n "$MANIFEST_PATH" ]]; then
  sf project deploy start \
    --target-org "$TARGET_ORG" \
    --manifest "$MANIFEST_PATH" \
    --test-level "$TEST_LEVEL" \
    --wait "$WAIT_MINUTES" \
    --json > "$REPORT_PATH"
else
  sf project deploy start \
    --target-org "$TARGET_ORG" \
    --source-dir "$SOURCE_DIR" \
    --test-level "$TEST_LEVEL" \
    --wait "$WAIT_MINUTES" \
    --json > "$REPORT_PATH"
fi

node scripts/extract-salesforce-deploy-result.mjs "$REPORT_PATH" > deployment-start.env
source deployment-start.env

echo "Deployment mode: ${DEPLOY_MODE}"
echo "Deployment status: ${DEPLOY_STATUS}"
echo "Deployment job ID: ${DEPLOY_JOB_ID}"
