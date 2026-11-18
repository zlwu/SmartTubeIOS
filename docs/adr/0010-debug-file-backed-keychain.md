---
status: accepted
date: 2026-11-18
deciders: zlwu
---
# 0010. Debug auth tokens use a file-backed Keychain store

## Context and problem statement

Ad-hoc signed debug builds and SwiftPM test bundles change their cdhash on every build, so reading a
Keychain item written by an earlier build triggers the macOS authorization dialog; "Always Allow"
never sticks. Keeping debug runs off the Keychain removed the dialog, but the in-memory store that
did it also dropped the sign-in on every relaunch.

## Decision

Debug builds default to `FileKeychainStore`: one file per key under
`Application Support/<bundle-id>/DebugKeychain`, files `0600`, directories `0700`, excluded from
backup, cleared by sign-out. Unit tests and `--uitesting` runs use the in-memory store.
`SMARTTUBE_KEYCHAIN=memory|file|keychain` forces a backend and `SMARTTUBE_KEYCHAIN_DIR` overrides the
root. Release defaults to `SecurityKeychainStore`; `SMARTTUBE_KEYCHAIN=file` is an explicit,
local-only opt-in for Release runs.

The file store is compiled into Release so that opt-in works, but no build setting, Info.plist key
or package marker can select it. Xcode Archive and a local Release build share one configuration, so
a missed marker would ship plaintext refresh tokens to App Store users.

## Consequences
- Good: local runs never prompt for Keychain access; sign-in survives relaunch and rebuild; tests
  stay hermetic.
- Bad: debug tokens are plaintext inside the app sandbox; Debug and Release use different backends,
  so a regression in the Security path is only caught by a Release run.

## Alternatives considered
- Keep the in-memory store: rejected — sign-in is lost on every launch.
- Always-Allow Keychain ACL: impossible while the cdhash changes per build.
- Release also defaults to the file store: rejected — every App Store user's long-lived refresh
  token would be stored as plaintext.
- Build-time "packaged build" marker: rejected — a missed marker is a silent security downgrade.
