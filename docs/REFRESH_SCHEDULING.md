# Refresh Scheduling and Policy

## Scope and status

Refresh Scheduling & Policy is **COMPLETE**, merged through PR #21 at merge commit `18ba431`;
post-merge CI run `34449661574` succeeded. It is a post-Phase-2 application-integration slice. Phase
2 remains complete, final production library/search UI remains unstarted, and this work adds no
Phase 3 playback behavior.

## Policy choices

Every source stores one policy:

- Manual only — the default for new and migrated sources.
- Every 6 hours.
- Every 12 hours.
- Daily.

Automatic choices define eligibility intervals. They do not promise exact execution at a displayed
time. Manual Refresh Now remains available for enabled sources and bypasses automatic cadence and
retry cooldown.

## Due semantics and cooldown

`RefreshPolicyEvaluator` evaluates a source, its local refresh metadata and an injected `now`:

- disabled source: not due and has no automatic wake date;
- manual-only source: not due and has no automatic wake date;
- enabled automatic source with no successful refresh: due immediately;
- successful source: due at last successful refresh plus its cadence;
- recent failed or cancelled attempt: waits for a 30-minute retry cooldown when that boundary is
  later than the cadence boundary.

Cadence is elapsed-time based and does not shift with locale or time-zone changes. The evaluator is
pure domain logic and has no UI, networking or persistence dependency.

## Scheduler and lifecycle

`RefreshSchedulingService` is an actor. It lists the small source registry, reads local refresh
metadata, evaluates all sources, and runs due sources one at a time through the existing
`CatalogRefreshService`. Due work is ordered by oldest eligibility and then stable source ID.
Automatic refresh concurrency is therefore exactly one. A failure is recorded as a safe outcome and
does not block the next due source; an already-running same-source refresh becomes `inProgress`.

The tvOS and iOS app entry points lazily create shared source services without delaying rendering.
The first active scene notification evaluates work. Later foreground/active transitions evaluate
again. While active, the coordinator uses cancellable Swift Concurrency sleep until the next known
eligibility date. Duplicate notifications coalesce to one active session. Leaving active cancels the
session task; there is no detached task, `Timer`, semaphore, busy polling or background entitlement.

iOS and tvOS may suspend or terminate the app. Automatic refresh therefore resumes on a later active
opportunity and is not guaranteed to execute while suspended or terminated. No CloudKit or remote
scheduling service is involved.

## Cancellation and catalog safety

Cancellation reaches the current delegated refresh and prevents later queued sources from starting.
Sources that completed earlier in the cycle remain committed. Phase 2E staging and atomic publication
continue to protect every source's last-known-good catalog from failure or cancellation.

## Persistence and migration

The durable source registry schema is version 2. `RefreshPolicy` is stored with the existing
non-secret source metadata. Version 1 is decoded explicitly and migrated atomically to version 2 with
`manualOnly`, preserving source ID, display name, kind, endpoint, `CredentialReference` and enabled
state. Corrupt registries and unsupported future versions still fail without an automatic reset.

## Security and privacy

Policy state contains no provider URL, username, password or token. The registry stores only the
existing opaque `CredentialReference`; credentials remain in the device-local Keychain. Updating
only an Xtream source's policy retains the same reference and performs no credential read or write.
Automatic scheduling performs no direct Keychain access, provider parsing or SwiftUI access.

## tvOS experience

The source editor offers a focused, native segmented scheduling control and safe status for current
policy, last successful refresh, last attempt, next eligibility and disabled-source pause. Copy says
that automatic work runs while AEVYNO is active and resumes on the next active opportunity. Status
changes are non-focusable and do not steal Siri Remote focus.

All scheduling copy and accessibility labels are localized in English, German and Arabic. Layout
uses native SwiftUI direction and semantic leading alignment; no string reversal or bidirectional
layout hack is used. Dates use Apple locale-aware formatting.

## Validation

Deterministic shared tests cover policy boundaries, time-zone independence, retry cooldown,
sequential ordering, failure isolation, coalescing, cancellation, lifecycle waiting, source-registry
migration, manual-refresh bypass and unchanged-credential edits. tvOS UI automation covers the eight
required scheduling scenarios using injected synthetic fixtures and no live network.

Local final validation on Xcode 26.6 passed 132 shared tests in 13 suites and all 22 tvOS UI tests on
the Apple TV 4K (3rd generation), tvOS 26.5 simulator, with zero failures. Generic tvOS and iOS
Simulator builds, both static analyzers, strict all-Swift formatting lint and `git diff --check` also
passed. Post-merge CI run `34449661574` succeeded on merge commit `18ba431`, including Core / Build /
Analyze and tvOS UI Tests.

Physical Apple TV LTR/Arabic RTL focus, viewing-distance layout, foreground transition and
long-session behavior remain **PENDING**; simulator evidence does not satisfy that device gate.

See [ADR-0011](../decisions/ADR-0011-refresh-scheduling-policy.md).
