#!/usr/bin/env bash
set -euo pipefail

: "${TARGET_ORG:?Set TARGET_ORG to a Salesforce org alias or username.}"

TEST_CLASS="${TEST_CLASS:-HarnessReleaseHealthTest}"
WAIT_MINUTES="${WAIT_MINUTES:-20}"

sf apex run test \
  --target-org "$TARGET_ORG" \
  --class-names "$TEST_CLASS" \
  --result-format human \
  --wait "$WAIT_MINUTES"
