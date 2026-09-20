# Phase 6A — XMLTV / EPG Foundation

Phase 6A is data, ingestion, and bounded-query work only. It contains no TV guide, playback, source-settings, scheduling, or provider-specific Xtream EPG behavior.

`XMLTVParser` is Foundation SAX parsing over an `InputStream`; it processes one programme at a time, caps retained text, and reports only bounded category warnings. `XMLTVEPGImportService` writes normalized non-secret programme rows to a temporary local spool during parsing, then reads it in 256-row batches into staging. It accepts standard `programme` fields and explicit-offset XMLTV times. Timezone-free and invalid intervals are skipped, while malformed documents are fatal; every terminal path removes the spool and staging rows.

`SQLiteEPGStore` is a source-scoped SQLite v1 cache using invisible staging and WAL. Foreign keys are enabled on each connection and staging rows are also explicitly removed on successful commit, discard, error, cancellation, and reopen. Readers see EPG A during parsing/staging and see EPG B only after a short atomic commit. Successful publication keeps 24 hours of recent history and 14 days of future starts. The cache is excluded from backup and is rebuildable; it is never synced to CloudKit.

M3U `tvg-id` is copied to an encrypted `CatalogItem.epgChannelID`; it is only an exact XMLTV channel anchor. Missing IDs do not fall back to display names. A caller asks `ProductionEPGService` for a catalog ID and absolute time; it performs the catalog mapping and returns safe `now`/`next` values. SwiftUI receives no SQLite, Keychain, provider, URL, credential, or scheduler access.

Performance fixtures are intentionally bounded at 256 write rows. The deterministic macOS debug smoke
measurement on 2026-09-20 staged, published, and queried two programmes per channel: 100 channels / 200
programmes in 0.0031 s, 1,000 / 2,000 in 0.0214 s, and 10,000 / 20,000 in 0.2410 s. These are local
debug measurements, not a device performance claim. Physical-device cache/memory observation and a
representative provider-derived multi-day corpus remain required before guide UI work.
