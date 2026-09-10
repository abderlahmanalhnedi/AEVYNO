# ADR-0011 — Refresh Scheduling and Policy

Status: Accepted
Date: 2026-09-10

## Context

Users need provider catalogs to refresh without repeatedly choosing Refresh Now, but iOS and tvOS do
not guarantee arbitrary application execution while an app is suspended or terminated. Scheduling
must therefore describe when a source is eligible, not promise an exact wall-clock execution time.
It must reuse the durable, last-known-good `CatalogRefreshService` path and keep provider credentials
out of policy state.

The source registry previously used schema version 1 and had no scheduling field. Existing users must
retain source identity, endpoint, enabled state and indirect Keychain reference when the policy is
introduced.

## Decision

- Each `SourceConfiguration` stores a durable `RefreshPolicy` in source-registry schema version 2.
- New sources and sources migrated from version 1 default to `manualOnly`.
- Automatic choices are every 6 hours, every 12 hours and daily. Cadence uses elapsed instants from
  the last successful refresh rather than calendar or time-zone boundaries.
- An enabled automatic source with no successful refresh is due immediately. Disabled and
  manual-only sources are never automatically due.
- A failed or cancelled recent attempt defers the next automatic attempt for 30 minutes. Eligibility
  is the later of that retry boundary and the normal cadence boundary.
- `RefreshPolicyEvaluator` is a deterministic domain rule. It performs no persistence, networking,
  Keychain or UI work.
- `RefreshSchedulingService` is actor-isolated and provider-neutral. It reads the small source
  registry and refresh metadata, sorts due sources by oldest eligibility and then stable source ID,
  and delegates them sequentially to `CatalogRefreshService`. Automatic concurrency is one.
- Failure of one eligible source does not prevent later eligible sources. An existing same-source
  refresh returns a safe `inProgress` outcome.
- Cancellation propagates to current refresh work and prevents later queued sources from starting.
  Already committed refreshes and all last-known-good catalogs keep the Phase 2E transaction
  guarantees.
- App composition evaluates on the first active launch and later foreground/active transitions. One
  active-session task may sleep until the next known eligibility date. Leaving active cancels that
  task, and duplicate active notifications do not create duplicate loops.
- Manual Refresh Now delegates directly to `CatalogRefreshService`; automatic cadence and cooldown
  do not block an explicit user action.
- Scheduling uses Swift Concurrency sleep. It adds no `Timer`, polling loop, background entitlement,
  `BGTaskScheduler`, CloudKit scheduling record or detached task.
- Policy contains no username, password, token, URL or other credential material. Xtream credentials
  remain behind their existing device-local Keychain reference.

## Registry migration

`FileSourceRepository` explicitly decodes version 1 records into a legacy type, supplies
`manualOnly`, validates the complete migrated collection, and atomically persists version 2. It
preserves source ID, display name, kind, endpoint, `CredentialReference` and enabled state. Malformed
or unsupported future registries continue to fail without destructive reset.

## Consequences

Positive:

- eligibility is deterministic, testable and independent of SwiftUI or provider implementations;
- automatic work retains durable refresh atomicity and never runs two provider refreshes from the
  scheduler concurrently;
- users can change only scheduling policy without re-entering or rewriting credentials;
- launch rendering is independent from scheduler setup and refresh work.

Tradeoffs:

- refresh is best-effort and may run later than its eligible time after suspension or termination;
- there is no guaranteed background execution or server-side push;
- a source added or changed while the app remains continuously active may be reconsidered at the
  next scheduling evaluation or active transition;
- sequential work favors predictable resource use over maximum aggregate refresh throughput.

## Alternatives considered

- Exact timers were rejected because they do not survive suspension and would communicate a false
  execution guarantee.
- Busy or frequent polling was rejected for energy, performance and focus-stability reasons.
- `BGTaskScheduler` and new background entitlements were rejected for this slice because platform
  scheduling remains discretionary and the product has not established a supported background mode.
- Concurrent automatic refreshes were rejected to limit provider, network, memory and persistence
  pressure.
- Reimplementing provider refresh inside the scheduler was rejected because it would duplicate the
  validated Phase 2E path and weaken last-known-good behavior.

