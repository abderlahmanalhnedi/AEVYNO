# ADR-0012 — Production Library UI Composition

Status: Accepted
Date: 2026-09-10

## Context

Phase 2F provides bounded committed-catalog browse, category and search queries, while the Phase 1
Home and Detail surfaces intentionally use synthetic `MediaItem` fixtures. Production application
launch must now present the local catalog without converting incomplete provider records into the
richer synthetic model, loading a complete catalog into SwiftUI, coupling views to SQLite/provider
details, or beginning Phase 3 playback.

Successful manual and scheduled refreshes also need to invalidate visible production queries. The
catalog remains rebuildable local state, so invalidation must not introduce polling, timers,
CloudKit catalog synchronization or a global application-state object.

## Decision

- `ProductionLibraryService` is the shared Library-layer presentation boundary. It joins bounded
  committed `CatalogItem` pages to safe source display names and maps only stable ID, title, exact
  catalog kind, source/category display metadata and optional artwork URL.
- Production records are not converted to `MediaItem`. Synopsis, year, genre, rating, progress,
  favorites, Continue Watching and episode metadata remain absent unless a future authoritative
  data source and feature boundary provide them.
- M3U `.unspecified` remains `.unspecified` throughout the service and is presented as Playlist. No
  title, filename, duration or URL heuristic classifies it as live, movie or series.
- `LibraryPagingController` requests 64 rows initially and retains at most 256 presentation items.
  It suppresses duplicate next-page requests, cancels superseded work, rejects stale generations,
  defensively deduplicates stable IDs and protects the currently focused item during window eviction.
- Search keeps the Phase 2F literal unordered AND-substring semantics and uses a 300 ms UI debounce.
  Scope, source and category changes restart paging at offset zero. SQLite performs catalog-scale
  filtering and ordering off the main actor; SwiftUI receives only bounded mapped pages.
- `LibraryRevisionCenter` is an in-process, buffering-newest invalidation signal shared by the
  production refresh and library services. A revision is published only after a successful durable
  catalog commit. The UI also reloads after returning from Sources and on foreground activation.
  Failed or cancelled refreshes publish nothing, so the last-known-good visible catalog remains.
- tvOS and iOS/iPadOS share service/state behavior but use separate native SwiftUI compositions.
  tvOS owns focus memory/restoration; the mobile composition uses touch navigation and no tvOS focus
  mechanics.
- Production artwork reuses `ArtworkImagePipeline`: request cancellation, ImageIO downsampling and
  the existing 48 MiB LRU memory bound remain in force. Remote responses are capped at 12 MiB and
  use an ephemeral cacheless, cookieless `URLSession`. Missing or failed artwork shows a kind-safe
  neutral placeholder; no synthetic artwork theme is assigned.
- Detail is metadata-only and exposes a non-actionable localized playback-unavailable status. No
  playback URL resolution, `AVPlayer`, StoreKit, analytics or CloudKit catalog work is included.
- Normal launches use production composition. Synthetic Home and production-library fixtures are
  available only through explicit UI-test/demo launch arguments.

## Consequences

Positive:

- Large catalogs remain in SQLite rather than SwiftUI state, with explicit request/window bounds.
- The UI cannot accidentally display richer synthetic metadata as if it came from a provider.
- Manual refresh, automatic refresh, source-management return and foreground activation converge on
  the same safe reload behavior without polling.
- tvOS focus and mobile touch behavior can evolve independently over one shared query contract.

Tradeoffs:

- Offset pagination is still a view of the current committed catalog, so refresh restarts at the
  first page rather than preserving a deep database cursor.
- Category titles are shown on items only while browsing a selected category; deriving every title
  in an unfiltered page would require a broader query contract or N+1 lookups.
- The 256-item window is a structural bound, not a process-memory or jetsam guarantee. Remote artwork,
  SQLite caches and long-session UI behavior still require Instruments and physical Apple TV review.
- In-process revision signals do not survive process termination; the next normal launch/foreground
  load reads the latest committed catalog directly.

This decision does not change Phase 2 completion, begin Phase 3 playback, or satisfy the pending
physical Apple TV validation gate.
