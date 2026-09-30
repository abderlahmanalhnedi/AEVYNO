# Phase 6A — XMLTV / EPG Foundation

Phase 6A is data, ingestion, and bounded-query work only. It contains no TV guide, playback, source-settings, scheduling, or provider-specific Xtream EPG behavior.

`XMLTVParser` is Foundation SAX parsing over an `InputStream`; it processes one programme at a time, caps retained text, and reports only bounded category warnings. `XMLTVEPGImportService` writes normalized non-secret programme rows to a temporary local spool during parsing, then reads it in 256-row batches into staging. It accepts standard `programme` fields and explicit-offset XMLTV times. Timezone-free and invalid intervals are skipped, while malformed documents are fatal; every terminal path removes the spool and staging rows.

## Phase 6D compatibility policy

The synthetic corpus covers absent/empty optional fields, entities/CDATA, Arabic Unicode, harmless
attribute/whitespace variation, repeated categories, unknown safe elements, duplicates, overlaps,
unmapped channels, and retention exclusion. Invalid programmes are skipped; structural XML errors fail
the document. Overlong text is skipped rather than silently truncated into valid metadata. Failed,
cancelled, and successful imports remove their temporary spool and staging rows; publication preserves
the prior committed source snapshot until its final atomic replacement.

The acquisition boundary deliberately returns bounded `Data` (64 MiB maximum) before parsing. Phase 6D
does not introduce network-to-spool streaming. The deterministic smoke test covers 100/1,000/10,000
channels (two programmes each); it is not a device memory claim.

Cancellation is checked before parsing, for each spool write, before each bounded staging batch, and
before atomic publication. A cancellation before publication discards staging and the spool, leaving
the prior source snapshot visible. Once SQLite has entered the short atomic publication transaction,
the operation is allowed to complete or roll back as SQLite requires; it is not interrupted mid-commit.

On the local macOS Swift runtime, the deterministic synthetic measurement recorded these independent
phase times (two programmes/channel): 100 channels: parse 0.1245 s, staging 0.0012 s, publication
0.0009 s, Now/Next 0.0003 s, Guide 0.0004 s, cache 300,576 bytes; 1,000: 1.1300 s, 0.0110 s, 0.0046 s,
0.0003 s, 0.0004 s, 2,088,656 bytes; 10,000: 10.9792 s, 0.1317 s, 0.0780 s, 0.0003 s, 0.0005 s,
24,435,016 bytes. Normalized-spool and end-to-end import durations are intentionally not labelled as
independent measurements because that boundary is not instrumented.

A warmed `/usr/bin/time -l` micro-measurement allocated a filled 64 MiB `Data` and then consumed it
through `InputStream` with a 64 KiB buffer: base peak RSS was about 142.1 MB, `Data` about 209.3 MB,
and `Data` plus `InputStream` about 209.3 MB. This is local runtime evidence, not a device claim, but
it found no material additional copy attributable to `Data -> InputStream`; a streaming transport
redesign is not justified by Phase 6D evidence.

`SQLiteEPGStore` is a source-scoped SQLite v1 cache using invisible staging and WAL. Foreign keys are enabled on each connection and staging rows are also explicitly removed on successful commit, discard, error, cancellation, and reopen. Readers see EPG A during parsing/staging and see EPG B only after a short atomic commit. Successful publication keeps 24 hours of recent history and 14 days of future starts. The cache is excluded from backup and is rebuildable; it is never synced to CloudKit.

## Phase 6B acquisition and Now/Next

Phase 6B adds an optional XMLTV endpoint only to M3U source configuration. It has the same sanitized
endpoint constraints as the M3U playlist (no user information, query, password, token URL, or
fragment) and is not available for Xtream sources. `SourceRefreshService` is shared by manual and
scheduled refresh: it commits the catalog first, then acquires and imports XMLTV independently. A
failed or unavailable EPG endpoint leaves the catalog usable. There is no URL guessing, Xtream EPG,
CloudKit EPG, or full guide.

The existing `ProductionEPGService` remains the sole SwiftUI-facing boundary. tvOS and iOS detail
views request Now/Next using a catalog item identifier and receive presentation values only; neither
view accesses SQLite, provider adapters, credentials, or scheduling.

M3U `tvg-id` is copied to an encrypted `CatalogItem.epgChannelID`; it is only an exact XMLTV channel anchor. Missing IDs do not fall back to display names. A caller asks `ProductionEPGService` for a catalog ID and absolute time; it performs the catalog mapping and returns safe `now`/`next` values. SwiftUI receives no SQLite, Keychain, provider, URL, credential, or scheduler access.

Performance fixtures are intentionally bounded at 256 write rows. The deterministic macOS debug smoke
measurement on 2026-09-20 staged, published, and queried two programmes per channel: 100 channels / 200
programmes in 0.0031 s, 1,000 / 2,000 in 0.0214 s, and 10,000 / 20,000 in 0.2410 s. These are local
debug measurements, not a device performance claim. Physical-device cache/memory observation and a
representative provider-derived multi-day corpus remain required before guide UI work.

## Phase 6C bounded Guide query

Phase 6C reuses `ProductionEPGService` for a source-scoped Guide presentation. It reads one exact
catalog candidate page (40 rows) and one set-based indexed programme query for an eight-hour interval
(two hours before through six hours after the opening instant). It does not materialize full EPG data,
infer identities, or change Now/Next semantics. See [EPG Guide UI](EPG_GUIDE_UI.md).

## Phase 6E EPG freshness and safe status

`epg.sqlite` schema v2 adds one local-only `epg_health` row per source. It stores only the latest
attempt time, latest successful publication time, committed programme count, source-wide minimum
start and maximum end, latest result, and a provider-neutral failure category. It never stores an
endpoint, credentials, provider identifiers, raw XML, parser diagnostics, or a refresh history.

Configuration remains the source registry's truth: only an M3U source with a supported XMLTV
configuration is configured. A configured source without a metadata row has never completed an
import. Publication writes the programme replacement and success facts in the same SQLite
transaction. A zero-programme publication is a successful, factual no-data publication.

Coverage is source-wide evidence only: no data when the committed count is zero, future-only when
the earliest retained programme starts after the viewing instant, current coverage when the bounds
span it, and expired when the latest retained end is not later than it. It never claims that every
channel has a current schedule.

Failed acquisition/import writes only the latest attempt, failure result, and one of
`networkUnavailable`, `timeout`, `responseTooLarge`, `invalidGuideData`, `persistenceFailure`, or
`unknown`; it retains last-success facts and the last-known-good EPG snapshot. Lifecycle
cancellation records no user-visible failure and retains the prior visible status. Version-one
caches migrate in place by adding this table without modifying committed programmes.
