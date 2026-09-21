# Source Management and Validation

## Scope

This post-Phase-2 integration slice adds durable source CRUD, connection validation, explicit manual
refresh and the tvOS source-management experience. Refresh scheduling is documented separately in
[Refresh Scheduling and Policy](REFRESH_SCHEDULING.md). Final production library/search UI
composition, CloudKit source synchronization and Phase 3 playback remain outside this slice.

## Source registry

`FileSourceRepository` stores durable user-authored metadata at
`Application Support/AEVYNO/sources.json`, outside the purgeable SQLite catalog cache. The actor owns
an ordered in-memory view and persists mutations with atomic file replacement.

The current JSON schema version is 3. Each `SourceConfiguration` contains a stable UUID, display
name, source kind, safe endpoint, enabled state, refresh policy and optional non-secret
`CredentialReference`. M3U sources may additionally carry an optional safe XMLTV endpoint; Xtream
sources cannot. Version 1 records migrate explicitly to version 2 with `manualOnly`, and version 2
records migrate atomically to version 3 with no XMLTV endpoint.
Sorted JSON keys make encoding stable, while array order preserves deterministic creation order.
Duplicate IDs, invalid records, corrupted JSON and unsupported schema versions fail without an
automatic destructive reset. See [ADR-0010](../decisions/ADR-0010-local-source-registry.md).

The registry is intended for a small number of source configurations. Catalog items, categories and
refresh metadata remain in the local SQLite cache. Provider secrets remain in Keychain.

## Drafts and validation

`SourceDraft` is transient application input, not a persistence model. Credential intent is
explicit: no credential, keep the existing credential, or replace it with entered username and
secret values.

Validation trims names and usernames, applies bounded UTF-8 lengths, keeps source kind immutable
during edit, and requires an absolute HTTP(S) endpoint with a host. URL user information, queries and
fragments are rejected. Xtream-compatible sources require either a new credential on creation or an
existing credential reference during edit. M3U sources do not accept credential input.

Current remote M3U acquisition therefore does not support source URLs whose user information, query
or fragment carries credentials. Supporting those providers later requires a reviewed,
Keychain-backed acquisition representation; credentials must not be embedded in registry JSON.

## Service responsibilities

`SourceManagementService` is the provider-neutral workflow boundary between UI and the source
registry, Keychain credential store, durable refresh service and SQLite catalog/refresh repository.
The SwiftUI view model never accesses Keychain, provider adapters or persistence directly.

### Create

For Xtream-compatible sources, the service creates a new opaque `CredentialReference`, stores the
credential first, then persists metadata containing only that reference. If metadata creation fails,
it deletes the new credential. A failed cleanup returns `compensationFailure`. M3U creation writes no
Keychain record.

### Edit

An unchanged credential performs no Keychain write. Replacement reads the existing credential,
writes the new value under the same reference, then updates source metadata. If metadata update
fails, the previous credential is restored; a failed restore returns `compensationFailure`. Source
identity and kind remain stable.

### Test Connection

Testing never imports, stages or commits catalog data. A new or replacement Xtream credential is
stored under a fresh temporary `CredentialReference`, used only for provider discovery, and deleted
after success, provider failure or cancellation. Cleanup failure is surfaced safely. Testing an
unchanged saved Xtream source reuses its existing reference. M3U testing performs bounded acquisition
and parsing without catalog publication.

### Delete and compensation

Deletion spans three independent stores and uses this order:

1. read the existing source and required credential;
2. delete source metadata;
3. delete its credential when one exists;
4. delete the selected source's catalog partitions and refresh metadata last.

If metadata deletion fails, Keychain and catalog state remain untouched. If credential deletion
fails, source metadata is recreated and the catalog remains untouched. If catalog deletion fails,
the credential and source metadata are recreated; SQLite rolls back its catalog/refresh-metadata
transaction. Any failed restoration returns `SourceManagementError.compensationFailure` rather than
being swallowed. Credential-free M3U deletion skips Keychain entirely.

`SQLiteCatalogStore.deleteCatalog(sourceID:)` uses `BEGIN IMMEDIATE`, deletes only matching
`catalogs` and `refresh_metadata` rows, and commits them together. Failure rolls back both changes;
unrelated sources and query-invisible staging semantics are unchanged.

### Enable, disable and Refresh Now

Enable/disable changes only the source's durable metadata. It preserves the stable ID, endpoint,
credential and committed catalog. Disabled sources cannot run a refresh.

Refresh Now and automatic scheduling both delegate the saved source to `SourceRefreshService` and
expose the catalog lifecycle stages. For an M3U source with an XMLTV endpoint, it acquires and
imports XMLTV only after catalog publication; catalog and EPG caches commit independently, so an EPG
failure never removes a usable catalog. Phase 2E last-known-good publication and refresh metadata
semantics remain unchanged. It is never blocked by the separate automatic cadence or retry cooldown.

## Platform experience, localization and accessibility

The native tvOS Sources screen provides loading, empty and actionable error states; an add/edit form;
secure credential replacement; Test Connection; enable/disable; Refresh Now; and confirmed deletion.
Loading/status text does not steal focus. The list remembers a stable source ID and restores focus
after returning from the editor; validation returns focus to the first invalid field.

All app-owned source-management strings are localized in English, German and Arabic. SwiftUI's native
layout direction handles Arabic RTL with semantic leading/trailing layout. Secure-field accessibility
labels and UI automation expose no secret value. Simulator automation covers initial and restored
focus, validation focus, secure Xtream and credential-free M3U forms, safe failure status, manual
refresh, enable/disable, delete, and Arabic RTL. Physical Apple TV focus, remote and visual validation
remain pending.

M3U forms on both platforms include an optional XMLTV endpoint. It uses the same safe endpoint rule
as the playlist: HTTPS/HTTP only, host required, and no user info, query, or fragment. The endpoint
is never included in accessibility content. Xtream forms deliberately do not expose XMLTV settings.

The iPhone/iPad Sources sheet uses a separate touch-first `NavigationStack`, list rows and native
forms. It presents the same saved-source state (kind, enabled state, refresh policy and safe refresh
status), add/edit flow, secure Xtream credential replacement, connection test, enable/disable,
Refresh Now and confirmed deletion as tvOS. The editor calls only `SourceManagementViewModel`; it
does not access Keychain, provider networking, SQLite or refresh scheduling directly. Source save,
delete and sheet dismissal reuse the production library's existing reload boundary, so the committed
library and source context are reread on return. The mobile UI intentionally has no tvOS focus or
remote-control behavior.

Both platforms use the same English, German and Arabic String Catalog entries. Source rows and
operation status expose only safe display metadata; credentials, provider IDs and credential-bearing
URLs are absent from accessibility content. Physical iPhone/iPad touch, keyboard, visual and Arabic
RTL review remain pending.
