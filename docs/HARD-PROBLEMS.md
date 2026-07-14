# Hard Problems — and how Wingman solves them

## 1. Shipping a Node gateway inside a signed macOS app

**Problem.** OpenClaw is a Node monorepo; users must not need a terminal or a Node install.

**Solution (implemented).**
- `GatewaySidecar` resolves the runtime in order: `WINGMAN_GATEWAY_CMD` (dev) → bundled runtime at `Resources/gateway/` → attach to an already-running gateway on `127.0.0.1:18789`.
- `scripts/bundle-gateway.sh` stages a portable Node runtime + an `openclaw` npm install into the app resources; `scripts/make-app.sh` copies them into `Wingman.app` and signs the bundle.
- Supervision: child process with log capture to `~/Library/Application Support/Wingman/gateway.log`, termination handler, quadratic-backoff restart capped at 3 attempts, then a surfaced failure state in the menu panel.
- Auth: a per-install token (0600 file in the app data dir) is exported as `OPENCLAW_GATEWAY_TOKEN` to the child and used by the WS client — loopback-only with shared-secret auth, matching OpenClaw's own token mode.
- State lives in the data directory (not the bundle), so app updates never touch user state; the gateway version rides app releases (Sparkle later), while plugins/skills install into the data dir.

**Residual work.** Notarization requires signing every Mach-O inside the bundled Node runtime (`codesign --deep` handles the common case; the release pipeline should sign binaries explicitly and enable hardened runtime with the JIT entitlement Node needs).

## 1b. Terminal-free onboarding for non-technical users

**Problem.** `openclaw onboard` is a terminal wizard; our users should never see a shell.

**Solution (implemented).**
- `OnboardingView` — a native four-step wizard shown automatically on first launch (or whenever no provider is configured): welcome → permission cards with one-click grants → provider picker + API key field (with a "where do I get a key?" link) → how-to-use card.
- `OnboardingManager.writeProviderConfig` writes the documented OpenClaw config shape (`env.<PROVIDER>_API_KEY` + `agents.defaults.model.primary`) into `~/.openclaw/openclaw.json`, merging with any existing config (0600 perms). The app then restarts the sidecar so the key takes effect.
- Detection is idempotent: users who already ran `openclaw onboard` (env keys or OAuth auth profiles) get a "already configured — skip" path.
- OAuth/subscription sign-in (ChatGPT/Codex-style) is the natural v2 of the provider step; API-key paste covers the launch.

## 2. TCC permissions that actually stick

**Problem.** Screen Recording/Accessibility grants bind to (signing identity × bundle path); dev rebuilds silently invalidate them. Both inspiration codebases hit this.

**Solution (implemented + process).**
- `PermissionsManager` follows Clicky's battle-tested flow: preflight → system prompt once per launch → deep-link to the exact System Settings pane afterwards (never both at once).
- The known `CGPreflightScreenCaptureAccess` false-negative flicker is absorbed by a "previously confirmed" UserDefaults flag, so users who already granted are never re-nagged.
- Process rules (in README): permission testing only from a stable path with a real signing identity; no ad-hoc signing for TCC work; never day-to-day `xcodebuild` from a terminal.

## 3. Teach vs. act — a question must never run `rm`

**Problem.** One app that can both explain and execute needs a hard line between the two.

**Solution (implemented, enforced server-side).**
- Three explicit modes in the menu bar: **Teach**, **Ask before acting**, **Act**.
- Each mode routes to a distinct gateway **session key** (`wingman-teach` / `wingman-main`). Tool policy binds to the session in the gateway config: the teach session denies all tools. The client never carries tool authority — a buggy or spoofed client still cannot make the teach session execute anything.
- Ask-before-act layers OpenClaw's exec-approval flow plus a prompt contract ("state the exact action and wait").
- Mode is visible at all times in the menu bar; teach is the default.

## 4. One product across macOS, Windows, mobile

**Problem.** Avoid three divergent products with three brains.

**Solution (implemented as structure).**
- The brain is the Gateway; **shells never contain product logic**. Everything a shell needs to agree on lives in `packages/wingman-core`: protocol subset, `[POINT]` contract, turn policy. Swift mirrors those files 1:1; Windows/mobile shells consume the TS package directly or mirror likewise.
- Windows reuses the identical sidecar pattern (bundled Node + tray). Mobile apps are OpenClaw **nodes** — they pair with the user's gateway rather than embedding one, so identity and memory stay singular.
- The pointing/overlay layer is deliberately optional per platform: the product is whole without it (channels + chat), and each platform adds presence when its native overlay tech is ready.

## 5. Privacy: the screen is sensitive

**Solution (implemented as defaults).**
- Capture is snapshot-per-turn, never continuous; captures happen only when a turn runs and the mode attaches them.
- Wingman's own windows are excluded from capture, so overlays and panels never reach the model.
- Frames go only to the user's own gateway over loopback; whatever model/provider policy the user configured in OpenClaw governs the rest. Cloud redaction can slot in front of the provider later (OpenClaw pre-processing seam).

## 6. Latency: the loop must feel alive

**Solution (current + planned).**
- Local STT/TTS (Apple Speech / AVSpeechSynthesizer) removes two network round trips in the scaffold; provider seams allow AssemblyAI streaming / ElevenLabs swaps exactly as Clicky does.
- Captures are downscaled to ≤1280px JPEG (Clicky's proven budget).
- Planned: stream TTS on first sentence rather than waiting for the full run; reuse Clicky's TLS-warmup trick in the gateway's provider clients.
