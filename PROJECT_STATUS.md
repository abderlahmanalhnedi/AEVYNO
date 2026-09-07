# Project Status

Last updated: 2026-09-07

## Current phase

**Phase 0 — Foundation complete in simulator; physical-device validation pending**

The AEVYNO repository is now the source of truth. It contains a native Xcode workspace,
tvOS and iOS/iPadOS app targets, shared Swift package boundaries, an original synthetic
Home foundation and automated tests. No Phase 1 work has started.

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

## Validation evidence

- shared package tests: 4 passed, 0 failed (`swift test`).
- generic tvOS Simulator build: passed.
- generic iOS Simulator build: passed.
- tvOS 26.5 Apple TV 4K (3rd generation) UI test: 1 passed, 0 failed.
- tvOS and iPhone 17 Pro simulator launches: visually inspected.
- physical Apple TV: **NOT RUN**.
- physical iPhone/iPad: **NOT RUN**.

No performance numbers are claimed; Phase 0 uses bounded synthetic data and lazy UI
containers, but real-device profiling and large-catalog fixtures belong to later work.

## Repository state

- Git was initialized locally and work is on `feature/phase-0-foundation`.
- Phase 0 is recorded in coherent source-of-truth, shared-foundation and
  native-application commits.
- Git author identity is configured locally by the repository owner.
- no remote was created and nothing was pushed or published.

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

Run the Phase 0 Home and focus/accessibility checklist on a physical Apple TV, including
rapid directional navigation and Reduce Motion. Address only Phase 0 findings before
starting the Phase 1 premium shell.

## Active blockers

- No implementation or simulator blocker remains.
- Physical-device UX validation remains outstanding.

## Real-device validation status

Physical Apple TV: **NOT RUN**.

Physical iPhone/iPad: **NOT RUN**.
