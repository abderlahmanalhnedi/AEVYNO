# ADR-0005 — Device-Local Keychain Credentials

Status: Accepted
Date: 2026-09-08

## Context

Source configurations need stable, serializable identities without persisting provider
usernames, passwords or token-like values in domain data. Credentials must be available to
future provider adapters through a testable security boundary. The existing Swift package
product named `Security` also conflicts with Apple's `Security` framework once Keychain APIs
are imported from that target.

## Decision

- Store source credentials as Keychain generic-password items.
- Address each item by an application service name and a non-secret UUID-backed
  `CredentialReference`; never place credential values in the Keychain account identifier.
- Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and explicitly disable Keychain
  synchronization. Provider credentials remain device-local and unavailable while the device
  is locked.
- Isolate the concrete credential store as an actor and inject an internal Keychain client
  boundary so behavior can be tested without signing-dependent live Keychain access in CI.
- Normalize Keychain failures into safe application error categories; do not expose raw
  `OSStatus` values or credential material in user-facing diagnostics.
- Name the Swift package product and target `AEVYNOSecurity` so the implementation can import
  Apple's `Security` framework without a module-name collision. The architectural directory
  remains `Core/Security`.

## Consequences

Positive:

- serialized source configuration contains only a non-secret credential reference.
- credentials do not migrate through backups or synchronize across devices through Keychain.
- concurrent credential operations are serialized away from the main actor.
- CI can verify Keychain query behavior and error normalization through an injected boundary.

Tradeoffs:

- users must enter provider credentials separately on each device.
- credentials cannot be read before the device has been unlocked.
- a signed simulator/application-host integration test is still needed to validate the real
  Keychain entitlement/runtime path; CI does not depend on that access.
