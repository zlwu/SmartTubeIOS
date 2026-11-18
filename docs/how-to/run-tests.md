> status: current (2026-11-18)

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

## Keychain (auth token) storage in local runs

Every build stores auth tokens in `FileKeychainStore` (see
[ADR-0010](../adr/0010-debug-file-backed-keychain.md)). It never calls Security.framework, so the
ad-hoc-signed-build authorization dialog cannot appear, and the sign-in survives relaunches.

| Item | Value |
|---|---|
| Default root | `Application Support/<bundle-id>/DebugKeychain` (inside the app container) |
| Layout | one file per key: `<root>/com.smarttube.auth/st_access_token`, raw UTF-8 |
| Permissions | directory `0700`, files `0600`, excluded from backup |
| Reset | sign out in the app, or delete the directory (the log prints its absolute path) |

The app logs the resolved path at launch: `KeychainStore: using file store at <path>`.

- Unit tests inject `InMemoryKeychainStore` directly, so they never read or write the credential
  files.
- `SMARTTUBE_KEYCHAIN_DIR` overrides the root (absolute path; `~` is expanded). The app is
  sandboxed, so the value must be writable by it — `~/.config` and repo paths are not.
- Tokens are plaintext inside the app sandbox, in Release builds too. Do not point
  `SMARTTUBE_KEYCHAIN_DIR` at a tracked path or commit its contents.
- A locally packaged macOS app (`just macos-package`) reads the same container path; no environment
  variable is needed.
