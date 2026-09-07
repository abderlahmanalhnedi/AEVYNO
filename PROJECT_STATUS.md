# Project Status

Last updated: 2026-09-07

## Current phase

**Phase 1 — Premium tvOS shell active; simulator-validated development slice complete**

Phase 0 is complete in simulator. Its physical Apple TV validation remains pending because
the owner is currently away from the device; the Phase 0 roadmap exit allows this explicit
deferral. Phase 1 development has started and stopped at the simulator-validated stage.
Phase 1 is not complete because its real Apple TV UX review has not been performed.

## Verified development environment

- selected developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Xcode 26.6 (build 17F113).
- Swift 6.3.3.
- iOS 26.5 SDK and simulator runtime available; iOS 17.5 runtime also available.
- tvOS 26.5 SDK and simulator runtime available.
- Apple TV 4K (3rd generation), 1080p variant and Apple TV simulators available.

The former Command Line Tools / missing `simctl` blocker is resolved.

## Phase 0 delivered

- `AEVYNO.xcworkspace` and native `AEVYNO.xcodeproj`.
- `AEVYNOTV` and `AEVYNOiOS` shared schemes.
- Domain, IPTVCore, Library, Playback, Persistence, CloudSync, Security and DesignSystem
  local Swift package products.
- deterministic synthetic Home sections for Continue Watching, Movies, Series, Live TV
  and Favorites.
- shared loading, loaded, empty and safe error-state foundations.
- tvOS-first lazy rails, accessible cards, native focus state, restrained focus treatment
  and Reduce Motion support.
- touch-adapted iPhone/iPad companion shell without tvOS focus behavior.
- Swift Testing coverage for module imports, deterministic Home data and Home state logic.
- tvOS XCUITest coverage for launch, initial card focus and right-direction focus movement.

## Phase 1 simulator-validated development delivered

- original, cinematic Home hero and refined lazy rails for Continue Watching, Movies,
  Series, Live TV and Favorites.
- reusable landscape, poster and live card families with stable geometry, restrained focus
  scale, explicit live/progress semantics and synthetic artwork.
- native tvOS Detail presentation with title, metadata, concise description, accessibility
  semantics, a safe no-playback primary action and temporary demo-only secondary state.
- native `NavigationStack` and `FocusState` flow that remembers deterministic media IDs and
  restores focus to the opened card after returning from Detail in simulator UI automation.
- stable, non-focusable loading skeletons; intentional empty state; concise error state with
  a focusable Retry action.
- injected actor-isolated artwork pipeline with request cancellation, target-size synthetic
  rendering, ImageIO downsampling support, a 48 MiB default LRU memory bound and memory-
  warning purge behavior. No network artwork service or third-party dependency was added.
- deterministic 10k, 50k and 100k synthetic catalog address spaces. The tvOS stress mode
  materializes a bounded 800-item Home snapshot instead of retaining a full catalog in
  SwiftUI state.
- expanded shared and tvOS UI automation for Detail, navigation/focus restoration, safe
  placeholder action, Home states, cache bounds/cancellation and fixture determinism.

## Validation evidence

- shared package tests: 9 passed, 0 failed (`swift test`).
- generic tvOS Simulator build: passed.
- generic iOS Simulator build: passed.
- tvOS and iOS Xcode static analysis: passed.
- tvOS 26.5 Apple TV 4K (3rd generation) UI tests: 6 passed, 0 failed.
- Phase 1 Home and Detail were visually inspected at 4K simulator resolution.
- the 10k-address-space stress launch passed UI automation with stable initial focus; cache
  bounds and cancellation passed deterministic shared tests.
- physical Apple TV: **PENDING** because the owner is currently away from the device. No
  physical build, install, launch, focus, accessibility or UX observation was performed.
- physical iPhone/iPad: **NOT RUN**.

No frame-rate, interaction-latency or peak-memory numbers are claimed. Lazy containers,
bounded Home materialization and a bounded image cache are verified structurally and by
tests, while Instruments profiling and long-session focus review remain real-device work.

## Repository state

- Phase 1 work is on `feature/phase-1-premium-tvos-shell`, created from merged `main` at
  `521888e`.
- Phase 0 is recorded in coherent source-of-truth, shared-foundation and
  native-application commits.
- Git author identity is configured locally by the repository owner.
- `origin` is configured for the project GitHub repository.
- Phase 0 was merged to `main` through PR #2 at `521888e`.

## Confirmed product decisions

- Native Apple stack.
- tvOS primary.
- iOS/iPadOS companion.
- macOS later.
- Swift + SwiftUI.
- AVFoundation/AVKit first playback engine.
- CloudKit private database for lightweight user sync.
- secrets in Keychain, not CloudKit.
- local catalog cache; do not synchronize the full IPTV catalog to iCloud.
- no bundled content.
- original design; no IPTVX cloning.
- top priorities: design, speed, compatibility.

## Not yet decided

- final app/product name.
- final distribution minimum OS versions; Phase 0 provisionally targets iOS/tvOS 17.0
  under ADR-0004 and must be reassessed before TestFlight.
- exact local persistence implementation after benchmark spike.
- whether a fallback playback engine is needed.
- EPG storage/index strategy after real provider fixtures are profiled.
- TestFlight/App Store distribution timing.

## Next milestone

Run the Phase 1 Home, Detail, focus-restoration, accessibility and Reduce Motion checklist
on a physical Apple TV. Include rapid directional navigation, repeated open/back cycles and
a long stress-mode browsing session with Instruments. Resolve findings before marking Phase
1 complete. Do not start Phase 2 until the Phase 1 exit gate passes.

## Active blockers

- No implementation or simulator blocker remains.
- The Phase 1 exit gate is pending because the physical Apple TV is currently unavailable
  to the owner. Pair/connect the Apple TV and select it as the AEVYNOTV run destination when
  the owner returns.

## Real-device validation status

Physical Apple TV: **PENDING — owner away from device; no Phase 1 real-device review run**.

Physical iPhone/iPad: **NOT RUN**.
