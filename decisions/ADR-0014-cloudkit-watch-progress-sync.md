# ADR-0014 — CloudKit Watch Progress Synchronization

Status: Accepted
Date: 2026-09-13

## Context

Phase 3 stores durable `WatchProgress` locally by stable media ID. Phase 4A must synchronize that
small user-authored state between Apple TV and iPhone/iPad without making playback depend on network
or iCloud availability, exposing CloudKit types outside `Core/CloudSync`, or allowing a stale device
to move progress backward.

Wall-clock last-write-wins is unsafe: device clocks can differ, a late stale checkpoint can have a
newer timestamp, and an incomplete checkpoint must not resurrect Resume after completion. Completion
also cannot be permanently sticky because Start Over is an intentional user action.

The repository contains no development-team setting, CloudKit container identifier, iCloud
entitlements, or remote-notification entitlement that can be configured without owner input.

## Decision

### Ownership and boundary

- `FileWatchProgressRepository` remains the durable local source used when iCloud is absent.
- `LocalFirstCloudWatchProgressRepository` writes locally first and only then records a compact
  outbound sync intent. Cloud failure is not returned as a local playback failure.
- `WatchProgressSyncCoordinator` is actor-isolated. It coalesces one pending record per media ID,
  pulls remote changes, resolves conflicts, persists a resolved local value, and uploads only when
  convergence requires it. SwiftUI and `PlaybackSession` do not import CloudKit.
- `CloudWatchProgressStore` and `WatchProgressSyncStateStore` are deterministic test boundaries.
  Tests use no Apple ID, CloudKit container, or public network.

### Private CloudKit schema

`PrivateCloudKitWatchProgressStore` always selects the injected `CKContainer`'s private database. It
uses custom zone `AEVYNO_WatchProgress_v1`, record type `AEVYNO_WatchProgress_v1`, and a SHA-256
record name derived from the stable media ID. Schema version 1 fields are:

- `schemaVersion`;
- `mediaID`;
- `positionSeconds`;
- `durationSeconds`;
- `updatedAt`;
- `completed`;
- `resetGeneration`;
- `logicalRevision`; and
- `operationID`.

Playback/source URLs, provider references, credentials, tokens, account identifiers, catalog rows,
artwork, and EPG data are excluded. CloudKit records and payloads are not logged.

### Deterministic conflict algorithm

The resolver validates both schema and identity, then compares in this order:

1. higher `resetGeneration` wins;
2. within one generation, completed beats incomplete;
3. otherwise, farther absolute position wins, preventing resume regression;
4. equivalent position uses higher `logicalRevision`;
5. remaining duration/equivalent-state ties use stable `operationID`; and
6. `updatedAt` is only a final deterministic tie-break for duplicate operation IDs, never the
   primary state-ordering mechanism.

Duration belongs to the winning semantic state. A duration difference alone cannot override
completion, an intentional reset generation, or farther progress. Duplicate delivery resolves to
the same record and does not cause another upload.

Start Over is an explicit local mutation. It immediately writes position zero/incomplete using the
known duration and queues a pending reset. After fetching changes, the coordinator rebases that
pending reset to one generation above the greatest competing remote generation before upload. Later
checkpoints retain the reset intent until upload succeeds. This lets a deliberate reset supersede a
prior completion without allowing an ordinary stale incomplete checkpoint to clear completion.

### Change tracking, retries, and degraded operation

- The adapter creates one private custom zone and a silent record-zone subscription.
- Incremental fetches use `CKFetchRecordZoneChanges` through the async database API with an opaque
  persisted `CKServerChangeToken`. The token and per-item sync metadata live in
  `Application Support/AEVYNO/watch-progress-sync.json`, separate from catalog SQLite and
  `watch-progress.json`.
- An expired server token triggers one full zone refetch; there is no periodic full-record polling.
- Fetch pages and save batches are bounded. Pending writes are coalesced by media ID.
- Before a save, the adapter resolves against the latest fetched server record and writes with
  `ifServerRecordUnchanged`. It returns the committed semantic record so the coordinator persists
  the same value locally; a change-tag race becomes a bounded conflict retry instead of an overwrite.
- Network, service, rate-limit, and server-conflict errors use a bounded exponential retry policy.
  Server retry hints are capped by the policy. Timing is injectable; there is no `Timer`, semaphore,
  busy loop, or infinite immediate retry.
- Missing/restricted accounts enter a presentation-safe unavailable state. Temporary account,
  network, and service conditions can retry. Quota, schema, configuration, and terminal service
  errors are normalized without exposing `CKError`.
- Each synchronization has a generation. Cancellation or a newer generation prevents an older fetch
  from publishing local metadata or status.
- Corrupt or unsupported sync metadata fails non-destructively. It never deletes or rewrites the
  independent local `WatchProgress` file.

### Configuration status

The production adapter is initialized with an injected `CKContainer`; no identifier is fabricated.
Before device/account validation, the owner must select the Apple development team, enable iCloud +
CloudKit for both app targets, select/create the real container, enable remote notifications for the
record-zone subscription, and deploy the schema to the intended CloudKit environment. Those manual
steps require the correct Apple Developer account and are not committed in this slice.

## Consequences

Positive:

- playback and local progress remain usable offline and without iCloud;
- deterministic tests cover convergence, reset, retry, cancellation, schema, and persistence;
- CloudKit implementation details stay inside `Core/CloudSync`;
- synchronization scales with zone changes instead of repeatedly downloading every record.

Tradeoffs and limits:

- the real adapter compiles but is not enabled until the project has owner-approved entitlements and
  a real container;
- foreground/explicit sync triggers can use the coordinator now; push-driven app lifecycle wiring
  requires the entitlement/container setup and device validation;
- Phase 4B extends the same private-zone/local-first architecture to Favorites with a separate
  `AEVYNO_Favorite_v1` record type, durable favorite repository, persisted change token and retained
  removal tombstones. Its deterministic ordering is logical revision, tombstone over add at an equal
  revision, operation ID, then timestamp only for duplicate operation IDs. A later intentional add
  advances the revision. Favorites UI and Continue Watching UI remain outside this slice;
- Apple TV-to-iPhone and iPhone-to-Apple TV resume remain unverified until two signed devices use the
  same iCloud account and configured production/development container.
