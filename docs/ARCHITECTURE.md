# Architecture

## 1. Architectural goals

- Native Apple UX.
- testable core logic.
- fast local reads.
- provider implementations isolated from UI.
- playback engine replaceable without replacing screens.
- cloud sync optional to core local operation.
- large-catalog behavior designed from the start.

## 2. High-level structure

```text
AppleIPTV/
├── App/
│   ├── tvOS/
│   └── iOS/
├── Core/
│   ├── Domain/
│   ├── IPTVCore/
│   ├── Library/
│   ├── Playback/
│   ├── Persistence/
│   ├── CloudSync/
│   └── Security/
├── DesignSystem/
├── Tests/
├── docs/
└── decisions/
```

Exact Xcode grouping can evolve, but responsibilities must remain separated.

## 3. Layers

### Domain
Pure models and rules:
- MediaItem.
- Channel.
- Movie.
- Series.
- Episode.
- Category.
- Favorite.
- WatchProgress.
- SourceConfiguration without plaintext secret fields.

No SwiftUI dependency.

### IPTVCore
Provider adapters:
- M3U parser.
- Xtream-like provider client.
- XMLTV/EPG parser later.
- normalized provider errors.

Produces domain/import DTOs, not views.

### Library
Use cases and query interfaces:
- refresh source.
- fetch home sections.
- browse category.
- search.
- favorites.
- continue watching.

### Persistence
Local, fast, rebuildable storage for catalog and EPG.

Expose protocols so persistence can be benchmarked or replaced without affecting UI.

Phase 2D implements the SDK system SQLite library behind `CatalogImportRepository` and
`CatalogQueryRepository`, with actor-isolated transactions and bounded indexed pages.
[ADR-0008](../decisions/ADR-0008-local-catalog-persistence.md) records the selection for review;
[Phase 2D evidence](PHASE_2D_PERSISTENCE.md) records measured bulk imports and queries.
Normal app launch now consumes the committed catalog through a bounded production presentation and
paging boundary. Explicit Phase 1 modes retain synthetic Home data, and production catalog rows are
not converted to synthetic `MediaItem` values. See
[ADR-0012](../decisions/ADR-0012-production-library-ui-composition.md) and
[Production Library and Search UI](PRODUCTION_LIBRARY_UI.md). This post-Phase-2 composition does not
change the Phase 2 exit gate.
Phase 2E adds the provider-neutral `CatalogRefreshService`, multi-partition source staging and local
refresh metadata. Xtream live/VOD/series and success metadata publish in one final transaction after
all network/normalization work succeeds. See [ADR-0009](../decisions/ADR-0009-durable-source-refresh.md)
and [Phase 2E evidence](PHASE_2E_REFRESH.md).
Phase 2F extends the same repository with bounded literal substring search, origin/source/kind/category
filters and committed category counts. The injected `CatalogLibraryService` is the provider-neutral
query boundary for future app UI. Search and browse never read staging tables. See
[Phase 2F evidence](PHASE_2F_LIBRARY_SEARCH.md).

Post-Phase-2 source management stores small, user-authored `SourceConfiguration` records in a
versioned, atomically replaced Application Support JSON registry. It keeps credentials in Keychain
and rebuildable catalog/refresh state in SQLite. `SourceManagementService` owns validation and
explicit compensation across those stores, with catalog deletion last. See
[ADR-0010](../decisions/ADR-0010-local-source-registry.md) and
[Source Management and Validation](SOURCE_MANAGEMENT.md).

Refresh Scheduling & Policy is **COMPLETE**, merged through PR #21 at merge commit `18ba431`;
post-merge CI run `34449661574` succeeded. Schema version 2 adds a non-secret per-source refresh
policy, with explicit version 1 migration to manual-only. The pure domain evaluator derives
due/cooldown state from local refresh metadata. The actor-isolated Library scheduler deterministically
delegates at most one automatic source at a time to the existing durable refresh service. App
composition owns one cancellable active-session loop using Swift Concurrency; it provides no
suspended/terminated execution guarantee or background entitlement. See
[ADR-0011](../decisions/ADR-0011-refresh-scheduling-policy.md) and
[Refresh Scheduling and Policy](REFRESH_SCHEDULING.md). Production library/search composition is
complete, merged through PR #24 at `1763189`, and post-merge CI run `34598275534` succeeded;
successful durable refresh commits publish a bounded
in-process revision signal consumed by that UI, while foreground/source-return reloads remain
explicit lifecycle events.

### Playback

Phase 3 implements the Playback boundary:

```swift
@MainActor
protocol PlaybackEngine {
  var events: AsyncStream<PlaybackEngineEvent> { get }
  func load(_ asset: PlaybackAsset, attemptID: UUID)
  func play()
  func pause()
  func seek(to seconds: TimeInterval) async
  func stop()
}
```

`NativeAVPlayerEngine` is the only implementation. Main-actor isolation contains AVPlayer,
AVPlayerItem, observations and AVPlayerViewController without unsafe Sendable wrappers. The
presentation-safe `PlaybackSession` accepts normalized events, rejects stale attempt UUIDs, performs
safe resume after a finite seekable timeline is known, and applies throttled progress/completion
policy.

The Library-layer resolver turns one stable catalog ID into an ephemeral `PlaybackAsset`. M3U uses
the exact committed HTTP/HTTPS media URL and remains `.unspecified`; the current Xtream live/VOD and
series contract is explicitly unsupported because it lacks a reviewed final path/container and
episode-resolution model. No SwiftUI view receives a URL, credential or provider reference.

Durable versioned `WatchProgress` lives in an actor-isolated Application Support repository,
separate from rebuildable catalog SQLite. Finite seekable non-live playback is eligible; clearly
live media is not. Playing writes require 12 seconds and 5 seconds of movement, lifecycle/pause/end
checkpoints are forced, and the completion threshold is 95%. Phase 3 performs no CloudKit write.

Both platform apps bridge the engine-provided AVPlayerViewController for system playback controls.
See [ADR-0013](../decisions/ADR-0013-native-playback-foundation.md) and
[Playback Foundation](PLAYBACK_FOUNDATION.md). Physical Apple TV playback validation remains the
Phase 3 exit gate.

### CloudSync
Owns:
- CloudKit availability/account state.
- watch-progress synchronization.
- favorites synchronization.
- conflict resolution.
- sync queue/retry.

Cloud sync failures must degrade gracefully to local behavior.

### Security
Owns:
- Keychain operations.
- credential references.
- redaction helpers.
- safe diagnostic representation.

### DesignSystem
Owns:
- typography tokens.
- spacing tokens.
- corner radii.
- card treatments.
- tvOS focus effects.
- loading placeholders.
- badges.
- motion policy.

## 4. State management

Prefer explicit feature/view models and observable state scoped to screens or flows.

Do not create a giant `AppState` containing the whole application.

Keep remote/provider state, persisted library state and ephemeral UI state distinct.

## 5. Dependency injection

Use constructor injection or environment-injected interfaces for services.

Avoid hidden global mutable dependencies.

Production composition happens at app entry points; tests can supply fakes.

## 6. Data flow — provider refresh

```text
User requests refresh
  -> Source use case
  -> Validate source and resolve credentials where required
  -> M3U acquisition or provider adapter fetches/decodes off-main
  -> Normalize provider data
  -> Query-invisible bounded staging and complete validation
  -> Short atomic live replacement plus successful refresh metadata
  -> UI observes/query refresh
```

Do not delete the previous usable catalog before the replacement import is valid.

## 7. Data flow — Continue Watching

```text
Player emits local progress
  -> Progress policy throttles updates
  -> local store writes progress
  -> Phase 4 CloudSync later enqueues a compact sync record
  -> Phase 4 CloudKit private DB saves asynchronously
  -> Phase 4 another device receives/fetches newer state
  -> Phase 4 conflict resolver chooses deterministic winner
  -> future Continue Watching UI updates
```

Phase 3 implements only the first two steps. Playback does not access or wait on CloudKit.

## 8. Conflict policy baseline

For simple watch progress, use deterministic metadata including:
- content stable ID.
- position.
- duration.
- updatedAt.
- completed flag.
- source/device metadata only if useful for diagnostics/conflict logic.

Last-write-wins alone may be wrong when one device reports a stale lower position after another device advanced. Implement tests for competing updates before final policy is frozen.

## 9. Stable IDs

Provider IDs are not automatically globally stable.

Construct stable identities using provider/source identity plus provider media identifier where possible. Do not key CloudKit records only by human title.

## 10. Offline/degraded operation

When the provider or CloudKit is unavailable:
- cached catalog remains browsable if valid.
- favorites/progress update locally.
- sync retries later.
- playback can continue if media URL remains valid/reachable.

## 11. Observability

Use structured logs/categories such as:
- app lifecycle.
- source refresh.
- parsing/import.
- database queries.
- playback.
- cloud sync.
- image pipeline.

Never log secrets or full credential-bearing URLs.
