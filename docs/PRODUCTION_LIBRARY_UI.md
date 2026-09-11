# Production Library and Search UI

Date: 2026-09-10
Status: Implemented; under final validation/review

## Scope

The normal tvOS and iOS/iPadOS launch paths now browse the committed local production catalog.
Explicit Phase 1 demo/state/stress arguments continue to launch synthetic Home; deterministic
production UI fixtures are also launch-argument-only. Production records are never repackaged as
synthetic `MediaItem` values.

This slice contains no playback, playback URL resolution, favorites, Continue Watching, CloudKit
catalog synchronization, commerce, analytics or tracking.

## Architecture and data flow

```text
SwiftUI screen
  -> ProductionLibraryViewModel (screen state, debounce, lifecycle reload)
  -> LibraryPagingController (64-row pages, 256-item window, cancellation/generation)
  -> ProductionLibraryService (safe presentation mapping + source names)
  -> CatalogLibraryService
  -> CatalogQueryRepository / committed SQLite catalog
```

`ProductionLibraryService` exposes only safe display data: exact stable catalog ID, provider title,
exact `CatalogMediaKind`, source display name, optional selected-category title and optional artwork
URL. It does not expose `mediaURL`, `providerReference`, credentials, source internal IDs in
accessibility text, or fabricated synopsis/progress/rating/year/genre/favorite/episode state.

Movies, Series and Live TV select the exact Xtream VOD/series/live partitions. Playlist selects only
M3U origin with `.unspecified` kind. Library and Search can span sources and kinds. M3U content is
never guessed from its title, extension, duration, group or URL.

Categories preserve source, origin and kind identity even when provider category IDs/titles collide.
Selecting a category applies its complete scope and resets offset paging. Disabled sources remain
available as filters when they still have committed last-known-good catalog data; disabled state
prevents refresh, not local browsing.

Search retains the Phase 2F semantics: fixed POSIX case/diacritic folding, Unicode whitespace terms,
literal unordered AND-substrings, deterministic normalized-title/stable-ID ordering, no fuzzy match,
transliteration or relevance ranking. UI input changes use a 300 ms debounce. Submit, scope, source
and category changes cancel superseded work; stale generations cannot replace current results.

## Paging and memory bounds

- Initial and subsequent presentation page: 64 items.
- Persistence hard maximum per request: 256 items.
- Maximum retained SwiftUI presentation window: 256 items.
- Category page: at most 256 summaries.
- Artwork response body: at most 12 MiB.
- Artwork memory cache: existing 48 MiB LRU default.

The pager suppresses a second next-page request while one is active, cancels a superseded request,
rejects late stale results, removes duplicate stable IDs and avoids evicting the protected focused
item. The 10k/50k/100k composition test maps only 384 requested rows while retaining 256; it does not
materialize those catalog scales in SwiftUI. Phase 2F's measured SQLite query evidence remains in
[Phase 2F Production Library Search Evidence](PHASE_2F_LIBRARY_SEARCH.md).

These are structural bounds, not physical Apple TV peak-memory measurements. Instruments, long
browsing sessions and jetsam behavior remain real-device validation work.

## Refresh invalidation

The production container shares one `LibraryRevisionCenter` between `CatalogRefreshService` and
`ProductionLibraryService`. A revision is emitted only after the durable refresh path has committed
successfully. Both manual Refresh Now and scheduled refresh use that same service. The view model
observes revisions even from the no-catalog state, and successful publication restarts bounded
paging without showing a focus-stealing loading state.

Returning from Sources and entering the active foreground state also re-read source context and the
committed catalog. There is no `Timer`, database polling, busy loop, detached task or global AppState.
Failed/cancelled refresh does not publish a revision and the persistence transaction guarantees keep
the last-known-good catalog visible.

## Platform UI

tvOS provides scope controls, source/category filters, native search, a lazy grid, explicit bounded
page loading, safe metadata-only Detail, source-management navigation and stable-ID focus memory.
Item updates restore the remembered item when it remains in the bounded result; otherwise focus
moves predictably to the first current result. Loading/status updates do not become focus targets.

iPhone/iPad use a separate touch composition with `NavigationStack`, toolbar menus, adaptive lazy
grid, search, sheets and touch Detail navigation. No tvOS `FocusState` behavior is shared with mobile.

App-owned strings are complete in English, German and Arabic through the shared String Catalog.
Layouts use semantic leading/trailing alignment and native SwiftUI RTL; there are no manual bidi
markers, string reversal or forced direction overrides. Provider titles and source/category names
remain unmodified content.

Accessibility cards expose only title plus localized kind/source/selected-category display text.
Artwork is decorative. URLs, provider references, credential references, source UUIDs, passwords,
tokens and endpoint diagnostics are never placed in labels, values or hints.

## Artwork

Production artwork uses `RemoteArtworkImageView` over the existing actor-isolated
`ArtworkImagePipeline`, rather than `AsyncImage` or a third-party library. It uses cancellation,
target-dimension clamping, ImageIO thumbnail downsampling, bounded LRU caching and memory-warning
purge behavior. Networking is ephemeral, cacheless and cookieless with a 15-second timeout and
12 MiB response cap. The pipeline does not log artwork URLs or attach Keychain/provider credentials.
Missing/invalid artwork renders a neutral kind-specific system-symbol placeholder with no fabricated
theme.

## Validation boundary

Deterministic shared tests use local actors/stubs and synthetic catalog values only. tvOS UI tests
use injected local production-library and source-management fixtures; they never access provider
networking, production credentials or the user's catalog. Final command counts and CI links are
recorded in `PROJECT_STATUS.md` and the pull request after validation completes.

Physical Apple TV LTR/Arabic RTL focus, visual quality, long-session memory and Instruments review
remain pending. Physical iPhone/iPad validation has not been run. Phase 3 playback has not started.

See [ADR-0012](../decisions/ADR-0012-production-library-ui-composition.md).
