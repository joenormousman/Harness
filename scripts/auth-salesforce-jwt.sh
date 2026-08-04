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

# --- Diagnostics (safe to log; do NOT print the key itself) ---
echo "=== JWT auth diagnostics ==="
echo "  Org alias:       ${SF_ORG_ALIAS}"
echo "  Username:        ${SF_USERNAME}"
echo "  Instance URL:    ${SF_INSTANCE_URL}"
echo "  Client ID (first 12 chars): ${SF_CLIENT_ID:0:12}..."

KEY_BYTES=$(wc -c < "$KEY_FILE" | tr -d ' ')
echo "  Decoded key size: ${KEY_BYTES} bytes"

FIRST_LINE=$(head -n 1 "$KEY_FILE")
echo "  Decoded PEM first line: ${FIRST_LINE}"

if [[ "$FIRST_LINE" != *"BEGIN"*"PRIVATE KEY"* ]]; then
  echo "  ERROR: Decoded key does not begin with a PEM header." >&2
  echo "  ERROR: The SF_JWT_KEY_BASE64 secret is corrupted or holds the wrong content." >&2
  echo "  ERROR: Regenerate the key, base64-encode it (single line, no wrapping), and re-set the secret." >&2
  exit 1
fi

if command -v openssl >/dev/null 2>&1; then
  PUB_SHA=$(openssl pkey -in "$KEY_FILE" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
  echo "  Derived public key SHA256: ${PUB_SHA}"
  echo "  (This MUST match the SHA256 of the cert public key uploaded to the SF Connected App.)"
else
  echo "  openssl not available in this image; skipping public-key fingerprint check."
fi
echo "=== end diagnostics ==="
echo ""

sf org login jwt \
  --client-id "$SF_CLIENT_ID" \
  --jwt-key-file "$KEY_FILE" \
  --username "$SF_USERNAME" \
  --instance-url "$SF_INSTANCE_URL" \
  --alias "$SF_ORG_ALIAS" \
  --set-default

sf org display --target-org "$SF_ORG_ALIAS" --json > "${KEY_DIR}/${SF_ORG_ALIAS}.org.json"
echo "Authenticated Salesforce org alias: ${SF_ORG_ALIAS}"
