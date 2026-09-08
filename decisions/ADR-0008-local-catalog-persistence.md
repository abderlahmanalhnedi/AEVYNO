# ADR-0008 — System SQLite Catalog and Encrypted References

Status: Accepted
Date: 2026-09-08

## Context and evaluated options

ADR-0003 requires benchmark-driven local storage for large rebuildable catalogs. Phase 2B and
2C already define transactional sinks and exact source-scoped identity. The storage boundary
must work on the provisional iOS/tvOS 17 minimum and keep database objects out of Domain/UI.

Considered:

- SwiftData: Apple-native schema/context integration, but this slice does not need observable
  model graphs. The required explicit bulk replacement and bounded lifetime would still need
  a dedicated storage adapter. No comparative performance claim is made.
- Core Data with a SQLite store: mature model versioning, private contexts and batch operations.
  A viable alternative, with additional managed-object/context and batch consistency machinery
  for an otherwise flat imported cache. No comparative performance claim is made.
- Apple's system SQLite library: explicit transactions, indexes, foreign keys, prepared statements,
  limited queries and schema versioning without third-party code or managed-object materialization.
  This is the first measured candidate and satisfies this slice's local 100k evidence. The
  benchmark report records actual results and device limitations; it does not prove superiority
  to the unbenchmarked alternatives.

## Decision

Use the SDK's `SQLite3` module behind `CatalogImportRepository` and `CatalogQueryRepository`.
There is no downloaded database package or server. `Library` depends on these abstractions and
provides `PersistentCatalogImportSink`; the app's Phase 1 preview remains unchanged.

### Transactions and concurrency

One `SQLiteCatalogStore` actor owns two non-Sendable database connections. Acquisition and parsing
write encrypted values to query-invisible staging tables in short, bounded transactions of at most
256 items/categories. No SQLite writer transaction remains open between batches or across an
adapter/network suspension.

After acquisition and validation finish, `commitStagedReplacement` starts `BEGIN IMMEDIATE`,
deletes only the requested source/origin/kind partition, recreates it, copies staged categories and
items in database-local batches of at most 256, and commits. The independent reader sees catalog A
until that final `COMMIT` atomically publishes catalog B. Staging uses `synchronous=NORMAL` because
it is disposable after a crash; the final live replacement switches to `synchronous=FULL` before
`BEGIN IMMEDIATE`. Schema creation and migration are also transactional.

Phase 2D initially allowed one logical staging operation per store. Phase 2E, under ADR-0009, permits
independent staging IDs for different sources and one multi-partition staging ID for Xtream's three
kinds. Overlapping work for the same source and deletion of an actively staged source return `busy`;
no hidden queue holds full catalogs. This logical ownership does not retain a SQLite writer lock.
UUID staging IDs prevent another operation's discard from touching an active import.
Construct one sink per service invocation. The owner must commit/discard each successful staging
begin; `close()` discards unfinished staging. Startup removes invisible staging left by a prior
process crash; abrupt power loss during final commit is not locally simulated.

Every query/batch checks cancellation, and a SQLite progress callback checks it during long SQL
statements. Cleanup deliberately ignores cancellation. Stage failure discards the complete staging
set. Final-copy/commit failure rolls back the live replacement, then discards staging; a rollback or
cleanup error closes the writer, preventing uncertain state from being reused. No detached tasks,
main-actor database work, managed objects crossing actors or unchecked Sendable database wrappers.

### Schema v2 and identity

- `catalogs`: primary key `(source, origin, kind)`. An explicitly empty successful refresh still
  records a committed partition. No timestamp is needed for this foundation.
- `items`: exact existing stable item ID, source UUID, origin, media kind, unchanged display title,
  normalized searchable title, optional category ID, authenticated encrypted reference payload.
- `categories`: stable ID, source UUID, origin, kind, unchanged title, normalized searchable title.
- `staged_catalogs`, `staged_categories`, `staged_items`: encrypted, query-invisible acquisition
  staging keyed by a UUID. Staging rows never replace or join the committed query tables directly.
- Foreign keys tie categories/items to partitions and ensure an item cannot reference a category
  belonging to another source/kind. Missing category references reject commit; they are not silently
  dropped. A provider with inconsistent category endpoints retains its previous catalog and reports
  failure; tolerance policy can be revisited with evidence.

Xtream keeps ADR-0007 item/category IDs and provider item reference. M3U keeps ADR-0006 item IDs;
group IDs use a separate `m3u-group:` hash anchor, scoped to source and exact group title. M3U kind
is `unspecified`: no heuristic guesses live versus movie/series. Group renames change group IDs.
Repeated identical stored IDs within the same partition use last-write-wins; M3U occurrence IDs
continue preserving parser duplicates. Cross-partition ID collisions fail rather than overwrite.

Indexes cover title/ID ordering, source, kind, source+kind and category item queries, plus category
source+kind/kind/title ordering. Search preparation folds case/diacritics with a fixed POSIX locale
and canonical composition while preserving the original display title, including Arabic. Schema v2
sorting is binary `(search_title, id)` and independent of insertion order. This is preparation for
Phase 2F, not full-text, token, substring or language-aware relevance search.

`CatalogPage` requires a positive limit of at most 256 and nonnegative offset. SQL performs
LIMIT/OFFSET; no full catalog is fetched and sliced. Deep offsets do scan skipped index entries,
so callers must restart paging after a refresh. No multi-page snapshot is promised. The benchmark
includes a deep page to expose this cost. Cursor paging can be considered when future UI needs it.
Counts run in the database, without materializing items. Source item count and number of committed
source partitions are separate operations.

### Privacy review for persisted references

`docs/SECURITY_PRIVACY.md` prohibits plaintext credential material in catalog fields. Exact M3U
media URLs can contain opaque embedded credentials and cannot safely be reconstructed by stripping
or normalizing them. This ADR records the narrow encrypted-storage design for these references:

- Encode only media URL, artwork URL and optional provider item reference, then encrypt with
  CryptoKit AES-256-GCM, a fresh nonce per write, and item ID as authenticated associated data.
- Preserve each URL's `absoluteString` bytes as supplied by the normalized import; do not parse out
  username/password/token fields. Encrypt all artwork references too, including Xtream artwork.
- A separate `CatalogKeyStore` stores the random 256-bit key in device-local, nonsynchronizing
  Keychain with `WhenUnlockedThisDeviceOnly`. It reuses the existing tested Keychain client boundary.
  The key is separate from provider credentials and is never stored in SQLite.
- No username/password/token fields, source credentials, raw response bodies, diagnostic payloads,
  account discovery snapshots or EPG data are serialized. Existing title/category metadata remains
  local plaintext; this is field encryption, not full-database encryption. User/provider-supplied
  metadata is untrusted and must not be logged.
- Losing the key makes references unreadable and requires an explicit cache reset/re-import in a
  future source flow. Wrong/corrupt keys fail safely; there is no automatic destructive reset.
- Catalog deletion never deletes Keychain credentials or the shared encryption key. No favorites,
  history or progress storage is owned by this schema.

`openDefault()` places the rebuildable database in the sandbox Caches directory and marks its
containing directory excluded from backup. tvOS can purge cache storage: durable reopen does not
mean guaranteed permanent availability on Apple TV. No CloudKit/iCloud catalog integration is
present. Test/custom URL initialization is explicit and does not make backup-location guarantees.
The real Keychain entitlement/device runtime and physical Apple TV cache lifecycle remain untested.

### Evolution

Phase 2D introduced `PRAGMA user_version=2`. Phase 2E schema version 3 changes the staging catalog
key for multi-partition sessions and adds local refresh metadata; v1 and v2 migrations are covered by
automated fixtures and do not change committed catalog rows. New stores are created atomically;
unknown versions, unidentified existing stores
and corrupt files fail without reset. Future versions must add an explicit transactional migration
(with old/new fixture tests) or a reviewed cache-rebuild flow; do not open a newer schema
optimistically. No speculative migration ladder is added.

## Evidence and consequences

See [Phase 2D benchmark and validation report](../docs/PHASE_2D_PERSISTENCE.md). Local results cover
10k/50k/100k imports and replacements, bounded queries, service integration, failures and reopen.
Memory peak and physical Apple TV performance are not claimed. SQLite's caches are configured at
4 MiB per connection; that setting is not a process-memory ceiling. The M3U importer's hashed
identity counters and Xtream's response/DTO arrays remain the limitations recorded by ADR-0006/7.

Costs: maintained SQL/schema code, extra encrypted staging disk space, short per-batch staging
transactions, actor query delays during the final copy/delete/commit SQL work, temporary WAL/disk
growth during refresh, encrypted-reference work, retained index pages after deletion, and linear
deep-offset scan cost. Freed database pages can be reused; secure deletion/compaction is not promised.

References:
- [Apple SwiftData](https://developer.apple.com/documentation/swiftdata/)
- [Apple Core Data](https://developer.apple.com/documentation/coredata/)
- [SQLite WAL and durability](https://www.sqlite.org/wal.html)
- [SQLite isolation](https://www.sqlite.org/isolation.html)
- [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html)
