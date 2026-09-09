# Phase 2F Production Library Search Evidence

Date: 2026-09-09

## Scope and acceptance

Phase 2F adds production SQLite-backed search, category summaries and a provider-neutral Library
query service over committed local catalogs. It adds no SwiftUI screen, provider networking,
CloudKit catalog storage, playback URL resolution or Phase 3 playback code.

Acceptance: all results remain capped by `CatalogPage` at 256 rows; browsing and search support
optional source, origin, media-kind and category filters in combination; ordering is deterministic;
M3U groups and Xtream live/VOD/series categories remain source scoped; category summaries include
committed item counts; cancellation propagates; and invisible Phase 2E staging never appears before
the atomic publication commit.

## Query architecture

`CatalogQueryRepository` remains the sole persistence query boundary. Phase 2F extends it with
`searchItems` and `categorySummaries`; it does not duplicate the repository or introduce a search
library. `SQLiteCatalogStore` continues to own its read connection inside an actor. SQL performs
filtering, ordering, counting, pagination and cancellation-aware row traversal; no catalog-wide
Swift array or `MainActor` work is involved.

`CatalogLibraryService` is an immutable, `Sendable`, constructor-injected facade in `Library`. It
provides bounded browse, search, category, item lookup, item-count and source-partition-count
operations without exposing provider or SQLite details to future tvOS/iOS UI.

## Exact search semantics

- Input and stored titles use Foundation case- and diacritic-insensitive folding with the fixed
  `en_US_POSIX` locale, followed by canonical precomposition. Display titles are never changed.
- All Unicode whitespace separates search terms. Leading, trailing and repeated whitespace is
  ignored. Duplicate normalized terms are evaluated once.
- Every nonempty term must occur as a literal substring anywhere in the normalized title. Terms are
  unordered. Prefixes are therefore supported as a normal substring case.
- Punctuation, digits and emoji are retained and matched literally. Wildcard characters have no
  special meaning because terms are bound to SQLite `instr` parameters rather than interpolated SQL.
- Arabic is case-stable and remains Arabic. There is no Arabic transliteration, stemming, fuzzy
  matching, token-boundary matching, typo correction, language-aware ranking or relevance ranking.
- Empty/whitespace-only search delegates to normal filtered browsing.
- Search input is capped at 16,384 UTF-8 bytes before and after folding and at 32 whitespace-separated
  terms. NUL, oversized input and impossible origin/kind filter combinations fail with
  `CatalogStoreError.invalidInput`.

Results use binary `(search_title, id)` ordering. Duplicate titles therefore have a stable exact-ID
tie-breaker. The existing `search_title` indexes provide ordered traversal. Literal substring
predicates are not B-tree seekable, so rare and no-result searches can inspect all rows in the
selected filter scope. This is linear, not quadratic, and is measured below. Schema v3 remains
unchanged; no ADR or migration was required.

## Category and filter behavior

`CatalogFilter` now supports `origin` in addition to source, media kind and category ID. Combined
filters are joined with SQL `AND`. M3U may pair only with `unspecified`; Xtream may pair only with
live, VOD or series when both origin and kind are supplied. Invalid pairs fail instead of broadening
the query.

Category rows retain their exact source/origin/kind scope and deterministic `(search_title, id)`
ordering. `CatalogCategorySummary` adds an item count computed inside SQLite against the committed
items table. Category IDs are source-scoped global primary keys, and the existing composite foreign
key enforces that every counted item has the category's same source/origin/kind. Explicitly empty
catalogs/categories and deleted sources return empty bounded pages and zero counts.

## Pagination and publication isolation

`CatalogPage` still requires a limit of 1...256 and a nonnegative offset. Adjacent-page tests verify
stable ordering and no duplicate IDs in an unchanged 100k catalog. Offset paging remains a view of
the current committed catalog rather than a multi-request snapshot; callers must restart after a
refresh. Deep offsets retain their linear scan cost.

An integration test pauses a real `CatalogRefreshService` after catalog B has been written through
the production staging repository. During that pause, browse, search and category-summary queries
return only catalog A. After releasing the refresh and completing its atomic commit, subsequent
queries return only catalog B. No staged table participates in production query SQL.

## Release measurements

MacBook Air Mac14,2, Apple M2 (8 CPU cores), 8 GB RAM, macOS 26.6.2 (25G83), Xcode 26.6
(17F113), Apple Swift 6.3.3. Release-mode Swift Testing, system SQLite WAL, AES-256-GCM encrypted
references, 256-row staging/query bounds, 100 categories and synthetic data only. Each query is the
median of five warm samples after correctness checks. Reproduce with:

```sh
swift test -c release --filter CatalogLibrarySearchPerformanceTests
```

Durations are milliseconds. These are single local observations, not percentiles, Apple TV results
or service-level guarantees.

| Query | 10k | 50k | 100k |
| --- | ---: | ---: | ---: |
| First 64-item page | 0.346 | 0.347 | 0.373 |
| Middle 64-item page | 0.416 | 0.737 | 2.351 |
| 64 category-filtered items | 0.997 | 0.989 | 1.088 |
| 64 category summaries with counts | 0.229 | 0.840 | 3.502 |
| Exact item ID | 0.019 | 0.020 | 0.023 |
| Common search | 0.347 | 0.366 | 0.368 |
| Rare search | 0.547 | 3.349 | 8.179 |
| No-result search | 0.512 | 3.309 | 8.308 |
| Source item count | 0.226 | 2.532 | 5.332 |

Peak memory was not measured. Structural bounds are the 256-row result/staging cap, 32 search terms,
16 KiB search input and SQLite's existing per-connection cache request. SQLite, Foundation,
CryptoKit and result decoding memory still require Instruments measurement on physical Apple TV.

## Local validation

- `swift test`: 98 tests in 10 suites passed, zero failed, including all prior Phase 2A/B/C/D/E
  coverage and the new search/category/performance cases.
- `swift format lint --strict $(git ls-files '*.swift')`: passed.
- Generic tvOS Simulator Debug build: passed.
- Generic iOS Simulator Debug build: passed.
- tvOS static analysis: passed.
- iOS static analysis: passed.
- Existing tvOS 26.5 Apple TV 4K (3rd generation) Simulator UI suite: 11 passed, zero failed.
- `git diff --check`: passed.
- Physical Apple TV and physical iPhone/iPad: not run.

## Security and known limitations

Search SQL binds all provider-supplied text. Search indexes contain only normalized titles; they do
not contain credentials, media/artwork URLs, sealed references, provider response bodies or Keychain
material. Phase 2F adds no query logging, analytics, tracking, network request or CloudKit catalog
write. Opaque references remain encrypted under ADR-0008 and are decrypted only for returned bounded
items.

Physical Apple TV query latency, peak memory, long-session behavior, cache purge behavior and real
Keychain integration remain unverified. Search has no relevance ordering or full-text linguistic
features. Category counts inspect matching committed item index entries and should be profiled with
real provider distributions. The final Search/browse UI, debounce policy, source-management flows
and refresh scheduling are assigned to the planned, unstarted post-Phase 2 source and library
application-integration follow-up in [the roadmap](ROADMAP.md); they are not Phase 2 exit
requirements.
