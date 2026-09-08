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
