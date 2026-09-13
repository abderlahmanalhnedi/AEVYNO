# Cloud Sync Design

## 1. Purpose

Use iCloud/CloudKit to synchronize lightweight user state so a user can stop on Apple TV and continue on iPhone/iPad.

CloudKit must not become the primary IPTV catalog store.

## 2. Database scope

Use the user's CloudKit **private database** for private synchronized app state.

The app must handle the case where no iCloud account is available and continue locally.

## 3. Phase 4A Watch Progress foundation

### WatchProgress

Phase 4A implements a provider-neutral `CloudWatchProgressRecord` with:

- schema version 1;
- stable `mediaID` (never a playback URL);
- position and duration seconds;
- completion and update time;
- reset generation;
- logical revision; and
- opaque operation ID.

The real adapter uses private custom zone and record type `AEVYNO_WatchProgress_v1`. The CloudKit
record name is a SHA-256 digest of stable media identity, avoiding record-name length and character
constraints without changing synchronization identity.

See [ADR-0014](../decisions/ADR-0014-cloudkit-watch-progress-sync.md).

### Later record types

### Favorite
- stableContentID
- sourceStableID
- createdAt/updatedAt
- removed/tombstone strategy if needed

### UserPreference
Only settings that are safe and useful to synchronize.

### Source metadata
Only non-secret metadata if needed. Credentials remain outside CloudKit.

## 4. Do not sync

- provider password.
- raw access token unless a future reviewed security design explicitly allows it.
- full playlist/catalog.
- full EPG.
- poster cache.
- transient playback URLs.

## 5. Local-first behavior

All UX writes happen locally first through the durable `FileWatchProgressRepository`.

`LocalFirstCloudWatchProgressRepository` records outbound intent only after the local write succeeds.
Cloud sync is asynchronous. Playback and browsing never wait for a CloudKit round trip, and cloud
failure never erases or invalidates usable local progress.

## 6. Progress checkpoint policy

- checkpoint locally periodically.
- checkpoint on pause/exit/background/completion.
- coalesce cloud updates.
- avoid one CloudKit write per second.

## 7. Conflict resolution

Phase 4A rejects timestamp-only last-write-wins. Resolution is deterministic:

1. a higher explicit reset generation wins;
2. completion is sticky within one generation;
3. farther absolute position wins for incomplete progress;
4. logical revision, operation ID, and only then timestamp settle equivalent state.

Material duration differences cannot override completion, explicit reset, or farther progress. A
pending Start Over is rebased above fetched remote generations before upload, allowing a legitimate
reset to clear completion while stale incomplete progress cannot resurrect Resume. Repeated delivery
is idempotent.

Tests must cover:
- Apple TV progresses to minute 40; iPhone later sends stale minute 20.
- completion on one device vs stale active playback on another.
- simultaneous favorites add/remove.
- device clock differences where possible.

Do not assume simple last-write-wins is always correct.

## 8. iCloud unavailable

If account unavailable or CloudKit fails:
- continue local operation.
- expose provider-neutral `idle`, `syncing`, `upToDate`, `unavailable`, `waitingForRetry`, or `failed`
  status without a raw `CKError`.
- retry only bounded transient categories with deterministic exponential backoff and capped CloudKit
  retry hints.
- do not erase local state.

## 9. Incremental change strategy

The adapter uses a dedicated private custom zone, a silent zone subscription, bounded async record-
zone change requests, and a persisted opaque `CKServerChangeToken`. It does not periodically query or
download every Watch Progress record. Per-media coalescing and sync metadata are stored separately at
`Application Support/AEVYNO/watch-progress-sync.json`. Corrupt/future metadata fails safely without
touching `watch-progress.json`.

## 10. Schema evolution

Every CloudKit record has a schema/version strategy from the beginning.

Production schema changes must be planned and tested before TestFlight/App Store rollout.

Unknown cloud record or local sync-metadata schema versions fail explicitly and non-destructively.

## 11. CloudKit configuration status

The repository has no team ID, CloudKit container identifier, iCloud entitlement, or remote-
notification entitlement. The real adapter therefore accepts an injected `CKContainer` and always
uses its private database. The owner must configure both targets with the correct Apple Developer
team, iCloud/CloudKit container, remote notifications, and deployed schema before signed device tests.
No identifier is guessed in source.

## 12. Credentials across devices

MVP default: credentials are stored in Keychain per device.

A future improvement may evaluate synchronized Keychain behavior on the selected supported OS versions. Do not silently duplicate secrets into CloudKit just to make setup easier.
