# Roadmap

## Phase 0 — Foundation

Deliver:
- Xcode project/workspace.
- tvOS + iOS/iPadOS targets.
- shared modules.
- DesignSystem skeleton.
- mock Home screen.
- basic tests/build automation.

Exit gate:
- clean build.
- tests pass.
- tvOS focus works in simulator.
- real Apple TV validation still explicitly pending if not performed.

## Phase 1 — Premium tvOS shell

Deliver:
- Home rails/cards.
- Detail screen.
- navigation/focus restoration.
- loading/error/empty states.
- image pipeline abstraction/cache.
- synthetic large-catalog UI stress fixture.
- localization foundation using Apple-native String Catalogs.
- English, German and Arabic interface resources for Phase 1-owned UI.
- Arabic RTL-safe Home, Detail, loading, empty and error states.

Exit gate:
- English, German and Arabic RTL simulator review passes for Phase 1-owned UI.
- Arabic tvOS focus movement and Detail/back restoration pass automated coverage.
- real Apple TV UX review includes Arabic RTL.
- no obvious navigation/focus stalls or broken/truncated Arabic layouts.

## Phase 2 — Sources and local library

Status: **COMPLETE** on `main` at `b557347` through PR #17. Post-merge CI run `34321067413`
passed on that exact commit.

Deliver:
- source model.
- Keychain credential storage.
- Xtream-compatible adapter.
- M3U parser.
- local persistence.
- batch refresh.
- categories/search.

Exit gate:
- 50k+ synthetic item import/query benchmark documented.
- failures preserve last usable catalog.

Gate evidence:

- [Phase 2D persistence evidence](PHASE_2D_PERSISTENCE.md),
  [Phase 2E refresh evidence](PHASE_2E_REFRESH.md) and
  [Phase 2F library/search evidence](PHASE_2F_LIBRARY_SEARCH.md) document 50k and 100k synthetic
  import, refresh and query measurements.
- Phase 2E failure and cancellation coverage verifies that unsuccessful refreshes preserve the
  previously committed catalog. Phase 2F coverage verifies that staged replacement data remains
  invisible until atomic publication.

## Post-Phase 2 follow-up — Source and library application integration

Status: **COMPLETE**. This follow-up remains outside the approved Phase 2 deliverables and exit gate.
The Source Management & Validation Flows slice is **COMPLETE**, merged through PR #19 at merge
commit `1c94236`; post-merge CI run `34386676789` succeeded.

Planned scope:

- Source Management & Validation Flows — **COMPLETE**; merged through PR #19 at `1c94236`, with
  successful post-merge CI run `34386676789`.
- Refresh Scheduling & Policy — **COMPLETE**; merged through PR #21 at merge commit `18ba431`, with
  successful post-merge CI run `34449661574`. Per-source manual/6-hour/12-hour/daily policy, schema
  migration, deterministic sequential scheduling, active-app lifecycle integration and localized
  tvOS controls are complete.
- final tvOS/iOS browse and search UI composition over the production library query boundary —
  **COMPLETE**; merged through PR #24 at `1763189`, with successful post-merge CI run `34598275534`.
  Normal launch uses production composition; the
  shared presentation/paging boundary, platform-adapted screens, refresh invalidation, artwork,
  localization/accessibility and deterministic coverage are documented in
  [Production Library and Search UI](PRODUCTION_LIBRARY_UI.md) and
  [ADR-0012](../decisions/ADR-0012-production-library-ui-composition.md).

This follow-up does not change the Phase 3 playback scope or count as Phase 3 implementation.

## Phase 3 — Playback foundation

Status: **IMPLEMENTED; PHYSICAL APPLE TV EXIT GATE PENDING**.

Merged to `main` at `55e55a0` through PR #25. Post-merge CI run `34746573352` succeeded.

Deliver:
- PlaybackEngine abstraction — **IMPLEMENTED**.
- AVPlayer engine — **IMPLEMENTED**; native and only engine.
- tvOS and iOS/iPadOS system player UI — **IMPLEMENTED**.
- durable local progress tracking and bounded writes — **IMPLEMENTED**.
- safe finite-media resume and 95% completion — **IMPLEMENTED**.
- normalized errors and explicit fresh-resolution retry — **IMPLEMENTED**.
- lawful/synthetic compatibility fixture matrix — **IMPLEMENTED** for deterministic application
  behavior; physical media compatibility evidence remains pending.

Support boundary:

- committed M3U media URLs are supported without reclassifying `.unspecified` items.
- Xtream live/VOD playback is not yet supported because the persisted provider contract lacks a
  reviewed final playback path/container.
- series-level Xtream records are not playable because episode enumeration and resolution do not
  exist.
- no second engine, ATS relaxation, CloudKit progress sync, or guessed provider URL was added.

Evidence and exact semantics are recorded in
[ADR-0013](../decisions/ADR-0013-native-playback-foundation.md) and
[Playback Foundation](PLAYBACK_FOUNDATION.md).

Exit gate:
- real Apple TV playback validation — **PENDING**.

## Phase 4 — Cloud continuity

Status: **PHASE 4A WATCH PROGRESS FOUNDATION COMPLETE; PHASE 4B FAVORITES SYNC IMPLEMENTED;
ENTITLEMENT AND REAL-DEVICE GATES PENDING**.

Deliver:
- CloudKit private DB integration — **WATCH PROGRESS ADAPTER IMPLEMENTED; OWNER CONTAINER
  CONFIGURATION PENDING**.
- local-first progress/favorites — **WATCH PROGRESS AND FAVORITES IMPLEMENTED**.
- conflict resolution — **WATCH PROGRESS AND FAVORITES DETERMINISTICALLY TESTED**.
- iCloud unavailable mode — **WATCH PROGRESS CONTRACT AND TESTS IMPLEMENTED**.

Phase 4A is **IMPLEMENTED on main** and includes the versioned Watch Progress record, explicit Start Over generation, local-first
repository decorator, actor-isolated coordinator, bounded retry/cancellation, persisted custom-zone
change token, normalized account/service state, and injected private CloudKit adapter. It deliberately
does not add Favorites UI. Phase 4B is **IMPLEMENTED on main through PR #27 at `252d620`**; post-merge
CI `34783856312` succeeded. It adds a separate durable favorite repository,
versioned CloudKit favorite records, operation revisions, removal tombstones and restart-safe sync
metadata; a tombstone wins an equal-version add, while a later re-favorite advances the revision. See
[ADR-0014](../decisions/ADR-0014-cloudkit-watch-progress-sync.md) and
[Cloud Sync Design](CLOUD_SYNC.md).

Exit gate:
- Apple TV -> iPhone resume verified.
- iPhone -> Apple TV resume verified.
- offline/reconnect tests.

## Phase 5 — iPhone/iPad companion quality

Phase 5A Continue Watching is **IMPLEMENTED on main through PR #28 at `d9b5e3e`**; post-merge CI
`34873787230` succeeded. Real-device tvOS focus/RTL and iPhone/iPad validation remain pending.

Phase 5B Favorites UI is implemented locally on its feature branch with shared tests, platform
build/analyze gates and focused tvOS UI coverage passed. It composes local-first favorite identities
with committed catalog display metadata; it does not change Phase 4B CloudKit records, sync conflict
policy, catalog persistence or playback. The full tvOS UI suite remains a self-hosted CI gate;
physical Apple TV focus/RTL and physical iPhone/iPad validation remain pending.

Deliver:
- touch-adapted UI.
- Continue Watching.
- library/search/favorites.
- playback.
- source setup.

Exit gate:
- no tvOS-specific UI assumptions leaked into iOS.

## Phase 6 — Media experience

Candidates:
- EPG.
- subtitle/audio refinements.
- PiP where supported.
- autoplay next episode.
- Recently Added.
- improved metadata.

Each feature requires its own performance and compatibility check.

## Phase 7 — Hardening/TestFlight and commercial readiness

Deliver:
- crash/error cleanup.
- performance profiling.
- compatibility matrix expansion.
- accessibility pass.
- privacy/security review.
- TestFlight deployment.
- StoreKit 2 entitlement foundation.
- localized purchase/restore flows for English, German and Arabic.
- Free/Pro packaging decision.
- subscription/lifetime pricing decision based on launch economics.
- StoreKit sandbox/configuration testing and restore-purchase validation.
- App Store/legal review of the player-only commercial model.
- commercial design review confirming monetization does not degrade the premium UX.

Exit gate additions:
- commercial readiness checklist in `docs/MONETIZATION.md` passes before paid launch.
- premium design review confirms AEVYNO has an original identity and clearly exceeds the chosen
  competitive IPTV quality baseline in the reviewed experience.

## Later

- macOS.
- optional premium visual personalization only after the core design system is stable.
- profiles.
- downloads only if lawful and technically justified.
- recording/timeshift only after product/legal/technical design.
- second playback engine only after ADR gate.
