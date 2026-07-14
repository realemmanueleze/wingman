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

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/Wingman"
cp "$MACOS_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Stage the embedded gateway runtime if it has been bundled.
GATEWAY_STAGE="$MACOS_DIR/Resources/gateway"
if [[ -d "$GATEWAY_STAGE" ]]; then
  echo "==> Bundling gateway runtime from $GATEWAY_STAGE"
  cp -R "$GATEWAY_STAGE" "$APP_DIR/Contents/Resources/gateway"
else
  echo "==> No bundled gateway (run scripts/bundle-gateway.sh first for a self-contained app)."
  echo "    The app will attach to a running gateway or use WINGMAN_GATEWAY_CMD."
fi

echo "==> Signing (identity: $SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    open \"$APP_DIR\""
