#!/usr/bin/env bash
set -euo pipefail

SF_CLI_VERSION="${SF_CLI_VERSION:-2.143.6}"
NODE_VERSION="${NODE_VERSION:-22.13.1}"

if ! command -v node >/dev/null 2>&1; then
  mkdir -p "$HOME/nodejs"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar xJ -C "$HOME/nodejs"
  export PATH="$HOME/nodejs/node-v${NODE_VERSION}-linux-x64/bin:$PATH"
fi

node --version
npm --version

if ! command -v sf >/dev/null 2>&1; then
  npm install --global "@salesforce/cli@${SF_CLI_VERSION}"
fi

sf --version
