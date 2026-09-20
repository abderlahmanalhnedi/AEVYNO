# ADR-0015 — XMLTV / EPG Foundation

Status: Accepted
Date: 2026-09-20

## Decision

Phase 6A adds provider-neutral, source-scoped XMLTV programme data without a guide UI. `EPGChannelIdentity` is an opaque, validated XMLTV channel `id`; an `EPGProgramme` is identified deterministically by channel, absolute start/end instants, and normalized title. It never uses a human title alone.

M3U `tvg-id` is preserved as the optional `CatalogItem.epgChannelID` mapping anchor inside the existing encrypted catalog reference payload. It does not change `CatalogItem.id`, favorites, watch progress, or M3U's `.unspecified` kind. Missing `tvg-id` means no mapping: there is no title/fuzzy fallback. `tvg-name` remains non-authoritative import metadata.

XMLTV is parsed with Foundation's SAX-style `XMLParser`; only one programme's bounded fields are accumulated. The Library import service spools normalized, non-secret programme rows to a temporary local file while parsing, then reads that spool in 256-row batches into actor-isolated staging. This avoids materializing a guide or holding a SQLite transaction during parsing. Required programme fields are channel, start, stop, and title. Invalid programme entries are skipped with a bounded, non-sensitive warning summary; malformed document structure is fatal. Timestamps require an explicit `Z` or numeric offset, support minute/second precision, and are normalized to absolute `Date` values without using the device timezone.

EPG uses a separate, backup-excluded rebuildable SQLite cache (`epg.sqlite`) with the same actor-isolated native SQLite infrastructure as the catalog. This avoids catalog schema migration and catalog writer contention while retaining WAL readers, short staging transactions, and atomic publication. Schema version is 1; future changes require an explicit migration or reviewed rebuild strategy.

Acquisition is injected. No XMLTV source URL/UI is added and no Xtream URL/API is guessed. A future adapter must supply an explicit reviewed channel-ID and endpoint contract.

## Publication, retention, and queries

Imports stage at most 256 rows per transaction. The writer enables foreign keys and explicitly deletes staging rows/session records on success, discard, error, cancellation, and reopen. A successful non-empty replacement atomically deletes/replaces only that source's EPG rows; readers keep the prior snapshot until commit. Parser, transport, cancellation, or write failure never replaces prior data. Publication retains programmes ending no earlier than 24 hours before the commit clock and starting no later than 14 days after it—enough for Now/Next and a near-term guide while bounding cache growth.

`nowNext` is bounded by source/channel/time and uses `[start,end)` semantics. For corrupt overlaps, Now is the active row with the latest start then programme-ID tie-break; Next is the earliest programme starting at or after Now's end (or now when no Now), then ID tie-break. Gaps and unmapped catalog items return nil fields rather than guesses.

No XML fragments, response bodies, credentials, tokens, credential-bearing URLs, or source secrets are persisted/logged. Programme metadata is provider-authored local cache metadata only; EPG never enters CloudKit.
