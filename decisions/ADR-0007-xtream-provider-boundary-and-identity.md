# ADR-0007 — Xtream Provider Boundary and Identity

Status: Accepted
Date: 2026-09-08

## Context

Xtream-compatible sources expose account discovery, categories and media lists through a
credential-bearing HTTP API. Provider payloads commonly mix numeric and string field types, and
catalog endpoints can return 100,000 items in one JSON array. The application needs stable local
identity and a testable import path without leaking provider protocol details or credentials into
UI, persistence or domain models.

## Decision

- `IPTVCore` owns the Xtream-compatible adapter, request builder, transport abstraction and private
  provider DTOs. It resolves credentials through the Phase 2A `CredentialStore` boundary.
- Requests use `URLComponents`, an explicit timeout and injected async Foundation transport. There
  are no automatic retries. Task cancellation remains `CancellationError`.
- Credential-bearing request URLs exist only for the transport call. Diagnostics expose normalized
  errors and use the existing safe URL redaction behavior; raw request URLs and response bodies are
  not retained or surfaced.
- The adapter decodes each provider array once and emits normalized catalog items individually to an
  async consumer. This avoids a second full normalized array while acknowledging that Foundation's
  JSON decoding and the provider's array response require response data and decoded DTOs during the
  request.
- `Library` writes emitted items through a transactional, bounded-batch sink. Production persistence
  remains a later benchmark-driven decision.
- A normalized item ID is the SHA-256 digest of the source UUID, item namespace, media kind and
  non-empty provider item ID. Category IDs use the source UUID, category namespace, media kind and
  provider category ID. The digest does not contain credentials, titles or artwork URLs.
- Invalid required provider IDs or titles are skipped and counted. An empty provider array remains a
  valid empty catalog; a structurally invalid top-level response is an error.

## Consequences

Positive:

- Same-source refreshes preserve identity while provider IDs remain stable.
- Identical provider IDs from different sources or media kinds cannot collide at the application
  identity level.
- UI and future persistence code remain independent of Xtream query and DTO details.
- Tests can inspect exact requests and simulate errors without an internet connection.
- Catalog import can stage bounded batches and roll back on cancellation or failure.

Tradeoffs:

- A provider changing or reusing its own item ID changes or aliases local identity respectively.
- A single catalog response is still held as response bytes and decoded DTOs because the provider
  returns a top-level JSON array; this phase does not add a custom streaming JSON parser.
- Source-scoped identity is device-stable only while the existing source UUID is preserved.

This decision does not define playback URLs, select production persistence, add EPG support or relax
App Transport Security.
