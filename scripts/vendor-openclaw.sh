#!/bin/bash
# Makes OpenClaw ours: copies the snapshot into vendor/openclaw as the fork
# baseline we self-improve from. Wingman builds its embedded gateway from this
# copy (see bundle-gateway.sh), so our changes ship with our app.
#
# Excludes non-runtime weight (native companion apps, docs site, test suites,
# CI) — we keep core runtime, plugins, UI, packages, and skills.
#
# Usage: scripts/vendor-openclaw.sh [source-dir]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-$REPO_ROOT/Inspirations/openclaw-main}"
DEST="$REPO_ROOT/vendor/openclaw"

if [[ ! -f "$SOURCE/openclaw.mjs" ]]; then
  echo "Source does not look like an OpenClaw checkout: $SOURCE" >&2
  exit 1
fi

echo "==> Vendoring OpenClaw from $SOURCE"
rm -rf "$DEST"
mkdir -p "$DEST"

rsync -a \
  --exclude "node_modules" \
  --exclude ".git" \
  --exclude "apps/" \
  --exclude "docs/" \
  --exclude "test/" \
  --exclude "qa/" \
  --exclude ".github/" \
  --exclude ".agents/" \
  --exclude "**/*.test.ts" \
  --exclude "**/*.e2e.test.ts" \
  "$SOURCE/" "$DEST/"

echo "==> Vendored: $(du -sh "$DEST" | cut -f1) at vendor/openclaw"
echo "    This is now OUR fork baseline. Improve it freely; commit when ready."
echo "    Build the embedded gateway from it with:"
echo "      OPENCLAW_SOURCE_DIR=vendor/openclaw scripts/bundle-gateway.sh"
