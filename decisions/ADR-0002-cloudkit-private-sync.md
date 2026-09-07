# ADR-0002 — CloudKit Private Database for Lightweight User State

Status: Accepted
Date: 2026-09-07

## Context

The app needs Continue Watching/favorites across Apple TV and iPhone/iPad without requiring a custom backend in the first version.

## Decision

Use CloudKit private database for eligible lightweight user state.

Keep the large provider catalog, EPG and poster caches local.

Keep provider credentials in Keychain rather than CloudKit.

## Consequences

Positive:
- native Apple-account-based sync.
- no custom auth/backend initially.
- local browsing remains independent of cloud availability.

Tradeoff:
- iCloud account availability must be handled.
- sync/conflict behavior must be tested carefully.
