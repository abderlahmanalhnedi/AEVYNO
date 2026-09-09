# Project Status

Last updated: 2026-09-09

## Current phase

**Phase 1 physical validation open; Phase 2 complete; Phase 3 not started**

Phase 0 is complete in simulator. Its physical Apple TV validation remains pending because
the owner is currently away from the device; the Phase 0 roadmap exit allows this explicit
deferral. The existing Phase 1 shell has completed simulator hardening. Its Apple-native localization
foundation for English, German and Arabic now covers the current tvOS and iOS surfaces, and the
Arabic RTL Home, Detail and state flows have been simulator-validated. Phase 1 remains incomplete
until the real Apple TV UX review passes in both LTR and Arabic RTL.
Phase 2 is complete on `main` at `b557347` through merged PR #17. Its approved roadmap deliverables
and exit gate are satisfied by the documented 50k/100k import, refresh and query benchmarks, atomic
last-known-good catalog behavior, and successful post-merge CI run `34321067413` on that exact
commit. Phase 3 playback work has not started.

## Verified development environment

- selected developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Xcode 26.6 (build 17F113).
- Swift 6.3.3.
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
  playback work is included. The UI and scheduling items are assigned to the planned, unstarted
  post-Phase 2 source and library application-integration follow-up in `docs/ROADMAP.md`; they are not
  Phase 2 exit requirements.

## Validation evidence

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
  Xcode 26.6.
- Blocking checks cover shared Swift tests, independent tvOS and iOS Simulator builds,
  tvOS and iOS static analysis, and the tvOS UI suite on an Apple TV 4K (3rd generation)
  tvOS 26.5 Simulator.
- A repository-wide Swift formatting baseline covers all tracked Swift/package source and test
  files. Strict `swift format lint` is clean locally and CI enforces it
  for Pull Requests, pushes to `main` and manual dispatches.
- CI health is reported only from actual GitHub Actions results. Phase 2F merged through PR #17 at
  `b557347`; post-merge push run `34321067413` completed successfully on that exact `main` commit.
- CI uses no signing identity, repository secret, Apple ID, provider credential or external
  runtime dependency. It does not replace physical Apple TV validation.
- Phase 1 remains physically **PENDING**. Phase 2A/B/C/D/E/F are merged and the approved Phase 2
  roadmap gate is complete. Phase 3 has not started.

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

Run the Phase 1 Home, Detail, focus-restoration, accessibility and Reduce Motion checklist
on a physical Apple TV in both the base LTR experience and Arabic RTL. Include rapid directional
navigation, repeated open/back cycles and
a long stress-mode browsing session with Instruments. Resolve findings before marking Phase 1
complete.

The planned post-Phase 2 source and library application-integration follow-up owns source-management
UI/flows, refresh scheduling and final app query/UI composition. These items are not part of the
approved Phase 2 deliverables or exit gate, and the follow-up has not started. M3U file acquisition
remains outside the completed remote-acquisition slice. Do not begin Phase 3 playback implementation
before its approved phase gate.

## Active blockers

- No infrastructure/simulator blocker remains.
- The Phase 1 exit gate is pending because the physical Apple TV is currently unavailable
  to the owner. Pair/connect the Apple TV and select it as the AEVYNOTV run destination when
  the owner returns.

## Real-device validation status

Physical Apple TV: **PENDING — owner away from device; no Phase 1 real-device review run**.

Physical iPhone/iPad: **NOT RUN**.
