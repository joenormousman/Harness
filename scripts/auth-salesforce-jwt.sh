#!/usr/bin/env bash
set -euo pipefail

: "${SF_CLIENT_ID:?Set SF_CLIENT_ID to the Salesforce connected app consumer key.}"
: "${SF_USERNAME:?Set SF_USERNAME to the integration user username.}"
: "${SF_JWT_KEY_BASE64:?Set SF_JWT_KEY_BASE64 to the base64-encoded JWT private key.}"
: "${SF_INSTANCE_URL:?Set SF_INSTANCE_URL to https://login.salesforce.com or https://test.salesforce.com.}"

SF_ORG_ALIAS="${SF_ORG_ALIAS:-target-org}"
KEY_DIR=".sf/ci"
KEY_FILE="${KEY_DIR}/${SF_ORG_ALIAS}.server.key"

mkdir -p "$KEY_DIR"
printf '%s' "$SF_JWT_KEY_BASE64" | base64 --decode > "$KEY_FILE"
chmod 600 "$KEY_FILE"

sf org login jwt \
  --client-id "$SF_CLIENT_ID" \
  --jwt-key-file "$KEY_FILE" \
  --username "$SF_USERNAME" \
  --instance-url "$SF_INSTANCE_URL" \
  --alias "$SF_ORG_ALIAS" \
  --set-default

sf org display --target-org "$SF_ORG_ALIAS" --json > "${KEY_DIR}/${SF_ORG_ALIAS}.org.json"
echo "Authenticated Salesforce org alias: ${SF_ORG_ALIAS}"
