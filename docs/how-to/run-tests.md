> status: current (2026-09-11)

# How to run tests

**When to use:** running unit or UI tests locally, or setting up a fresh simulator.

All commands are `just` recipes (run `just` from the repo root to list them). Don't use
`mcp_xcode_RunAllTests`/`mcp_xcode_RunSomeTests` or any other `mcp_xcode_*` tool to run tests.

## Target simulator

Single source of truth for the iOS/Catalyst target simulator — don't copy this UDID into other
docs, link here instead.

| Property | Value |
|---|---|
| Name | iPhone 17 |
| UDID | `6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6` |
| OS | iOS 26.4.1 |

### One-time simulator setup

Disable the crash dialog so a mid-test crash doesn't block subsequent tests (persists across
reboots, reset if the simulator is erased):

```bash
xcrun simctl boot 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 2>/dev/null; sleep 3
xcrun simctl spawn 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 \
  defaults write com.apple.CrashReporter DialogType none
```

Verify: `xcrun simctl spawn 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 defaults read com.apple.CrashReporter DialogType` should print `none`.

## Memory ceiling

16 GB Mac Mini. Each simulator clone adds ~500–750 MB RAM (copy-on-write). **3 workers is the
ceiling** — 5 stalls clone boot indefinitely with no output. `justfile` hardcodes 3; don't raise
it without more RAM.

## Commands

- `just test-unit` — Swift Testing package tests, no simulator.
- `just test-ui-legacy` — UI tests, 3 parallel workers. Temporary until WS3-T3.4 adds the
  `Smoke`/`Live` test plans, at which point `just test-smoke`/`just test-ui` take over.
- `just test-ui-one <SmartTubeUITests/Suite/testMethod>` — a single UI test.
- Device/app log capture during a test run: `docs/how-to/device-logs.md`.

## Keychain authorization dialog during test runs

SwiftPM test bundles are ad-hoc signed, so their code identity (a cdhash) changes on every
build. Reading a Keychain item written by an earlier build used to trigger the macOS
authorization dialog, which blocked the whole run until someone clicked it.

Debug builds now never touch the real Keychain: `KeychainStoreFactory` returns an in-memory
store in `#if DEBUG`, so tests and locally-run debug apps start signed out and never prompt.
Release builds still use the real Keychain. Two consequences:

- A debug run that needs persisted credentials must opt back in with
  `SMARTTUBE_KEYCHAIN=keychain` (and will then ask for authorization). Don't use this in
  agent sessions.
- UI tests that need a signed-in UI use the app's `--uitesting-signed-in` launch argument or
  a fake at the seam; the simulator's Keychain is irrelevant to them now.

## Known failure

`just test-unit` currently fails to build (pre-existing, not test-writing-related) — see
`AGENTS.md`'s Gotchas. Native-macOS-only code in `TOSPlayerView.swift`/
`TOSPlayerViewModel+WebBridge.swift` doesn't compile. Fixing it is WS4/WS5 scope.
