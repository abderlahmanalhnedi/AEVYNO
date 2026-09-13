# Playback Foundation

## Status and scope

Phase 3 Playback Foundation is implemented with AVFoundation/AVPlayer as the only playback engine.
Its automated gate covers shared behavior and tvOS/iOS Simulator integration. The roadmap exit gate
is still pending because no physical Apple TV playback validation has been performed.

This slice does not add CloudKit progress sync, Continue Watching UI, Favorites, PiP/background
entitlements, a custom track selector, Xtream URL guessing, episode enumeration, DRM bypass, or a
fallback engine.

## Architecture

```text
tvOS/iOS Detail (stable catalog ID)
  -> PlaybackDetailViewModel
  -> ProductionPlaybackAssetResolver ----> one CatalogLibraryService item lookup
  -> PlaybackSession ---------------------> WatchProgressRepository actor
  -> PlaybackEngine @MainActor
  -> NativeAVPlayerEngine
  -> AVPlayerViewController system UI
```

`Core/Playback` contains the generic engine, session, progress, state, failure, and ephemeral asset
contracts. `Core/Library` joins the stable ID to committed catalog state. App views receive only safe
presentation state and injected protocols. There is no direct SwiftUI-to-AVPlayer, Keychain,
provider, SQLite, or CloudKit access.

## Engine and concurrency

`PlaybackEngine` exposes an event stream and `load`, `play`, `pause`, `seek`, and `stop` commands.
On iOS/tvOS it also supplies an `AVPlayerViewController` so the bridge does not access the underlying
player.

`NativeAVPlayerEngine` is `@MainActor` because AVPlayer, AVPlayerItem, their observations, and the
native controller are non-Sendable UI/media objects. It uses AVPlayer KVO, the playback-ended
notification, and AVPlayer's periodic time observer. It does not use Timer, blocking synchronization,
detached work, or unsafe Sendable conformance. Item observers and the periodic observer are removed
when media stops or is replaced; the AVPlayerItem is released on stop.

The normalized states are `idle`, `loading`, `ready`, `playing`, `paused`, `buffering`, `ended`, and
`failed`. The session publishes only stable ID, title, state, elapsed time, optional finite duration,
seekability, resume position, and a normalized failure.

## Resolution and supported sources

Resolution begins with one stable media ID and performs one exact catalog lookup. It never scans or
materializes the catalog.

| Catalog input | Phase 3 behavior | Reason |
|---|---|---|
| M3U `.unspecified` with accepted HTTP/HTTPS media URL | Playable using the exact committed URL; kind remains `.unspecified` | The committed catalog has the authoritative URL |
| M3U item missing a media URL | `mediaUnavailable` | No asset can be produced safely |
| Missing catalog ID | `itemUnavailable` | Stable identity no longer resolves |
| Catalog/store unavailable | `sourceUnavailable` | No raw persistence detail reaches UI |
| Xtream live | `unsupported` | No reviewed persisted playback path/container contract |
| Xtream VOD | `unsupported` | No reviewed persisted playback path/container contract |
| Xtream series-level item | `unsupported` | No episode enumeration or episode playback identity |

Xtream credentials remain behind the existing Keychain/provider boundary and are not read by this
resolver because there is not yet enough contract information to build a correct final URL. No
provider URL pattern is fabricated. Adding Xtream playback requires a separately reviewed resolver
contract with synthetic provider tests and redaction evidence.

HTTP is accepted only because an existing committed M3U item may lawfully contain it. HTTPS is
preferred. There is no global or scoped ATS relaxation in this change; an ATS rejection becomes the
safe `transportSecurity` failure.

## Ephemeral assets and redaction

`PlaybackAsset` holds the short-lived URL needed by AVPlayer, but URL access is confined to the
Playback package implementation. The type's normal and debug descriptions render `<redacted>`.
Playback UI, accessibility, progress JSON, catalog identity, error text, and CloudKit contain no
playback URL, endpoint, provider reference, username, password, or token.

## Session attempts, retry, and cleanup

Every start/retry assigns a fresh UUID. The session has one engine-event consumer and ignores every
event whose attempt UUID is no longer active. Starting new media cancels obsolete resolution work
and stops/releases the old player item. Dismissal checkpoints useful progress, cancels resolution
and observation, stops the engine, and resets presentation state.

Cancellation is silent rather than a user-facing error. Terminal errors offer an explicit Retry,
which resolves the stable ID again and therefore does not reuse a stale asset. There is no automatic
retry or reconnect loop.

Normalized failures are `sourceUnavailable`, `itemUnavailable`, `unsupported`, `transport`,
`unauthorized`, `forbidden`, `notFound`, `mediaUnavailable`, `unsupportedFormat`,
`transportSecurity`, and `unknown`. The engine maps URL/AVFoundation failures and observed HTTP
401/403/404 status codes without displaying raw NSError/server text.

## Progress, resume, and completion

`WatchProgress` is domain state containing stable media ID, position, duration, timestamp, and a
completed flag. The actor-isolated `FileWatchProgressRepository` stores schema version 1 at:

```text
Application Support/AEVYNO/watch-progress.json
```

Writes use deterministic ordering and atomic file replacement. Corrupt records, duplicate IDs,
invalid ranges, and future schemas fail safely without destructive reset. The file is independent
of rebuildable catalog SQLite, so refresh, catalog replacement, source disable, and unrelated
catalog deletion do not remove progress. Phase 3 does not synchronize it with CloudKit.

Progress is eligible only when playback is not clearly live and AVPlayer reports a finite positive
duration plus seekability. This permits capability-based progress for M3U `.unspecified` while
leaving its catalog classification unchanged. Clearly live content never writes VOD progress or a
completion percentage.

While playing, persistence requires both 12 seconds since the previous checkpoint and at least 5
seconds of position change. Pause, player dismissal, inactive/background transition, and end force
a useful checkpoint. A local write failure does not interrupt playback.

Completion begins at 95% of finite duration. An end event also completes the item. Completed records
store duration as their position and Detail offers Play from the beginning, not Resume near the end.
Earlier finite positions offer Resume and Start Over. Resume is clamped and sought only after the
engine reports a finite seekable timeline; invalid, out-of-range, completed, or live positions are
not sought.

## Platform presentation

tvOS presents `AVPlayerViewController` full screen, preserving native Siri Remote playback, pause,
scrub, system transport, and available audio/subtitle track behavior. SwiftUI owns only loading,
buffering, safe terminal error/Retry, and dismissal integration. Returning from the player leaves
the user on the same Detail; returning from Detail restores the exact stable-ID library focus.
Loading/status changes are not focusable.

iPhone/iPad use the same resolver/session/engine/progress boundaries and native player controller in
a full-screen cover. Mobile navigation remains touch-adapted and contains no tvOS focus mechanics.

All app-owned playback action, state, failure, hint, and duration text is supplied in English,
German, and Arabic. Duration uses system localized formatting. SwiftUI semantic layout provides
native Arabic RTL; strings and video are not manually reversed. Actions have stable accessibility
identifiers and useful labels/hints, while video is not given redundant metadata containing
internal references.

## Deterministic compatibility matrix

CI and simulator UI automation do not fetch public media. Engine/resolver/progress/clock fakes cover
application behavior; the rows that require actual decoding remain physical-device fixtures.

| Fixture or condition | Automated evidence | Physical Apple TV evidence |
|---|---|---|
| HLS VOD / finite seekable asset | ready/play/pause/seek/progress/resume fake | Pending lawful HLS fixture |
| HLS live | live progress suppression fake | Pending lawful live fixture |
| HLS master/variant playlist | engine integration compiles | Pending playback/variant-switch review |
| Subtitle-capable HLS | system controller selected | Pending track/control review |
| Alternate-audio HLS | system controller selected | Pending track/control review |
| Loading and buffering | deterministic engine/UI modes | Pending network-transition review |
| Intermittent/failed transport | normalized failure and retry modes | Pending lawful controlled fixture |
| HTTP 401/403/404 | deterministic failure mapping | Pending server fixture |
| Malformed/unsupported media | normalized engine mapping/resolver failure | Pending asset fixture |
| Cancellation/replacement/stale events | deterministic session tests | Pending rapid-navigation review |
| End of playback / 95% completion | deterministic session/progress tests | Pending complete-playthrough review |

The automated matrix proves application behavior, not codec/provider compatibility or first-frame
latency.

## Application-side performance evidence

The deterministic measurement repeatedly resolves one M3U catalog item, reads an empty durable
progress repository, and creates a session. It enforces a conservative 10 ms average bound for each
operation in the local test environment and prints the exact observed values during `swift test`.
This change does not modify bulk catalog query/import paths, so the 10k/50k/100k benchmarks are not
rerun.

No AVPlayer first-frame, process-memory, thermal, decoder, long-session, or remote interaction
latency is claimed. Those require a physical device.

## Physical Apple TV exit checklist

The Phase 3 exit gate remains **PENDING**. On an available physical Apple TV, validate with lawful
fixtures and redacted diagnostics:

- HTTPS HLS VOD, live, and master/variant playback; first frame and terminal failure behavior.
- pause, resume, scrub, seek clamping, end, replay, audio tracks, and subtitles through system UI.
- loading/buffering recovery, explicit Retry, 403, 404, unsupported media, and ATS-blocked HTTP.
- Back/Menu exit, rapid open/close/retry/replacement, Detail return, and exact item focus restoration.
- relaunch resume, Start Over, 95% completion, no live resume, and catalog refresh/replacement
  independence.
- English, German, and Arabic RTL Detail/error states with VoiceOver and viewing-distance review.
- long-session memory, observer/player-item cleanup, thermal behavior, and Instruments profiling.
- representative lawful providers before making any real-provider compatibility claim.

Physical iPhone/iPad playback is also not run. Phase 4 does not begin as part of this foundation.

