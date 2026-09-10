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

Status: **STARTED**. This follow-up remains outside the approved Phase 2 deliverables and exit gate.
The Source Management & Validation Flows slice is **COMPLETE**, merged through PR #19 at merge
commit `1c94236`; post-merge CI run `34386676789` succeeded.

Planned scope:

- Source Management & Validation Flows — **COMPLETE**; merged through PR #19 at `1c94236`, with
  successful post-merge CI run `34386676789`.
- Refresh Scheduling & Policy — **IMPLEMENTED; UNDER FINAL VALIDATION/REVIEW**. Per-source
  manual/6-hour/12-hour/daily policy, schema migration, deterministic sequential scheduling,
  active-app lifecycle integration and localized tvOS controls are implemented; merge and
  post-merge reconciliation remain pending.
- final tvOS/iOS browse and search UI composition over the production library query boundary —
  **NOT STARTED**.

This follow-up does not change the Phase 3 playback scope or count as Phase 3 implementation.

## Phase 3 — Playback foundation

Deliver:
- PlaybackEngine abstraction.
- AVPlayer engine.
- player UI.
- progress tracking.
- resume.
- errors/retry.
- compatibility fixture matrix.

Exit gate:
- real Apple TV playback validation.

## Phase 4 — Cloud continuity

Deliver:
- CloudKit private DB integration.
- local-first progress/favorites.
- conflict resolution.
- iCloud unavailable mode.

Exit gate:
- Apple TV -> iPhone resume verified.
- iPhone -> Apple TV resume verified.
- offline/reconnect tests.

## Phase 5 — iPhone/iPad companion quality

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
