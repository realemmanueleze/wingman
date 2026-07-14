#!/bin/bash
# Stages a self-contained OpenClaw Gateway runtime into the macOS app resources:
#   apps/macos/Resources/gateway/node/      portable Node.js runtime
#   apps/macos/Resources/gateway/openclaw/  openclaw npm install
#
# Run this before scripts/make-app.sh to produce a fully self-contained
# Wingman.app that needs no system Node and no terminal setup.
#
# Env overrides:
#   NODE_VERSION         (default 22.19.0)
#   OPENCLAW_SPEC        npm spec to install (default openclaw@latest)
#   OPENCLAW_SOURCE_DIR  build from OUR fork instead of npm (e.g. vendor/openclaw).
#                        Runs pnpm install + build there, then stages the result —
#                        this is how self-improved OpenClaw ships inside Wingman.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$REPO_ROOT/apps/macos/Resources/gateway"
NODE_VERSION="${NODE_VERSION:-22.19.0}"
OPENCLAW_SPEC="${OPENCLAW_SPEC:-openclaw@latest}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) NODE_ARCH="darwin-arm64" ;;
  x86_64) NODE_ARCH="darwin-x64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

echo "==> Staging gateway runtime into $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "==> Fetching portable Node $NODE_VERSION ($NODE_ARCH)"
NODE_TARBALL="node-v$NODE_VERSION-$NODE_ARCH.tar.gz"
curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/$NODE_TARBALL" -o "/tmp/$NODE_TARBALL"
mkdir -p "$STAGE/node"
tar -xzf "/tmp/$NODE_TARBALL" -C "$STAGE/node" --strip-components 1
rm "/tmp/$NODE_TARBALL"

if [[ -n "${OPENCLAW_SOURCE_DIR:-}" ]]; then
  SOURCE_DIR="$OPENCLAW_SOURCE_DIR"
  [[ "$SOURCE_DIR" != /* ]] && SOURCE_DIR="$REPO_ROOT/$SOURCE_DIR"
  echo "==> Building OpenClaw from source: $SOURCE_DIR (our fork)"
  pushd "$SOURCE_DIR" >/dev/null
  corepack enable >/dev/null 2>&1 || true
  pnpm install
  pnpm build
  echo "==> Packing built fork via npm pack"
  PACK_FILE="$("$STAGE/node/bin/npm" pack --pack-destination /tmp 2>/dev/null | tail -1)"
  popd >/dev/null
  mkdir -p "$STAGE/openclaw"
  tar -xzf "/tmp/$PACK_FILE" -C "$STAGE/openclaw" --strip-components 1
  rm -f "/tmp/$PACK_FILE"
  pushd "$STAGE/openclaw" >/dev/null
  "$STAGE/node/bin/npm" install --omit=dev --no-fund --no-audit
  popd >/dev/null
else
  echo "==> Installing $OPENCLAW_SPEC from npm"
  mkdir -p "$STAGE/openclaw-install"
  pushd "$STAGE/openclaw-install" >/dev/null
  "$STAGE/node/bin/npm" init -y >/dev/null
  "$STAGE/node/bin/npm" install --no-fund --no-audit "$OPENCLAW_SPEC"
  popd >/dev/null

  # Flatten so the sidecar finds <Resources>/gateway/openclaw/openclaw.mjs.
  mv "$STAGE/openclaw-install/node_modules/openclaw" "$STAGE/openclaw"
  mv "$STAGE/openclaw-install/node_modules" "$STAGE/openclaw/node_modules_hoisted" 2>/dev/null || true
  rm -rf "$STAGE/openclaw-install"
fi

echo "==> Gateway runtime staged. Now run scripts/make-app.sh"
