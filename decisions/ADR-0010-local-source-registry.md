# ADR-0010 — Local Durable Source Registry

Status: Accepted
Date: 2026-09-09

Amended by [ADR-0011](ADR-0011-refresh-scheduling-policy.md), which advances the registry to schema
version 2 and explicitly migrates version 1 sources to the manual-only refresh policy.

## Context

Source configurations are small, user-authored durable state. They must survive loss or purge of
the rebuildable SQLite catalog cache. Provider credentials are separate secret state and must remain
in the device-local Keychain under ADR-0005; the source registry may retain only an indirect
`CredentialReference`.

The application also needs deterministic source ordering, explicit schema handling and safe failure
behavior without introducing a database framework or treating catalog-scale data as configuration.

## Decision

- `FileSourceRepository` owns a versioned JSON registry at
  `Application Support/AEVYNO/sources.json`.
- Schema version 1 stores an ordered array of `SourceConfiguration` values. Encoding uses sorted JSON
  keys, while the source array preserves deterministic creation order.
- Writes use atomic file replacement. The actor-isolated repository serializes loading and mutation.
- A source contains its stable ID, display name, kind, safe HTTP(S) endpoint, optional non-secret
  `CredentialReference` and enabled state. It never contains a username, password or token.
- Duplicate IDs, invalid sources, malformed JSON and unsupported schema versions fail explicitly.
  The repository does not destructively reset an unreadable or newer registry.
- Future schema changes require explicit version-aware migration or an approved replacement
  decision. The registry is not a catalog store.

## Cross-store consistency

The filesystem registry, Keychain and SQLite catalog cache cannot share one atomic transaction.
`SourceManagementService` therefore owns small, explicit compensating workflows:

- create stores a required credential before metadata and deletes that credential if metadata
  creation fails;
- credential replacement saves the previous credential and restores it if metadata update fails;
- delete reads the existing metadata and credential, deletes source metadata, deletes its credential
  when present, and deletes the catalog plus refresh metadata last;
- a credential-delete failure restores source metadata without touching the catalog;
- a transactional catalog-delete failure restores the credential and source metadata;
- any failed restoration is reported as `SourceManagementError.compensationFailure`.

SQLite continues to delete only the selected source's catalog partitions and refresh metadata within
one `BEGIN IMMEDIATE` transaction. A failure rolls that transaction back, preserving the
last-known-good catalog.

## Security

- Registry JSON must contain no username, password, token or credential-bearing URL.
- `SourceEndpoint` rejects URL user information, queries and fragments. Endpoint content must not be
  logged or exposed through accessibility diagnostics.
- Credentials remain device-local, nonsynchronizing Keychain records. The registry and catalog are
  not synchronized through CloudKit.

## Consequences

Positive:

- user-authored source metadata survives cache purge and catalog rebuild;
- source counts remain small and straightforward to inspect, version and migrate;
- actor isolation and atomic replacement give deterministic single-repository behavior;
- cross-store failure behavior is explicit and regression-testable.

Tradeoffs:

- there is no true transaction across filesystem, Keychain and SQLite;
- compensation can itself fail and requires a distinct actionable error path;
- JSON is appropriate for small source counts, not catalog-scale records or frequent bulk writes;
- a future format change must preserve or deliberately migrate schema version 1.
