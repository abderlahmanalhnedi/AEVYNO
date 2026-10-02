# Project Status

Last updated: 2026-10-01

## Current phase

**Phase 1 physical validation open; Phase 2 complete; Phase 3 implemented with physical exit gate
pending; Phase 4A Watch Progress Sync implemented on main; Phase 4B Favorites Sync implemented on
main; Phase 4 remains open for signed CloudKit validation; Phase 5A Continue Watching implemented
with simulator gates passed and real-device validation pending; Phase 5B Favorites UI implemented
on main with CI/simulator gates passed and physical review pending; Phase 5C mobile source management
implementation and automated exit gate complete on main; physical review pending**

Phase 6A XMLTV/EPG foundation is stable on main through PR #31 at merge commit
`f9169da9f209dbcaf7528ba1819f1ca4aaf2bea6`; post-merge CI `35524819690` succeeded. Phase 6B
XMLTV acquisition and Now/Next is stable on main through PR #32 at merge commit
`5726e6287ddcf733363c9086d6b228f8416c9ba9`; post-merge CI `35624332615` succeeded. Phase 6C EPG
Guide UI is stable on main through PR #33 at merge commit
`5eeaf9ddabe36f45f455dc48565c48b2d3a7888f`; post-merge CI `35757673052` succeeded. Phase 6D XMLTV
compatibility/import resilience is stable on main through PR #34 at merge commit
`f99bbd8d820e456086ad62648495825794be1804`; post-merge CI `36630491502` succeeded after an initial
tvOS Favorites focus simulator/SwiftUI flake. The focused test reproduced as passing 3/3 after a
simulator restart, related Favorites tests passed, and the CI rerun completed with 61/61 tvOS UI
tests. Phase 6E EPG freshness and safe status is stable on main through PR #35 at merge commit
`f3d6707109db42ae4518409f33f594856f29db2b`; post-merge CI `36755959432` succeeded. Phase 6F-A
real-provider XMLTV validation is **BLOCKED / PENDING EXTERNAL VALIDATION INPUT**: no owner-approved
real XMLTV, M3U, or persisted AEVYNO provider source is available; no compatibility defect was found
and no production change was made. Phase 6F-B bounded Guide time navigation is **STABLE ON MAIN**
through PR #36 at merge commit `5a50668a8d4cedeed4b43ff86f0d7e9499d3aac0`; post-merge push CI
`36898632649` succeeded for both Core / Build / Analyze and tvOS UI Tests. Physical Apple TV Guide
focus/navigation, EPG performance and Arabic RTL review, EPG health/status focus review, and physical
iPhone/iPad touch/layout/status review remain pending. Local scale/RSS evidence is not physical-device
performance evidence; owner-approved real-provider XMLTV corpus validation remains blocked.
Source URL guessing, Xtream EPG, CloudKit EPG, tokenized XMLTV URLs, and an unbounded timeline remain
out of scope.

Phase 0 is complete in simulator. Its physical Apple TV validation remains pending because
the owner is currently away from the device; the Phase 0 roadmap exit allows this explicit
deferral. The existing Phase 1 shell has completed simulator hardening. Its Apple-native localization
foundation for English, German and Arabic now covers the current tvOS and iOS surfaces, and the
Arabic RTL Home, Detail and state flows have been simulator-validated. Phase 1 remains incomplete
until the real Apple TV UX review passes in both LTR and Arabic RTL.
Phase 2 is complete on `main` at `b557347` through merged PR #17. Its approved roadmap deliverables
and exit gate are satisfied by the documented 50k/100k import, refresh and query benchmarks, atomic
last-known-good catalog behavior, and successful post-merge CI run `34321067413` on that exact
commit. The post-Phase-2 Source Management & Validation Flows follow-up is **COMPLETE**, merged
through PR #19 at merge commit `1c94236`; post-merge CI run `34386676789` succeeded. Refresh
Scheduling & Policy is **COMPLETE**, merged through PR #21 at merge commit `18ba431`; post-merge CI
run `34449661574` succeeded. Production Library/Search UI Composition is **COMPLETE**, merged
through PR #24 at `1763189`; post-merge CI run `34598275534` succeeded. Phase 3 Playback Foundation
is implemented on `main` at `55e55a0` through PR #25; post-merge CI run `34746573352` succeeded. Its
physical Apple TV exit gate remains **PENDING**. Phase 4A Watch Progress Sync is **IMPLEMENTED on
main**. Phase 4B Favorites Sync is **IMPLEMENTED on main through PR #27 at `252d620`**; post-merge
CI `34783856312` succeeded. Phase 4 is **NOT COMPLETE** because real CloudKit
entitlement/container configuration and signed cross-device validation remain pending.

## Verified development environment

- selected developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Xcode 27.0 (build 27A266a).
- Swift 6.4.
- iOS 26.5 SDK and simulator runtime available; iOS 17.5 runtime also available.
- tvOS 26.5 SDK and simulator runtime available.
- Apple TV 4K (3rd generation), 1080p variant and Apple TV simulators available.

The former Command Line Tools / missing `simctl` blocker is resolved.

## Phase 0 delivered

- `AEVYNO.xcworkspace` and native `AEVYNO.xcodeproj`.
- `AEVYNOTV` and `AEVYNOiOS` shared schemes.
- Domain, IPTVCore, Library, Playback, Persistence, CloudSync, AEVYNOSecurity and DesignSystem
  local Swift package products.
- deterministic synthetic Home sections for Continue Watching, Movies, Series, Live TV
  and Favorites.
- shared loading, loaded, empty and safe error-state foundations.
- tvOS-first lazy rails, accessible cards, native focus state, restrained focus treatment
  and Reduce Motion support.
- touch-adapted iPhone/iPad companion shell without tvOS focus behavior.
- Swift Testing coverage for module imports, deterministic Home data and Home state logic.
- tvOS XCUITest coverage for launch, initial card focus and right-direction focus movement.

## Phase 1 simulator-validated development delivered

- original, cinematic Home hero and refined lazy rails for Continue Watching, Movies,
  Series, Live TV and Favorites.
- reusable landscape, poster and live card families with stable geometry, restrained focus
  scale, explicit live/progress semantics and synthetic artwork.
- native tvOS Detail presentation with title, metadata, concise description, accessibility
  semantics, a safe no-playback primary action and temporary demo-only secondary state.
- native `NavigationStack` and `FocusState` flow that remembers deterministic media IDs and
  restores focus to the opened card after returning from Detail in simulator UI automation.
- stable, non-focusable loading skeletons; intentional empty state; concise error state with
  a focusable Retry action.
- injected actor-isolated artwork pipeline with request cancellation, target-size synthetic
  rendering, ImageIO downsampling support, a 48 MiB default LRU memory bound and memory-
  warning purge behavior. No network artwork service or third-party dependency was added.
- deterministic 10k, 50k and 100k synthetic catalog address spaces. The tvOS stress mode
  materializes a bounded 800-item Home snapshot instead of retaining a full catalog in
  SwiftUI state.
- expanded shared and tvOS UI automation for Detail, navigation/focus restoration, safe
  placeholder action, Home states, cache bounds/cancellation and fixture determinism.
- simulator hardening prevents a memory-warning purge from being undone by artwork work
  already in flight, disables eager ImageIO source caching before downsampling, and adds
  deterministic LRU, cost, oversized-image, purge, malformed-data, full address-space ID
  uniqueness and simulator accessibility coverage.
- a shared Apple String Catalog provides complete English, German and Arabic values for current
  app-owned Home, Detail, loading, empty, error, Retry, preview-notice and accessibility text on
  tvOS and iOS/iPadOS, including the synthetic Phase 1 preview presentation.
- native SwiftUI layout direction drives Arabic RTL without manual string reversal, forced
  direction overrides, duplicated Arabic components or artwork/media-glyph mirroring. Stable media
  IDs continue to drive tvOS focus memory and restoration.

## Phase 2A source/security foundation

- Phase 2 development has started in parallel while Phase 1 remains open.
- source configuration models provide stable IDs, Xtream-compatible and M3U kinds,
  non-credential endpoint metadata, indirect credential references and enabled state.
- source configurations are value-semantic, Codable and Sendable, with no plaintext password
  or token fields and no dependency on SwiftUI or Keychain APIs.
- the `AEVYNOSecurity` package boundary provides an async credential-store protocol and an
  actor-isolated Apple Keychain implementation for username plus password/token-like material.
- Keychain items are device-local generic-password records using
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; raw Keychain status values and secrets are
  excluded from safe diagnostics.
- reusable exact-value and URL sanitization helpers redact sensitive diagnostic content.
- no provider networking, M3U parsing, catalog persistence, source-management UI or playback
  implementation is included in Phase 2A.

## Phase 2B M3U parser/import foundation

- `IPTVCore` accepts asynchronous line sequences and incrementally parses basic and extended M3U
  without materializing a playlist-wide string or entry array. `M3UDataLineSequence` provides a
  cancellation-aware UTF-8/BOM/LF/CRLF adapter for already available data, while future file or
  network adapters can supply lines directly.
- the parser supports `#EXTM3U`, `#EXTINF`, quoted and unquoted attributes, whitespace variations,
  commas in display titles, `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, optional non-negative
  duration, blank lines, comments and unknown attributes.
- only absolute HTTP and HTTPS media/artwork URLs are accepted. Media URL path and query semantics are
  preserved; local/file URLs are outside the Phase 2B scope. Parsing performs no network request.
- malformed entries are skipped without crashing an otherwise usable playlist. Fatal invalid UTF-8
  and no-playable-entry errors, skipped counts and bounded warning summaries are explicit and contain
  no raw playlist lines or URL values.
- the `Library` import service writes through an asynchronous transactional sink in bounded batches
  of 256 by default. Cancellation and sink/parser failures roll back staged work instead of returning
  partial success. No production persistence implementation was added.
- stable imported IDs are SHA-256 digests scoped to the source ID. A non-empty `tvg-id` is preferred;
  the exact media URL is the fallback. Duplicate anchors are preserved with deterministic occurrence
  identities and reported rather than aggressively deduplicated. ADR-0006 records the decision.
- normalized output contains title, media URL, optional group/artwork/TVG metadata and optional
  duration. Unknown raw attributes and extracted credential fields are not retained, and default item
  diagnostics redact media/artwork URLs.

## Phase 2C Xtream-compatible provider adapter foundation

- `IPTVCore` defines a provider adapter boundary and an Xtream-compatible implementation for
  authentication/account discovery, live/VOD/series categories, live streams, VOD streams and the
  series list. EPG and playback URL generation are intentionally excluded.
- credentials are resolved through the Phase 2A `CredentialStore` boundary. The centralized request
  builder uses `URLComponents`, an explicit 15-second default timeout and credential-bearing query
  items only for the request lifecycle; normalized models and errors contain no credentials or raw
  response bodies.
- the production Foundation transport uses async `URLSession` with an ephemeral, cacheless and
  cookieless configuration. It adds no retry, certificate-pinning or transport-security relaxation.
- provider-private DTOs tolerate common string/numeric/null/missing optional variations. Invalid
  required IDs or titles are skipped and counted, invalid top-level JSON is a safe normalized error,
  and an empty provider array is accepted as an empty catalog.
- domain-safe categories and catalog items include source-scoped SHA-256 identity, title, media kind,
  optional category/artwork references and the provider item ID needed for a future resolver. They do
  not contain stream URLs, usernames, passwords or tokens.
- `Library` consumes normalized items through a transactional sink in bounded batches of 256 by
  default. Cancellation and adapter/sink failures roll back staged work; no production persistence
  implementation was added.
- ADR-0007 records the Xtream adapter, import boundary and deterministic source/kind/provider-ID
  identity decisions.

## Phase 2D production persistence foundation

- Apple system SQLite (SDK `SQLite3`, no third-party package) implements actor-isolated local
  catalog storage behind `CatalogImportRepository` and `CatalogQueryRepository`.
- Schema v2 persists catalog partitions, exact stable item IDs, source-scoped categories, original
  titles, indexed normalized titles and encrypted opaque media/artwork/provider references.
  ADR-0008 records the technology comparison, schema boundary and encrypted-reference design.
- Acquisition/parsing writes to invisible encrypted staging in short batches and holds no SQLite
  writer transaction across network waits. After validation, one final transaction copies staged
  rows in bounded batches and atomically replaces the source/origin/kind partition. An independent
  WAL reader keeps the previous committed catalog visible until commit. Parser/transport/write/
  commit failure and cancellation preserve the previous catalog. Version 1 migrates to version 2
  transactionally without changing committed items.
- `PersistentCatalogImportSink` supports the existing M3U and Xtream services. The Xtream service
  stages categories with items when the sink supports categories; M3U group IDs remain source-scoped,
  and M3U media kind is explicitly unspecified rather than guessed.
- Database-backed item/category pages support source/kind/category filters, deterministic ordering,
  item lookup, counts and cancellation. Page size is capped at 256; no catalog-wide UI state was added.
- Source catalog deletion leaves other sources and all Keychain/progress/favorites state untouched.
- CryptoKit AES-256-GCM protects opaque URL/reference payloads with a separate device-local Keychain
  key. No provider credential fields, raw responses or diagnostics are serialized; no CloudKit catalog
  sync exists. The default database is a backup-excluded rebuildable cache, subject to tvOS purge.
- Schema ownership/version checks reject unknown/corrupt stores without destructive reset.
- [Phase 2D evidence](docs/PHASE_2D_PERSISTENCE.md) records synthetic 10k/50k/100k import, replacement,
  query and reopen measurements, failure tests, privacy limits and reproduction commands.
- Physical Apple TV performance/cache/Keychain validation and Phase 1 LTR/Arabic RTL UX review remain
  **PENDING**. These device checks do not belong to the approved Phase 2 exit gate; Phase 3 playback
  has not started.

## Phase 2E durable source refresh foundation

- `Library` now exposes an actor-isolated, provider-neutral `CatalogRefreshService` with explicit
  dependencies and safe validating/acquiring/parsing/staging/committing/completed/failed/cancelled
  lifecycle stages. It has no SwiftUI or `MainActor` dependency.
- remote M3U acquisition uses Foundation `URLSession` async bytes with ephemeral/cacheless/cookieless
  configuration, a 30-second request timeout, no retries, safe redirects and a 64 MiB maximum enforced
  from both declared and actually received bytes. Errors and logs never contain full URLs or bodies.
- Xtream refresh reuses the existing credential-backed `XtreamProviderAdapter`, request builder,
  normalized models, bounded import service and persistent sink. Authentication plus live, VOD and
  series categories/items are refreshed; no final playback URL is generated.
- SQLite schema v3 supports one query-invisible staging ID across multiple source partitions.
  Xtream's three kinds and successful refresh metadata publish in one short final transaction only
  after acquisition, normalization, staging and integrity checks finish. Schema v1/v2 migrations
  preserve committed catalogs.
- local-only metadata records source ID, attempt/success times, committed item count and a safe result
  category. The committed count comes from distinct staged rows inside the final transaction.
  Failure/cancellation changes attempt/result only. A metadata commit failure rolls back catalog B
  and preserves catalog A plus its last-success values.
- a second same-source refresh returns `inProgress` without starting another attempt. Different-source
  acquisition and staging may overlap, while SQLite calls/final commits remain actor-serialized and
  bounded. There is no scheduler or implicit retry.
- deterministic synthetic coverage includes M3U HTTP/size/cancellation and full persistence flow,
  all Xtream kinds and failure classes, atomic last-known-good behavior, lifecycle/metadata semantics,
  schema migration, and the one-second slow-network writer-lock regression.
- [ADR-0009](decisions/ADR-0009-durable-source-refresh.md) records the durable orchestration,
  concurrency, multi-partition and metadata decisions. [Phase 2E evidence](docs/PHASE_2E_REFRESH.md)
  records reproduction commands, measured 10k/50k/100k results, privacy review and limitations.
- no source-management UI, scheduling, Phase 2F search/application integration, CloudKit catalog sync
  or Phase 3 playback work is included.

## Phase 2F production library search foundation

- `CatalogQueryRepository` and the production SQLite store now provide bounded literal substring
  search, origin/source/media-kind/category filters, deterministic ordering, exact lookup, counts and
  committed category summaries without materializing a catalog-wide Swift array.
- deterministic search normalization uses fixed POSIX case/diacritic folding and Unicode-whitespace
  term separation. All terms are literal unordered AND-substrings; punctuation, numbers, emoji and
  Arabic script are preserved. There is no transliteration, fuzzy matching or relevance ranking.
- the provider-neutral, injected `CatalogLibraryService` exposes async browse, search, category,
  lookup and count operations for future tvOS/iOS composition without SwiftUI, `MainActor`, provider
  networking or CloudKit dependencies.
- search input is limited to 16 KiB and 32 terms; pages remain limited to 256. Results use binary
  normalized-title plus stable-ID ordering, and invalid page/query/filter input fails explicitly.
- deterministic tests cover empty/edge states, English/German/Arabic/mixed-language titles,
  punctuation/emoji, duplicate-title pagination, source/origin/kind/category isolation,
  cancellation, deletion and a paused Phase 2E refresh proving staged catalog B remains invisible
  until its atomic commit replaces catalog A.
- [Phase 2F evidence](docs/PHASE_2F_LIBRARY_SEARCH.md) records exact semantics, architecture,
  security limits, 10k/50k/100k release measurements and remaining device/UI limitations.
- no final Search/browse UI, source-management UI, refresh scheduler, CloudKit catalog sync or Phase 3
  playback work was included in the Phase 2F slice. Those UI/scheduling items were assigned to the
  post-Phase-2 application-integration follow-up; scheduling and production library/search
  composition are complete. Neither item changes
  the completed Phase 2 exit gate.

## Post-Phase-2 Source Management & Validation Flows

Status: **COMPLETE**. Merged through PR #19 at merge commit `1c94236`; post-merge CI run
`34386676789` succeeded. Phase 2 remains complete.

- `FileSourceRepository` originally delivered the version 1 durable source registry at
  `Application Support/AEVYNO/sources.json`, outside the rebuildable catalog cache. Actor isolation,
  deterministic array ordering, atomic JSON replacement and explicit corrupt/unsupported-schema
  failures are covered. [ADR-0010](decisions/ADR-0010-local-source-registry.md) records the decision.
- `SourceManagementService` owns local validation, create/edit/delete compensation, enabled state,
  Test Connection and manual Refresh Now across the source repository, Keychain boundary and durable
  refresh/catalog services. Source metadata contains only an opaque `CredentialReference`; provider
  credentials remain device-local in Keychain.
- delete now reads existing state, deletes durable source metadata, deletes its credential when
  present, then transactionally deletes catalog and refresh metadata last. Earlier failures preserve
  the last-known-good catalog; catalog failure restores credential and source metadata; restoration
  failure is surfaced as `compensationFailure`.
- Test Connection uses a temporary Keychain reference for new/replacement Xtream credentials and
  removes it on success, provider failure and cancellation. M3U testing acquires and parses without
  catalog publication. Credential-bearing M3U URL user information, queries and fragments remain
  unsupported.
- the tvOS source-management UI provides loading/empty/error states, add/edit, secure credential
  replacement, validation focus restoration, enable/disable, manual refresh and confirmed delete.
  Stable source IDs restore list focus after returning from the editor, and operation status does
  not steal focus.
- English, German and Arabic strings, native Arabic RTL layout, localized accessibility labels and
  deterministic simulator UI flows are included. Physical Apple TV LTR/RTL focus and visual review
  remains **PENDING**.
- [Source Management and Validation](docs/SOURCE_MANAGEMENT.md) documents the workflows and current
  limitations. Production tvOS/iOS library/search composition is now **IMPLEMENTED; UNDER FINAL
  COMPLETE**, merged through PR #24 at `1763189`; post-merge CI run `34598275534` succeeded.

## Post-Phase-2 Refresh Scheduling & Policy

Status: **COMPLETE**. Merged through PR #21 at merge commit `18ba431`; post-merge CI run
`34449661574` succeeded. Phase 2 and Source Management & Validation Flows remain complete.

- source-registry schema version 2 durably stores a non-secret per-source policy. Explicit version 1
  migration preserves source metadata and `CredentialReference` while defaulting to manual-only;
  corrupt and unsupported future registries still fail without destructive reset.
- policy choices are manual-only, every 6 hours, every 12 hours and daily. The deterministic domain
  evaluator accounts for enabled state, missing/last successful refresh, elapsed cadence and a
  30-minute failed/cancelled-attempt cooldown.
- the actor-isolated scheduler reads the existing source and refresh-metadata boundaries, delegates
  only to `CatalogRefreshService`, executes due sources sequentially in deterministic order, isolates
  source failures, coalesces duplicate cycles and propagates cancellation to current work.
- tvOS and iOS composition evaluate on first activation and foreground transitions and may sleep
  until the next due instant while active. Scheduling is best-effort: suspended or terminated app
  execution is not guaranteed. No Timer, busy polling, background entitlement or CloudKit scheduling
  was added.
- manual Refresh Now bypasses automatic cadence/cooldown. Policy-only Xtream edits preserve identity,
  endpoint, enabled state and credential reference without Keychain credential rewrites.
- the tvOS editor exposes the scheduling control and safe scheduling metadata without focus-stealing
  status. English, German and Arabic resources, native RTL behavior and focused simulator automation
  are included. Physical Apple TV LTR/RTL validation remains **PENDING**.
- [ADR-0011](decisions/ADR-0011-refresh-scheduling-policy.md) records the decision and
  [Refresh Scheduling and Policy](docs/REFRESH_SCHEDULING.md) records behavior and limitations.

## Post-Phase-2 Production Library/Search UI Composition

Status: **COMPLETE**. Merged through PR #24 at `1763189`; post-merge CI run `34598275534`
succeeded. Phase 2, Source Management & Validation Flows and Refresh Scheduling & Policy remain
complete.

- normal tvOS and iOS/iPadOS launches use the committed local catalog through the shared
  `ProductionLibraryService`, `LibraryPagingController` and `ProductionLibraryViewModel` boundaries;
  Phase 1 synthetic modes remain available only through explicit demo/test launch arguments.
- presentation maps stable ID, title, exact catalog media kind, safe source/category display names
  and optional artwork only. It does not reuse `MediaItem` or fabricate synopsis, progress, rating,
  year, genre, favorites, Continue Watching or episode metadata. M3U `.unspecified` is presented only
  as Playlist.
- 64-item pages feed a maximum 256-item SwiftUI window. Superseded requests are cancelled, stale
  generations rejected, duplicate next-page requests suppressed, stable IDs defensively deduplicated
  and a protected focused item is not selected for eviction.
- Movies, Series, Live TV, Playlist, source/category filters and bounded literal title search reuse
  the Phase 2F query semantics. Disabled sources with committed catalog data remain locally
  browsable. Search changes use a 300 ms debounce.
- successful manual and automatic durable refresh commits publish an in-process revision. Returning
  from Sources and foreground activation also reload committed state. There is no Timer, database
  polling, busy loop, detached task or global AppState; failed/cancelled refresh keeps the
  last-known-good catalog.
- production artwork reuses the bounded `ArtworkImagePipeline` with cancellation, target downsampling
  and memory-warning invalidation. Remote responses use ephemeral cacheless/cookieless networking,
  a 15-second timeout and 12 MiB body cap; failures show a neutral kind placeholder without a
  fabricated artwork theme.
- tvOS provides production browse/search, safe metadata-only Detail and stable-ID focus restoration;
  iPhone/iPad use touch-adapted navigation without tvOS focus mechanics. English, German and Arabic
  strings, native RTL and URL/credential-free accessibility semantics are included.
- [ADR-0012](decisions/ADR-0012-production-library-ui-composition.md) records the composition decision.
  [Production Library and Search UI](docs/PRODUCTION_LIBRARY_UI.md) records behavior, exact bounds,
  security limits and remaining physical-device validation.

## Phase 3 Playback Foundation

Status: **IMPLEMENTED; PHYSICAL APPLE TV EXIT GATE PENDING**.

Merged through PR #25 at `55e55a0`; post-merge CI run `34746573352` succeeded.

- `PlaybackEngine` is a main-actor boundary with load/play/pause/seek/stop commands and normalized
  attempt-scoped events. `NativeAVPlayerEngine` is the only implementation and owns all AVPlayer,
  AVPlayerItem, observation, timing, and AVPlayerViewController state.
- the Library resolver looks up exactly one stable catalog identity. A committed M3U item uses its
  exact accepted HTTP/HTTPS media URL and remains `.unspecified`. Xtream live/VOD return
  `unsupported` because the persisted contract lacks a reviewed final playback path/container;
  series additionally lacks episode enumeration and episode identity.
- playback URLs are ephemeral and redacted. They are absent from presentation/accessibility and
  from durable `WatchProgress`, which records only stable ID, position, duration, timestamp and
  completion in an atomically replaced versioned Application Support file outside catalog SQLite.
- finite seekable non-live playback receives throttled local checkpoints, Resume, Start Over, and a
  95% completion rule. Clearly live media receives no VOD progress. Phase 3 adds no CloudKit writes.
- tvOS and iOS/iPadOS use native `AVPlayerViewController` controls with shared session logic and
  platform-specific navigation. English, German and Arabic/RTL presentation, safe errors, explicit
  fresh-resolution Retry, deterministic engine/resolver/progress fixtures, and playback UI modes
  are included.
- [ADR-0013](decisions/ADR-0013-native-playback-foundation.md) records the decision and
  [Playback Foundation](docs/PLAYBACK_FOUNDATION.md) records support, exact semantics, fixture
  matrix, security constraints, evidence, and the physical-device checklist.
- no second engine, VLC/FFmpeg, provider URL guessing, broad ATS relaxation, TLS bypass, DRM
  circumvention, background entitlement, or Phase 4 implementation was added.

## Phase 4A Cloud Continuity — Watch Progress

Status: **IMPLEMENTED; CLOUDKIT CONFIGURATION AND REAL-DEVICE EXIT GATES PENDING**.

- `FileWatchProgressRepository` remains the durable local source. The local-first cloud decorator
  writes it before recording asynchronous/coalesced outbound work; playback never waits for CloudKit.
- cloud schema version 1 contains only stable media ID, position, duration, completion, update time,
  reset generation, logical revision, and operation ID. It excludes URLs, provider/credential
  references, credentials, account IDs, catalog data, artwork, and EPG.
- deterministic conflict order prevents lower stale progress and stale incomplete completion
  resurrection. Explicit Start Over is persisted locally and rebased above fetched remote reset
  generations, so completion can be legitimately cleared.
- the actor-isolated coordinator pulls incremental custom-zone changes, coalesces outbound records,
  persists an opaque change token separately from catalog/progress state, resolves/persists local
  convergence, applies bounded injectable retry, and rejects cancelled/stale generations.
- missing/restricted/temporary accounts, network/service/rate-limit/quota/schema/configuration errors
  become presentation-safe status. Cloud or sync-metadata failure never destroys local progress.
- the real adapter uses an injected `CKContainer` private database, custom zone and silent zone
  subscription. Before each write it resolves against the latest server record, saves with
  change-tag protection, and returns the record CloudKit actually committed for local convergence.
  Server-record-changed races retry only within the bounded policy. No container/team identifier or
  entitlement was invented because none exists in the repository. Owner configuration and signed
  cross-device tests remain pending.
- deterministic fakes require no Apple ID or network. Favorites, Continue Watching UI, catalog/EPG/
  source/credential sync, monetization, analytics, and Phase 5 remain outside this slice.
- [ADR-0014](decisions/ADR-0014-cloudkit-watch-progress-sync.md) records the decision; [Cloud Sync
  Design](docs/CLOUD_SYNC.md) records the schema, behavior, and manual configuration gate.

## Validation evidence

- Phase 5C iPhone/iPad Source Management & Setup merged through PR #30 at
  `672a26c11d399054c85d18c51e1d16e3637407a8`; post-merge CI `35511142779` **SUCCESS**.
  Implementation and automated gates are complete. Its prior local validation on 2026-09-20 passed strict
  formatting, 195 shared tests in 19 suites with zero failures (`swift test`, exit 0), generic iOS
  Simulator build and Analyze (both exit 0), and `git diff --check`. Existing deterministic
  source-management tests cover M3U/Xtream create, validation, credential replacement, connection
  success/failure without catalog publication, edit, enable/disable, policy, manual refresh and
  compensated delete; no iOS UI-test target exists to extend. Physical iPhone/iPad touch, keyboard
  and Arabic RTL review remain pending. The 11 focused tvOS Source Management UI tests passed with
  zero failures on the Apple TV 4K (3rd generation), tvOS 26.5 simulator; the full tvOS UI suite was
  intentionally not rerun.

- Phase 5B Favorites UI merged through PR #29 at `f6b206f29db57d9249fccd69ca7e321825cab9d9`.
  Post-merge CI `35491439055` passed Core / Build / Analyze and tvOS UI Tests on the Xcode 27.0,
  tvOS 26.5 simulator baseline. Automated/simulator gates are complete; physical Apple TV
  focus/Arabic RTL and physical iPhone/iPad review remain pending.

- Phase 4B Favorites Sync local validation on 2026-09-13 passed the full shared `swift test` suite,
  including durable reopen, idempotent add/remove, tombstone conflict resolution, later re-favorite,
  offline/account-unavailable local operation, reconnect publication, cloud-failure preservation and
  cloud-model privacy checks. No real CloudKit account, entitlement or device validation was run.

- Phase 4A local final validation on 2026-09-13 passed 184 shared tests in 18 suites with zero
  failures (`swift test`, exit 0), including fetch/save races, committed-result persistence,
  server-record-changed retry bounds, stale-generation cancellation, completion, Start Over,
  duplicate delivery, account failure, backoff, token persistence, schema rejection, and redaction.
  Strict all-Swift formatting lint and `git diff --check` passed. Generic tvOS and iOS Simulator
  Debug builds and both static analyzers passed with exit 0. The full tvOS 26.5 Apple TV 4K (3rd
  generation) Simulator UI suite passed 41 tests in 1 XCTest suite with zero failures or skips
  (`xcodebuild test`, exit 0). Signed CloudKit and physical-device validation remain pending.
- Production Library/Search UI Composition completed through PR #24 at `1763189`; post-merge CI run
  `34598275534` succeeded. Its final local preflight on 2026-09-11 passed 146 shared
  tests in 14 suites with zero failures (`swift test`, exit 0) and the full 33-test tvOS UI suite
  with zero failures or skips on Apple TV 4K (3rd generation), tvOS 26.5 Simulator. Generic tvOS
  and iOS Simulator Debug builds and both static analyzers passed with exit 0. Strict formatting lint
  across every tracked and new Swift file, complete English/German/Arabic String Catalog validation,
  the security/scope audit and `git diff --check` passed. At 100k rows, measured median Phase 2F
  queries remained bounded (first page 0.47 ms, category page 1.14 ms, common search 0.49 ms,
  rare/no-result search 7.62/7.78 ms); the application composition mapped 384 rows and retained
  exactly 256 presentation items in 1.16 ms. Physical Apple TV and physical iPhone/iPad validation
  remain pending.
- Refresh Scheduling & Policy local final validation passed 132 shared tests in 13 suites with zero
  failures and 22 tvOS UI tests with zero failures on the Apple TV 4K (3rd generation), tvOS 26.5
  simulator. Generic tvOS/iOS Simulator builds, both static analyzers, strict all-Swift formatting
  lint and `git diff --check` passed. The post-merge CI run `34449661574` succeeded on merge commit
  `18ba431`, including Core / Build / Analyze and tvOS UI Tests. Physical Apple TV review remains
  pending.
- Phase 2F shared package validation: 98 tests in 10 suites passed, zero failed (`swift test`).
  This includes all prior Phase 2A/B/C/D/E tests plus production search/category semantics,
  Arabic and mixed-language matching, combined-filter isolation, pagination, cancellation,
  edge states, refresh staging invisibility and the 10k/50k/100k query benchmark cases.
- Phase 2F strict tracked-Swift formatting lint and `git diff --check` passed. Generic tvOS and iOS
  Simulator Debug builds and both static analyzers passed. The existing tvOS 26.5 Apple TV 4K
  (3rd generation) Simulator UI suite passed 11 tests with zero failures. No Phase 2F UI was added.
- Phase 2F merged through PR #17 as `b557347`. Post-merge CI run `34321067413` succeeded on that
  exact `main` commit: shared tests, tvOS/iOS Simulator builds, both static analyzers, tracked-Swift
  formatting lint and 11 tvOS Simulator UI tests all passed.
- Phase 2D shared package tests: 75 passed, 0 failed (`swift test`), including production persistence,
  rollback, query bounds, encrypted references and key storage, plus Xtream request construction,
  authentication, tolerant live/VOD/series decoding, normalized errors, security redaction,
  cancellation, deterministic identity and transactional import, plus all existing M3U,
  localization and synthetic-preview coverage.
- generic tvOS Simulator build: passed.
- generic iOS Simulator build: passed.
- tvOS and iOS Xcode static analysis: passed.
- tvOS 26.5 Apple TV 4K (3rd generation) UI tests: 11 passed, 0 failed, covering the default
  English flow, German launch, and targeted Arabic RTL Home/Detail/state/focus behavior.
- simulator accessibility audits passed for loaded Home and Detail; Detail/back focus
  restoration passed three consecutive cycles on the selected card.
- Phase 1 Home and Detail were visually inspected at 4K simulator resolution.
- Arabic Home and Detail were visually inspected at 4K simulator resolution: native RTL placed
  the first rail item on the right, semantic alignment and button order reflowed correctly, mixed
  Arabic/Latin names and numeric metadata rendered without visible clipping or overlap, and media
  artwork plus the play glyph remained unmirrored. The iPhone 17 Pro iOS 26.5 Simulator companion
  shell was smoke-inspected in Arabic RTL with the same content-direction behavior.
- the 10k-address-space stress launch passed UI automation with stable initial focus; cache
  bounds and cancellation passed deterministic shared tests.
- Phase 2B release-mode synthetic line-stream imports on a MacBook Air (M2, 8 GB), macOS 26.6.2,
  Swift 6.3.3 completed 10,000 entries in 0.083 s, 50,000 in 0.410 s and 100,000 in 0.839 s.
  The reproducible command was `swift test -c release --filter M3UImportPerformanceTests`.
  These are local parser/import-boundary measurements, not Apple TV or production-database claims.
  Peak memory was not measured; tests instead verify that sink batches never exceed 256 items.
- Phase 2C release-mode synthetic JSON decode, normalization and transactional test-sink imports on
  the same MacBook Air completed 10,000 entries in 0.078 s, 50,000 in 0.360 s and 100,000 in
  0.704 s. The reproducible command was
  `swift test -c release --filter XtreamProviderPerformanceTests`. These are local adapter/import
  boundary measurements without network or production-database work. Peak memory was not measured;
  tests verify a maximum sink batch of 256.
- Phase 2C Pull Request #11 hosted run `34211142740` passed the Core/Build/Analyze job and tvOS UI
  Tests job at implementation commit `048f9a0`; any follow-up commit remains subject to current-head
  CI before merge.
- Corrected Phase 2D release-mode disk-backed encrypted provider-model import: 10k **0.460 s**,
  50k **2.743 s**, 100k **7.661 s**; full replacements **0.496 / 3.025 / 8.677 s** respectively.
  M3U parser through production persistence: **0.601 / 3.269 / 7.796 s** imports and
  **0.489 / 4.233 / 7.778 s** replacements. At 100k, provider staging took **5.713 s** and the
  final live transaction **1.949 s**. Median-of-five 64-item pages were
  **0.436 / 0.464 / 0.485 ms**; 100k category page **2.850 ms**, ID lookup **0.478 ms**,
  source count **12.716 ms**. Repeat distributions and physical-device profiling remain required.
  Reproduce with
  `swift test -c release --filter CatalogPersistencePerformanceTests`.
  These are single local observations; peak memory and physical-device performance were not measured.
- Phase 2E release-mode full M3U refresh completed 10k/50k/100k in **0.591 / 3.221 / 7.567 s**;
  corresponding staging was **0.278 / 1.858 / 4.523 s** and final live transactions were
  **0.172 / 0.803 / 1.924 s**. Normalized provider refresh across live/VOD/series completed in
  **0.412 / 2.786 / 6.783 s**, with staging **0.226 / 1.738 / 4.333 s** and final transactions
  **0.145 / 0.869 / 2.091 s**. Synthetic response/generator preparation was outside the timer;
  M3U acquisition numbers represent in-memory handoff, not network throughput. Reproduce with
  `swift test -c release --filter CatalogRefreshPerformanceTests`. Peak memory was not measured.
- Phase 2F release-mode 64-item first pages completed at 10k/50k/100k in
  **0.346 / 0.347 / 0.373 ms**; middle pages in **0.416 / 0.737 / 2.351 ms**; 64 category
  summaries with counts in **0.229 / 0.840 / 3.502 ms**; exact item lookup in
  **0.019 / 0.020 / 0.023 ms**; common search in **0.347 / 0.366 / 0.368 ms**; rare search in
  **0.547 / 3.349 / 8.179 ms**; no-result search in **0.512 / 3.309 / 8.308 ms**; and source
  item count in **0.226 / 2.532 / 5.332 ms**. Reproduce with
  `swift test -c release --filter CatalogLibrarySearchPerformanceTests`. These are median-of-five
  warm local samples on the documented M2 system, not physical Apple TV or peak-memory claims.
- physical Apple TV: **PENDING** because the owner is currently away from the device. No
  physical build, install, launch, focus, accessibility or UX observation was performed.
- physical iPhone/iPad: **NOT RUN**.

No frame-rate, UI interaction-latency or peak-memory numbers are claimed. Local database query
latencies above are measured separately from UI behavior. Lazy containers,
bounded Home materialization and a bounded image cache are verified structurally and by
tests, while Instruments profiling and long-session focus review remain real-device work.

## Continuous integration

- A GitHub Actions CI foundation validates Pull Requests targeting `main`, pushes to `main`
  and manual dispatches on the repository-scoped self-hosted macOS runner with explicitly selected
  Xcode 27.0.
- Blocking checks cover shared Swift tests, independent tvOS and iOS Simulator builds,
  tvOS and iOS static analysis, and the tvOS UI suite on an Apple TV 4K (3rd generation)
  tvOS 26.5 Simulator.
- A repository-wide Swift formatting baseline covers all tracked Swift/package source and test
  files. Strict `swift format lint` is clean locally and CI enforces it
  for Pull Requests, pushes to `main` and manual dispatches.
- CI health is reported only from actual GitHub Actions results. Phase 2F merged through PR #17 at
  `b557347`; post-merge push run `34321067413` completed successfully on that exact `main` commit.
- Source Management & Validation Flows merged through PR #19 at `1c94236`; post-merge CI run
  `34386676789` completed successfully, including Core / Build / Analyze and tvOS UI Tests.
- Refresh Scheduling & Policy merged through PR #21 at `18ba431`; post-merge CI run `34449661574`
  completed successfully, including Core / Build / Analyze and tvOS UI Tests.
- Production Library/Search UI Composition merged through PR #24 at `1763189`; post-merge CI run
  `34598275534` completed successfully, including Core / Build / Analyze and tvOS UI Tests.
- CI uses no signing identity, repository secret, Apple ID, provider credential or external
  runtime dependency. It does not replace physical Apple TV validation.
- Phase 1 remains physically **PENDING**. Phase 2A/B/C/D/E/F and post-Phase-2 application
  integration are merged and complete. Phase 3 is implemented on its feature branch; its physical
  Apple TV exit gate and PR/self-hosted CI validation remain pending.

## Repository state

- The GitHub Actions CI foundation is defined in `.github/workflows/ci.yml`. Phase 2A was merged
  into `main` through PR #8 at `c53ff99`; the source/security foundation remains intact.
- Phase 2B was merged into `main` through PR #10 at `112a8a0`; the M3U parser/import foundation
  remains intact.
- Phase 2C merged through PR #11 at `6835219`; the provider adapter foundation remains intact.
- Phase 2D and its transaction-lifetime correction merged through PR #14 at `07a0ccc`.
- Phase 2E merged through PR #16 at `49d4f1c`.
- Phase 2F merged into `main` through PR #17 at `b557347`; successful post-merge CI run
  `34321067413` validated that exact commit.
- Post-Phase-2 Source Management & Validation Flows is complete, merged through PR #19 at
  `1c94236`; successful post-merge CI run `34386676789` validated the merge commit.
- Post-Phase-2 Refresh Scheduling & Policy is complete, merged through PR #21 at `18ba431`;
  successful post-merge CI run `34449661574` validated the merge commit.
- Post-Phase-2 Production Library/Search UI Composition is complete, merged through PR #24 at
  `1763189`; successful post-merge CI run `34598275534` validated it.
- Phase 3 Playback Foundation is merged on `main` at `55e55a0` through PR #25; successful post-merge
  CI run `34746573352` validated the merge commit. Its physical Apple TV exit gate remains pending.
- Phase 4A Watch Progress Sync is implemented on `main`; Phase 4B Favorites Sync is implemented on
  `main` through PR #27 at `252d620`, with post-merge CI `34783856312` successful. CloudKit
  entitlements/container setup and signed cross-device validation remain pending; Phase 4 is not
  complete.
- Phase 1 localization work merged through PR #9; physical LTR/Arabic RTL validation is pending.
- Phase 1 simulator implementation and hardening are merged into `main` through PRs #3
  and #4. The physical Apple TV exit gate remains pending.
- Phase 0 is recorded in coherent source-of-truth, shared-foundation and
  native-application commits.
- Git author identity is configured locally by the repository owner.
- `origin` is configured for the project GitHub repository.
- Phase 0 was merged to `main` through PR #2 at `521888e`.

## Confirmed product decisions

- AEVYNO is intended to become a sustainable commercial product after the core experience reaches
  launch quality.
- preferred commercial direction: useful Free tier + AEVYNO Pro, recurring plans and a possible
  lifetime purchase; final packaging/pricing remains a pre-launch decision.
- intrusive ads inside Home/library/playback are not part of the product strategy.
- the design target is to exceed IPTVX's perceived quality bar by a clear margin through original
  Apple-native design, stronger focus/navigation, responsiveness, Arabic RTL, accessibility and
  overall polish; copying remains prohibited.
- commercialization rules live in `docs/MONETIZATION.md`.
- first-class interface languages: English, German and Arabic.
- Arabic is mandatory native RTL with premium typography, layout, focus and accessibility quality.
- Apple-native localization and system typography are the default; localization rules live in
  `docs/LOCALIZATION.md`.
- Native Apple stack.
- tvOS primary.
- iOS/iPadOS companion.
- macOS later.
- Swift + SwiftUI.
- AVFoundation/AVKit first playback engine.
- CloudKit private database for lightweight user sync.
- secrets in Keychain, not CloudKit.
- local catalog cache; do not synchronize the full IPTV catalog to iCloud.
- no bundled content.
- original design; no IPTVX cloning.
- top priorities: design, speed, compatibility.

## Not yet decided

- final app/product name.
- final distribution minimum OS versions; Phase 0 provisionally targets iOS/tvOS 17.0
  under ADR-0004 and must be reassessed before TestFlight.
- whether a fallback playback engine is needed.
- EPG storage/index strategy after real provider fixtures are profiled.
- TestFlight/App Store distribution timing.
- final Free/Pro feature boundaries.
- final monthly/annual/lifetime pricing and whether lifetime remains economically sustainable.

## Next milestone

Run the Phase 1 Home/Detail/focus/accessibility/Reduce Motion checklist and the Phase 3 lawful-media
playback checklist on a physical Apple TV in base LTR and Arabic RTL. Include rapid directional
navigation, repeated player/Detail/back cycles, native transport/audio/subtitle controls, resume and
completion, failure/retry, representative HLS VOD/live/master fixtures, and a long Instruments
session. Resolve findings before marking either physical exit gate complete.

The post-Phase-2 source and library application-integration follow-up is complete. Phase 5A
production Continue Watching is implemented locally: a bounded, provider-neutral composition joins
durable WatchProgress to exact committed catalog records, hides completed/live/orphaned entries,
uses deterministic recency ordering, reuses the Phase 3 session for Resume, and renders separate
tvOS/iOS rails. Catalog commits invalidate the rail; player dismissal and foreground activation
refresh it without polling. Physical Apple TV focus/RTL and physical iPhone/iPad validation remain
pending. Phase 5A is **IMPLEMENTED on main through PR #28 at `d9b5e3e`**; post-merge CI
`34873787230` succeeded. Phase 5B Favorites UI is **IMPLEMENTED on main through PR #29 at
`f6b206f29db57d9249fccd69ca7e321825cab9d9`**; post-merge CI `35491439055` succeeded. Phase 5C
iPhone/iPad source management is **IMPLEMENTED on main through PR #30 at
`672a26c11d399054c85d18c51e1d16e3637407a8`**; post-merge CI `35511142779` succeeded. The
implementation/automated exit gate is complete; physical iPhone/iPad touch, keyboard, layout and
Arabic RTL review remains pending. For Phase 4,
configure the owner-approved CloudKit container/capabilities, wire signed lifecycle/push triggers,
then validate Apple TV-to-iPhone and iPhone-to-Apple TV resume/favorites plus offline reconnect.
Xtream playback URL and
episode-resolution contracts remain future work and must not be guessed.

## Active blockers

- No build/simulator infrastructure blocker remains.
- Phase 4A/4B signed runtime validation is blocked on owner selection of the Apple development team,
  CloudKit container, iCloud/CloudKit and remote-notification capabilities, and schema deployment.
- The Phase 1 exit gate is pending because the physical Apple TV is currently unavailable
  to the owner. Pair/connect the Apple TV and select it as the AEVYNOTV run destination when
  the owner returns.
- The Phase 3 exit gate is pending for the same reason; simulator automation cannot establish real
  first-frame, provider, Siri Remote, memory/thermal, or long-session playback behavior.

## Real-device validation status

Physical Apple TV: **PENDING — owner away from device; no Phase 1 UX or Phase 3 playback review run**.

Physical iPhone/iPad: **NOT RUN**.

Cross-device CloudKit Watch Progress: **NOT RUN — container/capabilities are not configured**.
