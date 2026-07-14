.PHONY: build app app-release gateway-bundle core-check run clean

# Compile the macOS app (SPM, debug)
build:
	cd apps/macos && swift build

# Assemble dist/Wingman.app (debug, ad-hoc signed)
app: build
	bash scripts/make-app.sh

# Assemble dist/Wingman.app (release; set SIGN_IDENTITY for real signing)
app-release:
	bash scripts/make-app.sh --release

# Stage a self-contained Node + openclaw runtime into the app resources
gateway-bundle:
	bash scripts/bundle-gateway.sh

# Typecheck the shared cross-platform core
core-check:
	cd packages/wingman-core && npm install --no-fund --no-audit --loglevel=error && ./node_modules/.bin/tsc -p tsconfig.json --noEmit

# Run the app binary directly (dev; expects a gateway via WINGMAN_GATEWAY_CMD or a running one)
run: build
	./apps/macos/.build/debug/Wingman

clean:
	rm -rf apps/macos/.build dist
