# ADR-0006 — M3U Import Identity and Streaming Boundary

Status: Accepted
Date: 2026-09-08

## Context

M3U playlists can contain 100,000 or more entries, incomplete metadata, repeated entries and
credential-bearing media URLs. Refreshes need identities that remain stable without copying a full
catalog into memory or embedding provider data in an identifier. The future persistence layer also
needs a transaction boundary so cancellation or a fatal parse failure cannot replace the last usable
catalog with a partial import.

## Decision

- `IPTVCore` parses an asynchronous line sequence and emits one normalized parser entry at a time.
  The parser keeps one pending `EXTINF` record and a fixed set of warning counters.
- `Library` consumes parser entries in batches of 256 by default through an asynchronous import sink.
  A sink must stage writes between `beginImport` and `commitImport`, and discard them on
  `rollbackImport`.
- Imported item identity is a SHA-256 digest scoped by `SourceConfiguration.ID`. The preferred stable
  anchor is a non-empty `tvg-id`; the exact media URL string is the fallback when `tvg-id` is absent.
- Repeated anchors are preserved. Their zero-based occurrence within the source produces a distinct,
  deterministic identity, and the import report records the duplicate count.
- Media and artwork URLs are accepted only when they are absolute HTTP or HTTPS URLs. The parser does
  not fetch them, rewrite their paths or queries, extract credentials, or support local/file URLs.
- Raw unknown attributes are ignored rather than retained. This keeps the normalized model minimal
  and avoids persisting unnecessary provider data.
- Diagnostics expose typed error/warning categories and aggregate counts. They never contain raw
  playlist lines or URLs; the imported model's default description redacts URL values.

## Consequences

Positive:

- The parser and import sink do not need to retain the full catalog.
- Same-source refreshes keep stable IDs when `tvg-id` remains stable, even if signed media URLs rotate.
- A playlist without `tvg-id` preserves exact provider URL semantics for identity rather than applying
  potentially destructive normalization.
- Duplicate behavior, cancellation and transaction expectations are explicit and testable before a
  production persistence implementation is selected.

Tradeoffs:

- URL-fallback identity changes when the provider changes the URL, because there is no stronger stable
  identifier.
- Adding, removing or reordering exact duplicates can change occurrence identities within that one
  duplicate set.
- The importer retains one hashed counter per distinct identity anchor during an import. It does not
  retain the corresponding media entries, raw URLs or attributes.
- SHA-256 collisions are theoretically possible but not a practical catalog identity risk.

This decision does not select a production database, implement networking, or define playback models.
