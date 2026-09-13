# Playback Compatibility Strategy

## 1. Goal

Maximize reliable playback of lawful user-provided streams while preserving a native App Store-friendly Apple architecture.

## 2. Primary engine

AVFoundation/AVPlayer is the default and only MVP playback engine.

Reasons:
- native tvOS integration.
- system media controls.
- AirPlay/PiP integration potential.
- system audio/subtitle track handling.
- lower dependency and licensing complexity.

## 3. Compatibility architecture

The player UI must depend on an abstract playback interface, not scattered AVPlayer calls.

Represent:
- loading.
- ready.
- playing.
- paused.
- buffering.
- ended.
- failed with normalized failure reason.

Phase 3 implements this as a main-actor `PlaybackEngine` with attempt-scoped event streaming, a
presentation-safe `PlaybackSession`, and the only concrete engine `NativeAVPlayerEngine`. SwiftUI
uses an engine-supplied `AVPlayerViewController`; it does not manipulate AVPlayer directly.

## 4. Compatibility fixture corpus

Maintain lawful/synthetic test fixtures for different media patterns, for example:
- HLS VOD.
- HLS live.
- variant playlists.
- streams with subtitles.
- multiple audio tracks.
- intermittent network.
- expired/403 URL.
- malformed playlist.
- unsupported media fixture.

Do not commit private provider credentials.

The deterministic Phase 3 matrix covers application-side ready/play/pause/buffer/end, finite seek,
live progress suppression, explicit retry, cancellation/replacement/stale attempts, 401/403/404,
unsupported media and completion without a network dependency. HLS VOD/live/master, subtitle and
alternate-audio decoding remain lawful physical-device fixtures; simulator fakes do not establish
codec or provider compatibility. See [Playback Foundation](PLAYBACK_FOUNDATION.md).

## 5. Source URL handling

- sanitize/redact query credentials in logs.
- do not persist short-lived playback URLs as long-term identity.
- separate stable media identity from current stream URL.

The Phase 3 Library resolver performs one exact stable-ID catalog lookup. A committed M3U
`.unspecified` item uses its exact accepted media URL but remains unclassified. Xtream live/VOD are
not yet playable because the current persisted provider reference does not document a final path or
container; series-level records additionally lack episode enumeration and episode identity. All
three return `unsupported` rather than guessing a provider URL.

## 6. HTTP/ATS

Prefer HTTPS.

Do not set a blanket global ATS bypass.

If real providers require plain HTTP media, research the current Apple-supported narrowly scoped media transport configuration, document the exact requirement, threat model and App Store implications in an ADR, and add tests. Never relax all network security merely for convenience.

## 7. Second-engine gate

A fallback engine such as VLC/FFmpeg-based technology may be considered only after:
- a meaningful percentage of legitimate test streams fail reproducibly.
- failure cannot be solved by correct AVFoundation usage/source normalization.
- license obligations are reviewed.
- binary-size impact is measured.
- App Store implications are reviewed.
- performance/memory are compared.
- an ADR is approved.

Fallback must plug into the existing playback abstraction.

## 8. Recovery behavior

For transient errors:
- distinguish buffering from terminal failure.
- retry only when safe; avoid infinite retry loops.
- preserve progress across retries.
- surface a concise actionable error when terminal.

Phase 3 performs no automatic retry. The user-triggered Retry creates a new attempt UUID and
re-resolves the stable media ID. Events from older attempts are ignored and cancellation is not
shown as failure.

## 9. Progress semantics

Progress identity must use stable media IDs.

Do not save progress for live TV as if it were VOD unless timeshift/DVR semantics are explicitly implemented later.

Phase 3 fixes the initial completion threshold at 95%. Finite seekable non-live media persists local
progress; clearly live media does not. `.unspecified` M3U becomes eligible only from actual player
duration/seekability and is never reclassified. Completed items start from the beginning.
