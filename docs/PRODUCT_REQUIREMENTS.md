# Product Requirements

## 1. Product statement

A premium Apple-native IPTV/media client for lawful user-provided sources. The app should feel purpose-built for Apple TV, remain fast with large catalogs, play legitimate streams reliably, and synchronize viewing continuity across Apple devices.

## 2. Primary users

- A household user with one or more Apple TVs and iPhone/iPad devices.
- A user who already has a lawful IPTV/media source and wants a better client.
- A user who expects premium streaming-app quality rather than a utility-style playlist viewer.

## 3. Primary platforms

### P0
- tvOS — primary interaction and quality bar.
- iOS/iPadOS — companion and continuity.

### Later
- macOS.
- Other Apple platforms only after core quality is stable.

## 4. Primary jobs to be done

1. Add a lawful media/IPTV source.
2. Browse live channels, movies and series quickly.
3. Search a large library.
4. Start playback with minimal friction.
5. Stop on Apple TV and continue on iPhone/iPad near the same position.
6. Keep favorites and selected preferences synchronized.
7. Recover gracefully from provider/network failures.

## 5. Localization and language support

The MVP interface languages are:

- English.
- German.
- Arabic with complete right-to-left support.

Arabic is a first-class product language. It must not be treated as a late translation pass.
Layouts, typography, tvOS focus behavior, accessibility and reusable components must be designed
and tested for RTL from the beginning.

Use Apple-native localization and system typography. App-owned strings must be localizable, while
provider-supplied media metadata may remain in any source language.

Read `docs/LOCALIZATION.md`.

## 6. MVP feature set

### Source management
- Xtream-compatible API/source support.
- M3U playlist support.
- Source validation.
- source refresh.
- safe credential storage.

### Library
- Live TV.
- Movies.
- Series/episodes.
- Favorites.
- Continue Watching.
- Search.
- categories.

### Playback
- AVPlayer/AVFoundation first.
- resume from saved position.
- playback progress tracking.
- mark watched based on configurable completion policy.
- standard subtitle/audio-track selection when exposed by the media.
- useful playback error states.

### Sync
- watch progress.
- favorites.
- selected non-secret settings.
- conflict resolution for changes from multiple devices.

## 7. Explicitly not MVP

- built-in content provider.
- account/password backend owned by us.
- social features.
- household profiles unless later justified.
- recordings/DVR.
- downloads.
- advanced recommendation ML.
- second playback engine unless compatibility evidence requires it.
- macOS app.

## 8. Quality requirements

### Design
- tvOS must feel native, calm and cinematic.
- English, German and Arabic RTL must preserve the same premium visual hierarchy.
- Arabic text must render with correct shaping, alignment and wrapping without clipped or broken layouts.
- reusable UI must avoid hard-coded left/right assumptions.
- cards must have clear focus states.
- layouts must work at TV viewing distance.
- avoid clutter.
- loading should preserve spatial stability.

### Performance
- cached catalog should appear quickly.
- browsing must remain responsive with large fixtures.
- parsing/import must not block UI.
- image cache must be bounded.

### Reliability
- network failures must not corrupt local catalog.
- provider refresh should be transactional when practical.
- playback progress should survive app interruption.
- CloudKit being unavailable must not make local playback unusable.

## 9. Legal/content boundary

The app is a player. It does not provide media, subscriptions, playlists, copyrighted catalogs, provider accounts, DRM bypass or unauthorized scraping.

## 10. Success metrics

Track during development:
- cold/warm launch to interactive UI.
- time to first cached content.
- focus/navigation responsiveness.
- playback start latency, separated into app overhead vs provider/network delay.
- crash-free sessions.
- import time for 10k/50k/100k item synthetic catalogs.
- memory stability while scrolling large poster grids.
- watch-progress resume error in seconds.
- CloudKit sync convergence time under normal network conditions.
