#!/usr/bin/env bash
# One-shot demo of the metadata dependency resolver.
# Feeds a single-field seed manifest through the resolver and prints the
# expanded package.xml + rationale trail. This is the "watch the seed
# expand" moment for the interview demo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SEED_FILE="${SEED_FILE:-$SCRIPT_DIR/resolve-input.example.json}"
OUT_PACKAGE="${OUT_PACKAGE:-$REPO_ROOT/package-expanded.xml}"
OUT_RATIONALE="${OUT_RATIONALE:-$REPO_ROOT/rationale.json}"

echo "==> Seed manifest:"
cat "$SEED_FILE"
echo ""
echo "==> Running resolver..."
python "$SCRIPT_DIR/resolve-dependencies.py" \
  --source-dir "$REPO_ROOT/force-app" \
  --input "$SEED_FILE" \
  --output "$OUT_PACKAGE" \
  --rationale "$OUT_RATIONALE"
echo ""
echo "==> Expanded package.xml:"
cat "$OUT_PACKAGE"
echo ""
echo "==> Rationale trail (why each item was included):"
if command -v jq >/dev/null 2>&1; then
  jq . "$OUT_RATIONALE"
else
  cat "$OUT_RATIONALE"
fi
