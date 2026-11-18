# SmartTube — agent guide

Native Swift/SwiftUI YouTube client for iOS/iPadOS (17+), macOS Catalyst (14+) and tvOS (17+).
Package `SmartTubeIOS/` (targets `SmartTubeIOSCore` = Foundation-only models/API/stores,
`SmartTubeIOS` = SwiftUI views, view models, services) + Xcode project `SmartTubeApp/`
(iOS+Catalyst app, tvOS app, Share/Safari extensions, Download widget, UI-test targets).
Architecture map: docs/architecture.md · Glossary: CONTEXT.md · Decisions: docs/adr/ · Plan: docs/modernization/

## Commands (always via `just`; run `just` to list)
- `just ci` — secrets check + format check + lint + unit tests. Run before every commit.
- `just build` / `just build-tvos` — simulator builds, no signing needed.
- `just test-unit` / `just test-unit-filter <Name>` — Swift Testing package tests (no simulator). Debug builds use the file-backed Keychain store by default (tests use the in-memory one), so local runs never touch the real Keychain (see Gotchas).
- `just test-smoke` — hermetic UI smoke plan. `just test-ui` — live UI plan (needs signed-in simulator; 3 workers max, see docs/how-to/run-tests.md).
- `just format` — swift-format in place. `just lint` — SwiftLint against the committed baseline.

## Rules that differ from defaults
- Swift 6 strict concurrency everywhere. View models are `@MainActor @Observable`. No `ObservableObject`, `@Published`, Combine, `DispatchQueue`, completion handlers in new code.
- `SmartTubeIOSCore` must stay Foundation-only (no SwiftUI/UIKit/AVFoundation/WebKit). Put platform code in `SmartTubeIOS`.
- One definition per constant/identifier/threshold. Accessibility identifiers come from `AccessibilityID`; SF Symbols from `AppSymbol`; playback timeouts from `PlaybackTuning`.
- Wrap UIKit-only API in `#if os(iOS)`; provide AppKit/tvOS branches. Never nest `NavigationStack`s.
- Never hand-edit `project.pbxproj` (a hook blocks it). New Swift files under synchronized folders are picked up automatically; UI-test files must be added in Xcode.
- Tests: Swift Testing for unit tests; no `Task.sleep`, no live network, fakes at protocol seams. UI tests use `AccessibilityID` and `waitForExistence`, never `sleep`.
- Logging via `os.Logger` (subsystem `AppSubsystem`), never `print`.
- Commits: Conventional Commits with the task ID, e.g. `fix(player): … (#312)`.

## Gotchas
- The Simulator cannot decode VP9/AV1 and cannot run PiP; assert stream *selection* in tests, not decoding.
- WKWebView `evaluateJavaScript` has no user activation: PiP/fullscreen cannot be triggered from Swift.
- Authenticated InnerTube calls use the TVHTML5 client on youtubei.googleapis.com with a Bearer token and no API key; the WEB client rejects Bearer tokens. Never call `/oauth2/v3/userinfo` for account info (the TV OAuth client isn't Data-API-v3-enabled) — use `account/accounts` with the TVHTML5 context instead.
- The 16 GB build Mac stalls with > 3 parallel simulator clones; `just` hardcodes 3.
- Playback fallback code (`PlaybackViewModel+Fallback.swift`) is under active decomposition (WS4). Do not add branches there; add a `StreamSource`.
- **Debug auth tokens live in a file, not the Keychain**: `KeychainStoreFactory` defaults `#if DEBUG` to `FileKeychainStore` under `Application Support/<bundle-id>/DebugKeychain` (0600 files, `SMARTTUBE_KEYCHAIN_DIR` overrides, sandbox rules apply), so local runs never hit the macOS authorization dialog and sign-in survives rebuilds. Tests and `--uitesting` launches get the in-memory store; `SMARTTUBE_KEYCHAIN=memory|file|keychain` forces a backend. Release defaults to the real Keychain — `SMARTTUBE_KEYCHAIN=file` is a local-only opt-in; never ship a Release build with it (see docs/adr/0010-debug-file-backed-keychain.md).
- `just test-unit` runs serially (`swift test --no-parallel`): the tests wait for spawned tasks with fixed delays and share process-global state, so parallel runs flake (one suite even crashes on an empty array).

## Where things are
- Playback: docs/architecture.md#playback · Tests how-to: docs/how-to/run-tests.md · Device logs: docs/how-to/device-logs.md
- Tasks: tasks/README.md (open items) · Modernization program: docs/modernization/PLAN.md