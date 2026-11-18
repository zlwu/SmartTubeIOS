---
status: accepted
date: 2026-11-18
deciders: zlwu
---
# 0010. Auth tokens use a file-backed Keychain store

## Context and problem statement

Ad-hoc signed builds change their cdhash on every build, so reading a Keychain item written by an
earlier build triggers the macOS authorization dialog; "Always Allow" never sticks. The earlier
in-memory store avoided the dialog but dropped the sign-in on every relaunch. Per the owner's
decision, every build now uses one simple backend instead of choosing per configuration.

## Decision

Every build (Debug and Release, all platforms) uses `FileKeychainStore`: one file per key under
`Application Support/<bundle-id>/DebugKeychain`, files `0600`, directories `0700`, excluded from
backup, cleared by sign-out. The path is fixed: no environment variable and no backend switch.
`SecurityKeychainStore` and the in-memory store are removed; unit tests use throwaway directories.

## Consequences
- Good: no Keychain authorization dialogs in any build; sign-in survives relaunch and rebuild; one
  code path to reason about.
- Bad: OAuth access/refresh tokens are plaintext inside the app sandbox, including App Store builds.
  They lose Keychain access control (per-app ACLs, hardware-backed protection), and existing users
  appear signed out once after updating because their Keychain tokens are not read anymore.
- Bad: backup exclusion is best-effort, so a plaintext token file is a weaker boundary than the
  Keychain.

## Alternatives considered
- Keep the real Keychain as the Release default: rejected by the owner in favour of one backend.
- Runtime `SMARTTUBE_KEYCHAIN` selection and `SMARTTUBE_KEYCHAIN_DIR`: removed — the simpler rule
  is always file at one fixed path.
- Build-time "packaged build" marker: rejected — a missed marker silently changes credential
  storage.