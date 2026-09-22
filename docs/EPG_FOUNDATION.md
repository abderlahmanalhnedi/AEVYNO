# Phase 6A — XMLTV / EPG Foundation

Phase 6A is data, ingestion, and bounded-query work only. It contains no TV guide, playback, source-settings, scheduling, or provider-specific Xtream EPG behavior.

`XMLTVParser` is Foundation SAX parsing over an `InputStream`; it processes one programme at a time, caps retained text, and reports only bounded category warnings. `XMLTVEPGImportService` writes normalized non-secret programme rows to a temporary local spool during parsing, then reads it in 256-row batches into staging. It accepts standard `programme` fields and explicit-offset XMLTV times. Timezone-free and invalid intervals are skipped, while malformed documents are fatal; every terminal path removes the spool and staging rows.

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
