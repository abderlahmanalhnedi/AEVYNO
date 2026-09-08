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
The current app shell still consumes synthetic Phase 1 data; production query/UI composition is later work.
Phase 2E adds the provider-neutral `CatalogRefreshService`, multi-partition source staging and local
refresh metadata. Xtream live/VOD/series and success metadata publish in one final transaction after
all network/normalization work succeeds. See [ADR-0009](../decisions/ADR-0009-durable-source-refresh.md)
and [Phase 2E evidence](PHASE_2E_REFRESH.md).

### Playback
Define a playback abstraction, for example conceptually:

```swift
protocol PlaybackEngine {
    func prepare(_ request: PlaybackRequest) async throws
    func play()
    func pause()
    func seek(to: TimeInterval) async throws
    var state: PlaybackState { get }
}
```

The initial implementation is AVFoundation/AVPlayer.

The UI consumes playback state, not AVPlayer internals where avoidable.

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
  -> CloudSync enqueues compact sync record
  -> CloudKit private DB saves asynchronously
  -> another device receives/fetches newer state
  -> conflict resolver chooses deterministic winner
  -> local Continue Watching updates
```

Playback must not wait on CloudKit.

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
