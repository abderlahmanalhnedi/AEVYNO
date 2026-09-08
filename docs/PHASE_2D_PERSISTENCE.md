# Phase 2D Persistence Evidence

Date: 2026-09-08

## Scope and acceptance

Production local storage, existing M3U/Xtream sink integration, categories, deterministic bounded
query APIs, source deletion, rollback and benchmark evidence. No source UI, EPG, playback, full
search or CloudKit catalog work. See [ADR-0008](../decisions/ADR-0008-local-catalog-persistence.md)
for schema, stack evaluation, privacy review and tradeoffs.

Acceptance: commit/reopen preserves IDs and references; catalog A remains queryable until B commits;
parser, transport, cancellation and database-write/commit failures preserve A; categories stay
consistent; replacing/deleting one source leaves other sources/kinds intact; all query arrays are
explicitly limited; 10k/50k/100k tests exercise disk-backed storage. Phase 1 UI regression checks
must remain green. Physical Apple TV performance is a separate pending gate.

## Reproduce

```sh
swift test
swift test -c release --filter CatalogPersistencePerformanceTests
swift format lint --strict $(git ls-files '*.swift')
xcodebuild -workspace AEVYNO.xcworkspace -scheme AEVYNOTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' -derivedDataPath /tmp/aevyno-phase2d-tv \
  CODE_SIGNING_ALLOWED=NO build analyze
xcodebuild -workspace AEVYNO.xcworkspace -scheme AEVYNOiOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/aevyno-phase2d-ios \
  CODE_SIGNING_ALLOWED=NO build analyze
xcodebuild -workspace AEVYNO.xcworkspace -scheme AEVYNOTV -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.5' \
  -derivedDataPath /tmp/aevyno-phase2d-tv CODE_SIGNING_ALLOWED=NO test
```

## Measurement method

MacBook Air Mac14,2, Apple M2 (8 CPU cores), 8 GB RAM, macOS 26.6.2 (25G83), Xcode 26.6
(17F113), Apple Swift 6.3.3. Synthetic data only. Release-mode Swift Testing, disk databases in a
unique temporary directory, 256-row maximum batches, 100 categories, 64-item query pages, WAL and
FULL synchronous commits. Timings use ContinuousClock and include actor hops, normalization,
identity generation, encryption, database work and result decoding as applicable.

The unified provider-model benchmark creates only the current batch; no network/JSON decode is
included. The separate M3U benchmark includes the existing streaming parser, identity bookkeeping,
production sink, group writes and URL encryption. Both measure complete replacement from begin
through commit. Initial queries follow import and are cache-warm. Reopen+page includes connection
setup after explicit close; the OS cache is not flushed, so it is not a physical cold-start result.
Query numbers are individual observations, not percentiles or service-level guarantees.

Peak process memory was not measured. Each SQLite connection requests a 4 MiB cache, query results
are limited to 256, SQL imports accept at most 256 rows per batch, and encrypted URL payloads and
text lengths have explicit validation limits. These are structural bounds, not measured memory
numbers. SQLite/WAL, Foundation, CryptoKit and importer memory must still be profiled on Apple TV.

## Release measurements

Single isolated local run after simulator testing finished. Durations below are seconds for imports
and milliseconds for queries. No physical-device or peak-memory claim is made.

| Rows | Provider-model import (s) | Provider replacement (s) | M3U import (s) | M3U replacement (s) |
| ---: | ---: | ---: | ---: | ---: |
| 10,000 | 0.244 | 0.269 | 0.301 | 0.385 |
| 50,000 | 1.354 | 2.749 | 1.563 | 3.548 |
| 100,000 | 2.904 | 5.054 | 5.186 | 6.539 |

| Query (ms) | 10k | 50k | 100k |
| --- | ---: | ---: | ---: |
| 64-item page | 0.589 | 0.629 | 0.565 |
| Source page | 0.397 | 0.505 | 0.432 |
| Media-kind page | 0.378 | 0.484 | 0.410 |
| Category item page | 0.519 | 0.675 | 0.594 |
| Exact item ID | 0.042 | 0.058 | 0.057 |
| Source item count | 0.670 | 3.979 | 7.901 |
| 64-category page | 0.074 | 0.098 | 0.096 |
| Deep offset page (last 32 rows) | 0.658 | 2.666 | 4.345 |
| Reopen + first page | 1.333 | 1.313 | 1.419 |

The normalized-provider import grows from 0.244 s at 10k to 2.904 s at 100k. This sample provides
no evidence of quadratic import behavior; it does not establish an asymptotic guarantee. The M3U
100k case and replacement work cost more, and disk/cache effects need device profiling. Counts and
deep offsets show increasing scan costs. First-page, category and ID queries stay bounded without
catalog materialization. The measured candidate meets this foundation's local acceptance criteria;
there was no need to add a third-party store or to benchmark additional stacks before review.

## Local validation

- 73 shared tests passed, including all existing M3U/Xtream tests and the production persistence cases.
- The explicit release benchmark command passed both parameterized tests at all three sizes.
- Strict tracked-Swift formatting lint and `git diff --check` passed.
- Generic tvOS Simulator and iOS Simulator Debug builds and analyzers passed.
- Existing tvOS 26.5 Apple TV 4K (3rd generation) UI suite: 11 tests passed, zero failures,
  including English/German/Arabic flows and focus restoration.
- No physical Apple TV/iPhone/iPad test was performed. Real Keychain access uses the injected
  system-client test boundary, not a signed device entitlement test.

## Failure and security evidence

Automated production-database coverage includes:

- committed reader isolation while replacement batches are in flight, then atomic replacement;
- injected SQLite trigger write failure after an earlier batch; deferred foreign-key commit failure;
- cancellation before commit, cancellation through the provider service after a written batch,
  invalid UTF-8 after a persisted M3U batch, and transport error after a provider batch;
- empty successful replacement, category removal/replacement consistency, wrong-scope ID collision,
  same-scope duplicate last-write-wins, deterministic sort ties and preserved Arabic display text;
- separate source and kind replacement/deletion, token ownership, concurrent begin rejection;
- close/reopen durability, abandoning an unfinished refresh, unknown schema and corrupt file refusal;
- exact opaque URL round-trip after reopen, wrong-key authentication failure, and absence of synthetic
  URL secret markers in database bytes; all stored references are encrypted before entering SQLite;
- stable Keychain key retrieval through the injected system boundary, device-local accessibility,
  separation from source credentials, and safe corrupt/unavailable key handling;
- SQL query-plan evidence uses the source+kind index without temporary sorting, large catalogs return
  only requested page sizes, invalid limits/offsets fail and cancelled queries remain CancellationError.

There is no provider credential, raw response, account snapshot, diagnostic or CloudKit field in
this schema. No real provider request/data was used. SQLite errors never include SQL text, values
or raw engine diagnostics. The sole storage log reports rollback failure without provider content.

## Known limitations and follow-up

- Physical Apple TV and physical iPhone/iPad storage/Keychain/performance validation: not run.
- Phase 1 physical LTR and Arabic RTL UX review: pending; simulator success does not complete it.
- Caches can be purged on tvOS; future source flows must handle missing/expired caches and key loss.
- One active import owns the writer, including network waits. Concurrent refreshes must retry `busy`.
  The actor serializes SQL calls: a long deletion/begin/commit statement can delay queued queries,
  even though their reader snapshot remains unchanged. Profile this during real-device refresh.
- A missing category reference rejects the whole refreshed partition; no silent orphan fallback.
- SQLite retains reusable free pages; refresh can temporarily grow WAL/disk use. No secure erasure or
  database compaction guarantee. Metadata such as titles stays plaintext; references are encrypted.
- Offset paging is stable only within an unchanged catalog and scans skipped index entries.
- M3U media kind remains unspecified until a future evidence-backed classification policy.
- Full production search, source validation/management, acquisition and refresh scheduling remain
  Phase 2 work. No Phase 3 playback work has started.
