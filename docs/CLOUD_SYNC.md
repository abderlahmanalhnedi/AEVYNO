# Cloud Sync Design

## 1. Purpose

Use iCloud/CloudKit to synchronize lightweight user state so a user can stop on Apple TV and continue on iPhone/iPad.

CloudKit must not become the primary IPTV catalog store.

## 2. Database scope

Use the user's CloudKit **private database** for private synchronized app state.

The app must handle the case where no iCloud account is available and continue locally.

## 3. Candidate record types

### WatchProgress
- stableContentID
- sourceStableID
- positionSeconds
- durationSeconds
- completed
- updatedAt
- version/schemaVersion

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

All UX writes happen locally first.

Cloud sync is asynchronous. Playback and browsing must not wait for a cloud round trip.

## 6. Progress checkpoint policy

- checkpoint locally periodically.
- checkpoint on pause/exit/background/completion.
- coalesce cloud updates.
- avoid one CloudKit write per second.

## 7. Conflict resolution

Must be deterministic and tested.

Tests must cover:
- Apple TV progresses to minute 40; iPhone later sends stale minute 20.
- completion on one device vs stale active playback on another.
- simultaneous favorites add/remove.
- device clock differences where possible.

Do not assume simple last-write-wins is always correct.

## 8. iCloud unavailable

If account unavailable or CloudKit fails:
- continue local operation.
- expose non-blocking sync status.
- retry with backoff.
- do not erase local state.

## 9. Schema evolution

Every CloudKit record has a schema/version strategy from the beginning.

Production schema changes must be planned and tested before TestFlight/App Store rollout.

## 10. Credentials across devices

MVP default: credentials are stored in Keychain per device.

A future improvement may evaluate synchronized Keychain behavior on the selected supported OS versions. Do not silently duplicate secrets into CloudKit just to make setup easier.
