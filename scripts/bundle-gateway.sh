#!/bin/bash
# Stages a self-contained OpenClaw Gateway runtime into the macOS app resources:
#   apps/macos/Resources/gateway/node/      portable Node.js runtime
#   apps/macos/Resources/gateway/openclaw/  openclaw npm install
#
# Run this before scripts/make-app.sh to produce a fully self-contained
# Wingman.app that needs no system Node and no terminal setup.
#
# Env overrides:
#   NODE_VERSION   (default 22.19.0)
#   OPENCLAW_SPEC  npm spec to install (default openclaw@latest)
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

echo "==> Installing $OPENCLAW_SPEC"
mkdir -p "$STAGE/openclaw-install"
pushd "$STAGE/openclaw-install" >/dev/null
"$STAGE/node/bin/npm" init -y >/dev/null
"$STAGE/node/bin/npm" install --no-fund --no-audit "$OPENCLAW_SPEC"
popd >/dev/null

# Flatten so the sidecar finds <Resources>/gateway/openclaw/openclaw.mjs.
mv "$STAGE/openclaw-install/node_modules/openclaw" "$STAGE/openclaw"
mv "$STAGE/openclaw-install/node_modules" "$STAGE/openclaw/node_modules_hoisted" 2>/dev/null || true
rm -rf "$STAGE/openclaw-install"

echo "==> Gateway runtime staged. Now run scripts/make-app.sh"
