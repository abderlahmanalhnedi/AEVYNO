# Phase 2D Persistence Evidence

Date: 2026-09-08

## Scope and acceptance

Production local storage, existing M3U/Xtream sink integration, categories, deterministic bounded
query APIs, source deletion, rollback and benchmark evidence. No source UI, EPG, playback, full
search or CloudKit catalog work. See [ADR-0008](../decisions/ADR-0008-local-catalog-persistence.md)
for schema, stack evaluation, privacy review and tradeoffs.

Acceptance: acquisition and network waits hold no SQLite writer transaction; commit/reopen preserves
IDs and references; catalog A remains queryable until B commits;
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
unique temporary directory, 256-row maximum batches, 100 categories, 64-item query pages and WAL.
Disposable staging commits use NORMAL synchronous mode; the final live replacement uses FULL.
Timings use ContinuousClock and include actor hops, normalization,
identity generation, encryption, database work and result decoding as applicable.

The unified provider-model benchmark creates only the current batch; no network/JSON decode is
included. The separate M3U benchmark includes the existing streaming parser, identity bookkeeping,
production sink, group writes and URL encryption. Both measure complete staging and final
replacement. Initial queries follow import and are cache-warm. Reopen+page includes connection
setup after explicit close; the OS cache is not flushed, so it is not a physical cold-start result.
Query numbers are medians of five warm samples after correctness checks. They are not percentile or
service-level guarantees.

Peak process memory was not measured. Each SQLite connection requests a 4 MiB cache, query results
are limited to 256, SQL imports accept at most 256 rows per batch, and encrypted URL payloads and
text lengths have explicit validation limits. These are structural bounds, not measured memory
numbers. SQLite/WAL, Foundation, CryptoKit and importer memory must still be profiled on Apple TV.

## Release measurements

Two isolated local release runs after simulator testing finished: one for the provider-model/import
and query benchmark, and one for M3U. Durations below are seconds for imports and milliseconds for
queries. No physical-device or peak-memory claim is made.

| Rows | Provider-model import (s) | Provider replacement (s) | M3U import (s) | M3U replacement (s) |
| ---: | ---: | ---: | ---: | ---: |
| 10,000 | 0.460 | 0.496 | 0.601 | 0.489 |
| 50,000 | 2.743 | 3.025 | 3.269 | 4.233 |
| 100,000 | 7.661 | 8.677 | 7.796 | 7.778 |

| Query (ms) | 10k | 50k | 100k |
| --- | ---: | ---: | ---: |
| 64-item page | 0.436 | 0.464 | 0.485 |
| Source page | 0.445 | 0.448 | 0.673 |
| Media-kind page | 0.439 | 0.424 | 0.585 |
| Category item page | 0.448 | 0.416 | 2.850 |
| Exact item ID | 0.020 | 0.023 | 0.478 |
| Source item count | 0.254 | 2.894 | 12.716 |
| 64-category page | 0.058 | 0.063 | 0.061 |
| Deep offset page (last 32 rows) | 0.430 | 2.278 | 7.212 |
| Reopen + first page | 1.537 | 1.764 | 3.121 |

The normalized-provider import grows from 0.460 s at 10k to 7.661 s at 100k. At 100k, its staging
phase was 5.713 s and its final live transaction was 1.949 s; the replacement split was 5.954 s and
2.722 s. A required `(staging_id, sequence)` index keeps the bounded final-copy traversal from
repeatedly scanning earlier staging rows. This sample does not establish an asymptotic guarantee.

The final schema adds a second encrypted write for staging, so these numbers supersede the faster
pre-correction Phase 2D values. Counts and deep offsets show increasing scan costs. Result arrays
remain bounded and no catalog is materialized in memory. Physical-device and broader distribution
profiling remain required.

## Local validation

- 75 shared tests passed, including all existing M3U/Xtream tests and the production persistence cases.
- The explicit release benchmark commands passed both parameterized tests at all three sizes.
- Strict tracked-Swift formatting lint and `git diff --check` passed.
- Generic tvOS Simulator and iOS Simulator Debug builds and analyzers passed.
- Existing tvOS 26.5 Apple TV 4K (3rd generation) UI suite: 11 tests passed, zero failures,
  including English/German/Arabic flows and focus restoration.
- No physical Apple TV/iPhone/iPad test was performed. Real Keychain access uses the injected
  system-client test boundary, not a signed device entitlement test.

## Failure and security evidence

Automated production-database coverage includes:

- a suspended provider acquisition after a staged batch while an independent connection acquires
  `BEGIN IMMEDIATE`, proving the live SQLite writer transaction is not held across the network wait;
- committed reader isolation while staged replacement batches are in flight, then atomic replacement;
- injected SQLite trigger write failure after an earlier batch; deferred foreign-key commit failure;
- cancellation before commit, cancellation through the provider service after a written batch,
  invalid UTF-8 after a persisted M3U batch, and transport error after a provider batch;
- empty successful replacement, category removal/replacement consistency, wrong-scope ID collision,
  same-scope duplicate last-write-wins, deterministic sort ties and preserved Arabic display text;
- separate source and kind replacement/deletion, token ownership, concurrent begin rejection;
- close/reopen durability, abandoning an unfinished refresh, transactional v1-to-v2 migration,
  unknown schema and corrupt file refusal;
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

Phase 2E follow-up extends the same staging architecture to concurrent different-source sessions and
one multi-partition Xtream commit, and adds schema-v3 refresh metadata. The live transaction boundary
remains unchanged. See [ADR-0009](../decisions/ADR-0009-durable-source-refresh.md) and
[Phase 2E evidence](PHASE_2E_REFRESH.md).

- Physical Apple TV and physical iPhone/iPad storage/Keychain/performance validation: not run.
- Phase 1 physical LTR and Arabic RTL UX review: pending; simulator success does not complete it.
- Caches can be purged on tvOS; future source flows must handle missing/expired caches and key loss.
- One source owns one logical staging session; Phase 2E permits separate sessions for different
  sources and rejects overlapping work for the same source. No session holds a SQLite writer
  transaction between staging batches or during network waits. The actor
  serializes SQL calls, so the final copy/delete/commit can delay queued queries even though their
  reader snapshot remains unchanged. Profile this during real-device refresh.
- Staging temporarily requires additional encrypted local disk space and is cleaned on rollback,
  close and next startup after a process crash.
- A missing category reference rejects the whole refreshed partition; no silent orphan fallback.
- SQLite retains reusable free pages; refresh can temporarily grow WAL/disk use. No secure erasure or
  database compaction guarantee. Metadata such as titles stays plaintext; references are encrypted.
- Offset paging is stable only within an unchanged catalog and scans skipped index entries.
- M3U media kind remains unspecified until a future evidence-backed classification policy.
- Phase 2F subsequently delivered production search. Source-management UI/flows, refresh scheduling
  and final app query/UI composition are assigned to the planned, unstarted post-Phase 2 source and
  library application-integration follow-up in [the roadmap](ROADMAP.md); they are not Phase 2 exit
  requirements. No Phase 3 playback work has started.
