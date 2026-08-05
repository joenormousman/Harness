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
  echo "  Derived public key SHA256 (via openssl): ${PUB_SHA}"
elif command -v node >/dev/null 2>&1; then
  # openssl not installed (e.g. node:22-slim). Fall back to Node's built-in crypto
  # module to extract the DER-encoded public key and SHA256 it. Same fingerprint,
  # different tool.
  PUB_SHA=$(node -e "
    const fs = require('fs');
    const crypto = require('crypto');
    const pemPriv = fs.readFileSync(process.argv[1], 'utf8');
    const keyObj = crypto.createPrivateKey(pemPriv);
    const pubDer = crypto.createPublicKey(keyObj).export({type:'spki', format:'der'});
    console.log(crypto.createHash('sha256').update(pubDer).digest('hex'));
  " "$KEY_FILE" 2>/dev/null)
  echo "  Derived public key SHA256 (via node crypto): ${PUB_SHA}"
else
  echo "  Neither openssl nor node available; skipping public-key fingerprint check."
fi
echo "  (This MUST match the SHA256 of the cert public key uploaded to the SF Connected App.)"
echo "  Expected v2 cert fingerprint: 73e01e60203b74cef712ffd0e86bf8ccf28868366b3d584f420b1177d3fbcd53"
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
