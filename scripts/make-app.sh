#!/bin/bash
# Assembles Wingman.app from the SPM build product.
#
# Usage:
#   scripts/make-app.sh [--release]
#
# Signing:
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/make-app.sh --release
#   Defaults to ad-hoc signing ("-") for local development.
#
# TCC note: permissions (Screen Recording, Accessibility) are tied to the
# signing identity + bundle path. For permission testing, always install the
# built app to a stable path (e.g. /Applications) and sign with a real
# identity — ad-hoc re-signs generate a new identity each build and macOS
# will re-prompt every time.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$REPO_ROOT/apps/macos"
CONFIGURATION="debug"
if [[ "${1:-}" == "--release" ]]; then
  CONFIGURATION="release"
fi
# Prefer the local "Wingman Dev" self-signed identity when present: a stable
# identity keeps TCC permission grants valid across rebuilds (ad-hoc doesn't).
if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Wingman Dev"'; then
  SIGN_IDENTITY="Wingman Dev"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "==> Building Wingman ($CONFIGURATION)"
cd "$MACOS_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
  swift build -c release
else
  swift build
fi

BINARY="$MACOS_DIR/.build/$CONFIGURATION/Wingman"
APP_DIR="$REPO_ROOT/dist/Wingman.app"
# Assemble + sign outside the repo: iCloud File Provider syncs ~/Documents and
# re-injects com.apple.FinderInfo xattrs mid-sign, which codesign rejects as
# "detritus". A non-synced staging dir avoids the race entirely.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wingman-app.XXXXXX")"
STAGE_APP="$STAGE_DIR/Wingman.app"
trap 'rm -rf "$STAGE_DIR"' EXIT

echo "==> Assembling $STAGE_APP"
mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
# ditto --noextattr: strip provenance/Finder xattrs from staged inputs.
ditto --norsrc --noextattr --noacl --noqtn "$BINARY" "$STAGE_APP/Contents/MacOS/Wingman"
ditto --norsrc --noextattr --noacl --noqtn "$MACOS_DIR/Resources/Info.plist" "$STAGE_APP/Contents/Info.plist"

# Stage the embedded gateway runtime if it has been bundled.
GATEWAY_STAGE="$MACOS_DIR/Resources/gateway"
if [[ -d "$GATEWAY_STAGE" ]]; then
  echo "==> Bundling gateway runtime from $GATEWAY_STAGE"
  ditto --norsrc --noextattr --noacl --noqtn "$GATEWAY_STAGE" "$STAGE_APP/Contents/Resources/gateway"
else
  echo "==> No bundled gateway (run scripts/bundle-gateway.sh first for a self-contained app)."
  echo "    The app will attach to a running gateway or use WINGMAN_GATEWAY_CMD."
fi

echo "==> Signing (identity: $SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGE_APP"

echo "==> Installing to $APP_DIR"
mkdir -p "$REPO_ROOT/dist"
rm -rf "$APP_DIR"
mv "$STAGE_APP" "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    open \"$APP_DIR\""
