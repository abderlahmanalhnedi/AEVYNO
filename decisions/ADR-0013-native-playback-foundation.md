# ADR-0013 — Native Playback Foundation

Status: Accepted
Date: 2026-09-12

## Context

The production library/search composition now opens stable catalog items on tvOS and iOS/iPadOS,
but the `Playback` module was only an importable boundary. Phase 3 needs real playback without
coupling SwiftUI to AVFoundation, using a credential-bearing or short-lived URL as durable identity,
or storing user-authored progress in the rebuildable catalog cache.

AVFoundation/AVPlayer is the approved primary engine. The committed M3U catalog already retains the
exact accepted HTTP/HTTPS media URL. The current Xtream contract deliberately retains only a
provider item reference; it does not retain or document a final playback path, container, episode
enumeration, or episode playback reference. Inventing a common provider URL convention would make
provider-specific assumptions and could expose credentials.

AVPlayer and its observations are not Sendable. Playback presentation therefore needs an explicit
isolation boundary, while catalog resolution and durable progress I/O must remain asynchronous and
off the main actor.

## Decision

- `Core/Playback` owns `PlaybackEngine`, normalized state/failure/timeline types,
  `PlaybackSession`, the ephemeral `PlaybackAsset`, progress policy, and progress repository
  contract. SwiftUI never issues AVPlayer commands directly.
- `NativeAVPlayerEngine` is the only engine. It is `@MainActor` isolated and owns AVPlayer,
  AVPlayerItem, KVO/notification observations, the periodic AVPlayer time observer, and creation of
  a system `AVPlayerViewController`. No unsafe Sendable wrapper is used.
- Each load has a fresh attempt UUID. `PlaybackSession` keeps one event consumer across retry or
  item replacement and accepts only events for the active attempt. Resolution cancellation is not
  presented as failure. Retry is explicit, unbounded automatic reconnect is absent, and every retry
  re-runs asset resolution.
- The Library-layer `ProductionPlaybackAssetResolver` resolves exactly one stable catalog ID.
  Playback URL access remains package-internal to the Playback implementation after construction;
  descriptions redact it. Presentation and progress state contain no URL, source reference, or
  credential.
- A committed M3U `.unspecified` item is playable using its exact stored HTTP/HTTPS URL and remains
  `.unspecified`. Seekability and finite duration come from AVPlayer capabilities, not catalog
  reclassification.
- Xtream live, VOD, and series-level items return normalized `unsupported` in this foundation. The
  persisted provider contract is insufficient to construct a reviewed final playback URL. Series
  entries are not treated as episodes. A later contract must add lawful, tested playback-path and
  episode resolution before these capabilities can become playable.
- `WatchProgress` is durable user-authored domain state keyed by stable media ID. The actor-isolated
  versioned repository atomically stores it at Application Support/AEVYNO/watch-progress.json,
  separately from catalog SQLite. It stores only position, duration, update time, and completion.
- Finite seekable non-live media may persist progress. Clearly live media never gets VOD progress.
  `.unspecified` M3U content becomes eligible only when AVPlayer reports finite duration and
  seekability; its catalog kind is not changed.
- Playing checkpoints are throttled to at least 12 seconds and at least 5 seconds of meaningful
  movement. Pause, dismissal, inactive/background lifecycle, and end request a checkpoint. Progress
  I/O failure does not terminate otherwise usable playback. There is no CloudKit write in Phase 3.
- At or above 95%—or on an end event—the item is completed and its stored position becomes duration.
  Completed media starts from the beginning. A valid earlier position is clamped and sought only
  after the engine reports a finite seekable timeline.
- tvOS and iOS/iPadOS use a minimal SwiftUI bridge around `AVPlayerViewController`, retaining system
  play/pause/scrub and available audio/subtitle controls. tvOS owns focus restoration; mobile uses
  its existing touch navigation. Loading, buffering, safe error, Retry, Play, Resume, and Start Over
  are app-owned localized states.
- HTTPS remains preferred. No ATS exception, TLS bypass, media background mode, PiP entitlement,
  analytics, DRM circumvention, provider hack, server, or second playback engine is added.

## Consequences

Positive:

- Player UI and progress behavior can be tested deterministically without network playback.
- AVFoundation object isolation is explicit and compatible with Swift 6 concurrency checking.
- Retry and replacement reject stale events and do not retain an expired resolved URL.
- Catalog refresh/replacement/source disable cannot erase the separate progress file.
- Future CloudKit synchronization can consume `WatchProgress` without changing player UI.

Tradeoffs and limits:

- Phase 3 supports committed M3U media only. Xtream live/VOD remain visibly unsupported until an
  authoritative playback contract is designed; Xtream series additionally needs episode
  enumeration and episode identity.
- Plain HTTP may be rejected by platform transport security. That is a normalized
  `transportSecurity` failure; this decision does not weaken ATS.
- System controls expose audio/subtitle tracks only when AVFoundation and the asset provide them.
- Simulator fakes validate application state, navigation, localization, and retry—not codec,
  provider, first-frame, long-session, thermal, or remote-control quality.
- The Phase 3 roadmap exit gate and the existing Phase 1 physical UX gate remain pending until a
  physical Apple TV is available.

