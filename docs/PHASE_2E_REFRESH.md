# Phase 2E Durable Refresh Evidence

Date: 2026-09-08

## Scope and acceptance

Phase 2E adds bounded remote M3U acquisition, provider-neutral refresh orchestration, atomic Xtream
live/VOD/series replacement, local refresh metadata, deterministic concurrency and last-known-good
failure behavior. It adds no source-management UI, scheduler, production search, CloudKit catalog
sync, playback URL resolution or playback implementation. Architecture decisions are recorded in
[ADR-0009](../decisions/ADR-0009-durable-source-refresh.md).

Acceptance: validate before network work; never hold the live replacement transaction while waiting
on a provider; bound M3U response bytes independently of `Content-Length`; keep catalog A unchanged
after invalid source, missing credential, authentication, HTTP/network/timeout, malformed input,
cancellation, category-integrity, staging, persistence or final-commit failure; commit Xtream's three
kinds and success metadata atomically; allow different-source acquisition while rejecting a second
same-source refresh.

## Implementation behavior

- M3U: Foundation `URLSession` only, ephemeral/cacheless/cookieless configuration, async bytes,
  30-second request timeout, no retry, 64 MiB limit, 2xx validation and safe redirect policy.
- Xtream: reuses `XtreamProviderAdapter`, its centralized request construction and `CredentialStore`.
  Authentication discovery precedes catalog staging; live, VOD and series categories/items use the
  existing normalized models and bounded import service. No final stream URL is constructed.
- Persistence: schema v3 supports one staging ID across the three Xtream partitions. Staging writes
  are query-invisible transactions of at most 256 items/categories. Only the final database-local
  copy opens the live `BEGIN IMMEDIATE`; success metadata is part of that same transaction.
- Metadata: local source ID, last attempt, last success, committed live item count and safe result
  category. The count is derived from distinct staged rows inside the publication transaction, so a
  repeated provider ID cannot overstate the live catalog. Failure/cancellation preserves prior
  success time/count. No raw error text or source data is stored.
- Concurrency: `CatalogRefreshService` rejects a second same-source refresh with `inProgress` before
  recording a new attempt. Different sources can acquire concurrently and have separate staging IDs;
  the store actor bounds and serializes SQLite calls/final commits.

## Synthetic failure and integration evidence

Automated tests use only `example.invalid`, synthetic credentials and generated data. Coverage
includes:

- M3U 2xx, 401, 403, 404, 5xx, connection failure, timeout, cancellation, empty body, oversized body,
  lying `Content-Length`, disabled source and malformed playlist after successful transport;
- first M3U import, successful replacement, exact opaque media reference and group persistence,
  malformed/network/cancelled replacement preserving the committed catalog;
- Xtream authentication plus live/VOD/series categories and items through adapter, staging,
  persistence and queries; missing credential, authentication rejection, malformed JSON, transport
  failure, cancellation and missing-category commit failure preserve all prior kinds;
- injected successful-metadata write failure rolls back catalog publication and retains the previous
  success timestamp/count;
- one-second synthetic M3U acquisition delay leaves the old catalog queryable in under the asserted
  250 ms bound, leaves no M3U staging before download completes, and permits an independent SQLite
  connection to acquire `BEGIN IMMEDIATE`; a second same-source call returns `inProgress` while a
  different source completes;
- schema v1 and v2 migration to v3, multi-partition staging, bounded batches and existing Phase 2D
  rollback/commit/cancellation cases.

## Release performance evidence

MacBook Air Mac14,2, Apple M2 (8 CPU cores), 8 GB RAM, macOS 26.6.2 (25G83), Xcode 26.6
(17F113), Apple Swift 6.3.3. Release-mode Swift Testing, system SQLite, WAL, encrypted references,
256-row maximum batches, 100 categories and synthetic data only. Reproduce with:

```sh
swift test -c release --filter CatalogRefreshPerformanceTests
```

The M3U response `Data` and normalized-provider generator are prepared before the timer. M3U
acquisition therefore measures only the deterministic in-memory transport handoff, not real network
throughput. `parse/normalize/orchestration` and provider `acquire/normalize/orchestration` are derived
as total minus directly timed repository staging, final transaction and M3U acquisition. They include
small metadata/actor overhead. Provider rows are distributed across live/VOD/series. These are single
local observations, not percentiles or device guarantees.

| Rows | M3U acquisition (s) | M3U parse/normalize/orchestration (s) | M3U staging (s) | M3U final transaction (s) | M3U total (s) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 0.000 | 0.141 | 0.278 | 0.172 | 0.591 |
| 50,000 | 0.000 | 0.560 | 1.858 | 0.803 | 3.221 |
| 100,000 | 0.000 | 1.120 | 4.523 | 1.924 | 7.567 |

| Rows | Provider acquire/normalize/orchestration (s) | Provider staging (s) | Provider final transaction (s) | Provider total (s) |
| ---: | ---: | ---: | ---: | ---: |
| 10,000 | 0.041 | 0.226 | 0.145 | 0.412 |
| 50,000 | 0.179 | 1.738 | 0.869 | 2.786 |
| 100,000 | 0.358 | 4.333 | 2.091 | 6.783 |

The tests show bounded batch sizes and no quadratic failure signature across these three points, but
do not establish an asymptotic proof. Peak memory was not measured. Structural bounds are a 64 MiB
M3U body, 256-row staging calls and 256-row query pages. The parser retains identity counters, the
Xtream adapter retains one endpoint response/decoded DTO array, and SQLite/Foundation/CryptoKit add
unmeasured memory. Physical Apple TV Instruments profiling remains required.

## Security and privacy audit

The Phase 2E patch adds no plaintext Keychain duplication, credential logging, full URL diagnostics,
raw M3U/provider payload logging, CloudKit catalog sync, analytics/tracking, real IPTV data, ATS
weakening or TLS bypass. Redirects cannot downgrade HTTPS to HTTP. M3U diagnostics contain a safe
category and `SafeDiagnostics`-sanitized endpoint only. Durable metadata contains only safe scalar
state. Opaque catalog references continue using ADR-0008 encryption.

## Remaining validation

- Physical Apple TV storage, Keychain, memory and long-refresh profiling: not run.
- Phase 1 physical LTR/Arabic RTL UX gate: pending because the device is unavailable.
- Real provider compatibility is not claimed; tests intentionally use synthetic transports only.
- Peak memory is not claimed.
