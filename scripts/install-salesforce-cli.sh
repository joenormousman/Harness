#!/usr/bin/env bash
# Install Salesforce CLI into the Harness workspace directory.
#
# In Harness Kubernetes CI, each step runs in its own container within the
# stage's pod. The workspace volume (typically /harness) is shared across
# all steps in the stage; anything installed OUTSIDE that volume (e.g. via
# `npm install -g`) does NOT persist to subsequent steps.
#
# This script installs the sf CLI into ./sf-cli/ relative to the workspace,
# so subsequent steps can add `$PWD/sf-cli/node_modules/.bin` to PATH and
# invoke `sf` normally.
#
# Assumes the base image already provides node + npm (e.g. node:20-slim).
# If node isn't present, falls back to downloading a portable Node.js.
set -euo pipefail

SF_CLI_VERSION="${SF_CLI_VERSION:-2.143.6}"
NODE_VERSION="${NODE_VERSION:-22.13.1}"
WORKSPACE_ROOT="$PWD"
SF_CLI_HOME="${SF_CLI_HOME:-$WORKSPACE_ROOT/sf-cli}"

if ! command -v node >/dev/null 2>&1; then
  echo "node not on PATH — downloading portable Node.js ${NODE_VERSION} into workspace"
  mkdir -p "$PWD/nodejs"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar xJ -C "$PWD/nodejs"
  export PATH="$PWD/nodejs/node-v${NODE_VERSION}-linux-x64/bin:$PATH"
fi

echo "node: $(node --version)"
echo "npm: $(npm --version)"

mkdir -p "$SF_CLI_HOME"
cd "$SF_CLI_HOME"

# Bootstrap a minimal package.json so npm install --prefix behaves predictably.
if [[ ! -f package.json ]]; then
  cat > package.json <<'JSON'
{
  "name": "harness-sf-cli-workspace",
  "version": "1.0.0",
  "private": true
}
JSON
fi

# Install sf CLI into the workspace. --no-audit / --no-fund quiet the log.
npm install --no-audit --no-fund "@salesforce/cli@${SF_CLI_VERSION}"

SF_BIN="$SF_CLI_HOME/node_modules/.bin/sf"
if [[ ! -x "$SF_BIN" ]]; then
  echo "error: sf binary not found at $SF_BIN after install" >&2
  exit 1
fi

echo "sf installed at: $SF_BIN"
echo "sf --version:"
"$SF_BIN" --version

# Emit the PATH export that downstream steps must source.
# Writes to workspace root so `source sf-cli.env` from any step (whose
# $PWD is the workspace root at step start) resolves correctly.
cat > "$WORKSPACE_ROOT/sf-cli.env" <<EOF
export PATH="$SF_CLI_HOME/node_modules/.bin:\$PATH"
EOF

echo "PATH export written to $WORKSPACE_ROOT/sf-cli.env"
echo "downstream steps must: source sf-cli.env"
