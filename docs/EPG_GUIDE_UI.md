# Phase 6C — EPG Guide UI

The Guide is a local, source-scoped presentation of committed XMLTV data. It never acquires XMLTV,
opens SQLite from SwiftUI, guesses a channel identity, or constructs a playback URL.

Phase 6F-B bounded Guide time navigation is **STABLE ON MAIN** through PR #36 at merge commit
`5a50668a8d4cedeed4b43ff86f0d7e9499d3aac0`. Post-merge push CI `36898632649` passed both Core /
Build / Analyze and tvOS UI Tests. Physical-device and real-provider validation gates remain open.

## Query bounds

`ProductionEPGService` reads one deterministic committed catalog candidate page of 40 rows and then
issues one indexed EPG query for the exact mapped channel IDs. The initial interval is eight hours:
two hours before the opening instant and six hours after it. Programme rows overlap the interval and
are sorted by exact channel identity, start time, then programme identity. The presentation contains
catalog-item IDs, display titles, and programme metadata only; the encrypted XMLTV mapping stays in
the service boundary.

The Guide keeps one explicit eight-hour interval. Previous and Next shift the current interval by
exactly eight hours from its existing boundaries; Jump to Now restores the canonical two-hours-before
through six-hours-after interval. Time movement retains the current catalog page offset. Every reload
therefore remains one 40-candidate catalog page plus one source-scoped indexed interval query; it
does not prefetch adjacent days or materialize a source schedule.

## UI and playback

tvOS uses native focusable programme cells in channel rows. Returning from programme detail restores
the remembered programme cell; leaving the guide returns to the existing library focus fallback. A
time-window replacement restores focus to the first programme on the prior channel when available,
then the first available programme, then the action that initiated navigation for an empty window.
Catalog pagination restores focus to the first available programme on the new page. One presentation
change handler coordinates both restoration policies and does not reset focus while detail is open.
iPhone and iPad use the same guide presentation in vertically scrolling channel sections with
horizontal programme rows and no tvOS focus state.

Programme detail exposes only channel/title/subtitle/description/category and local start/end time.
Play passes the mapped catalog item ID to the existing `PlaybackSession` resolver path. EPG never
owns media URLs, credentials, source UUIDs, or provider IDs.

## Current-time and localization

Persistence uses absolute instants; guide labels use the device locale and timezone. English, German,
and Arabic app-owned labels are in the shared String Catalog. SwiftUI semantic layout provides native
RTL; programme titles remain provider content. A `TimelineView` updates only while the guide is on
screen at a one-minute cadence—there is no global timer or polling service.

## Performance evidence

The SQLite guide query is bounded to at most 40 mapped channels and an eight-hour interval. The
shared EPG scale fixture imports 100, 1,000, and 10,000 synthetic channels and keeps lookup/query
work source-scoped. UI automation uses two synthetic channels only; it does not instantiate a large
SwiftUI hierarchy.

## Remaining validation

Physical Apple TV Guide focus/navigation, EPG performance, EPG health/status focus and Arabic RTL,
and physical iPhone/iPad touch/layout/status review remain pending. Local scale/RSS evidence does not
establish physical-device performance. Phase 6F-A real-provider XMLTV validation is **BLOCKED /
PENDING EXTERNAL VALIDATION INPUT** until owner-approved real XMLTV/M3U data is available; no
compatibility defect or production change was found in Phase 6F-A.
