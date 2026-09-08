# ADR-0009 — Durable Source Refresh Orchestration

Status: Accepted
Date: 2026-09-08

## Context

Phase 2A–2D provide source configuration, device-local credentials, M3U and Xtream-compatible
normalization, and query-invisible SQLite staging. A production refresh must compose those pieces
without exposing protocol details to UI, holding a live catalog transaction across network work, or
allowing a failed multi-endpoint Xtream refresh to publish only some media kinds. Refresh status must
survive process restarts without persisting provider payloads or diagnostic secrets.

Remote M3U acquisition also needs a finite response bound. A typical 100,000-entry synthetic M3U is
well below 64 MiB, while an unbounded response is unsafe on tvOS. `Content-Length` alone is not a
control because it can be absent or false.

## Decision

- `Library` owns an actor-isolated, provider-neutral `CatalogRefreshService`. Dependencies are
  constructor-injected: catalog/metadata repository, M3U acquisition, provider adapter, importers and
  clock. The service has no SwiftUI or `MainActor` dependency.
- A refresh reports platform-neutral stages: validating, acquiring, parsing/decoding, staging,
  committing, completed, failed and cancelled. Errors collapse to safe result categories rather than
  retaining raw provider errors or payloads.
- Source enabled state, source kind requirements, endpoint presence and Xtream credential reference
  are validated before network work. There is no implicit retry or scheduling in Phase 2E.
- Production M3U acquisition uses an ephemeral, cacheless, cookieless `URLSession`, async bytes, a
  30-second request timeout and a 64 MiB maximum. It checks declared length early and counts received
  bytes independently. Redirects must remain absolute HTTP(S), contain no URL user/password, and
  cannot downgrade HTTPS to HTTP. Diagnostics sanitize the endpoint with `SafeDiagnostics`; URLs and
  response bodies are never logged.
- One source ID may have only one active refresh per service. A concurrent request for that source
  returns `inProgress` without becoming a second attempt. Different source acquisition may overlap;
  SQLite serializes its short calls and final commits without an unbounded task queue.
- A staging ID may own multiple partitions for one source. Xtream live, VOD and series categories and
  items are staged under one ID and published in one final transaction. M3U uses the same mechanism
  with one `unspecified` partition. Staging batches remain query-invisible and capped at 256 rows.
- SQLite schema version 3 changes `staged_catalogs` to a composite key that supports multiple scopes
  per staging ID and adds `refresh_metadata`. Version 1 and 2 stores migrate transactionally; old
  staging is disposable and rebuilt without changing live catalog rows.
- At attempt start, local metadata records source ID, attempt time and `inProgress`. Failure or
  cancellation updates only attempt time/result. Successful metadata—success time and committed item
  count—is written in the same final `BEGIN IMMEDIATE` transaction that publishes the catalog. The
  count is derived from distinct staged rows in that transaction rather than trusting importer event
  counts. Thus a metadata write/commit failure rolls back both catalog B and success metadata,
  preserving catalog A.
- Refresh metadata is local-only. It stores no `Error` text, URL, credentials, tokens, playlist,
  provider JSON or response body.

## Consequences

Positive:

- M3U and Xtream refreshes share one Library boundary while existing parser, provider adapter,
  credential store and persistent sinks remain reusable.
- Live/VOD/series cannot become a partially refreshed Xtream catalog.
- Queries continue seeing the last committed catalog while acquisition or staging is suspended.
- Success timestamps and counts cannot claim a catalog that did not commit.
- Same-source concurrency, cancellation and failure outcomes are deterministic and testable.

Tradeoffs:

- Remote M3U currently accumulates one bounded response `Data` before line parsing. The 64 MiB limit
  bounds that cost but does not claim low peak memory; a future file-backed/streaming line adapter may
  reduce it without changing the refresh boundary.
- The existing Xtream adapter still receives and decodes each provider JSON array as documented by
  ADR-0007. Phase 2E does not add a streaming JSON parser.
- Different-source staging can temporarily consume additional encrypted disk space. Final SQLite
  transactions remain serialized and can briefly delay calls queued on the store actor.
- `inProgress` may remain after abrupt process termination. It means the last attempt did not record
  a terminal result; startup already discards invisible staging and the next attempt replaces it.
- The 64 MiB limit is a compatibility tradeoff. A legitimate larger playlist fails safely and keeps
  the previous catalog; changing the limit requires new device memory and provider-fixture evidence.

This decision adds no UI, refresh scheduler, CloudKit synchronization, playback URL construction or
Phase 3 playback behavior.
