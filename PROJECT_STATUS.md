# Project Status

Last updated: 2026-09-08

## Current phase

**Phase 1 open with localization simulator foundation delivered; Phase 2A intact**

Phase 0 is complete in simulator. Its physical Apple TV validation remains pending because
the owner is currently away from the device; the Phase 0 roadmap exit allows this explicit
deferral. The existing Phase 1 shell has completed simulator hardening. Its Apple-native localization
foundation for English, German and Arabic now covers the current tvOS and iOS surfaces, and the
Arabic RTL Home, Detail and state flows have been simulator-validated. Phase 1 remains incomplete
until the real Apple TV UX review passes in both LTR and Arabic RTL.
By explicit owner direction, Phase 2 work that does not depend on physical Apple TV validation
has started in parallel. Phase 3 playback work has not started.

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
- Domain, IPTVCore, Library, Playback, Persistence, CloudSync, AEVYNOSecurity and DesignSystem
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
- simulator hardening prevents a memory-warning purge from being undone by artwork work
  already in flight, disables eager ImageIO source caching before downsampling, and adds
  deterministic LRU, cost, oversized-image, purge, malformed-data, full address-space ID
  uniqueness and simulator accessibility coverage.
- a shared Apple String Catalog provides complete English, German and Arabic values for current
  app-owned Home, Detail, loading, empty, error, Retry, preview-notice and accessibility text on
  tvOS and iOS/iPadOS, including the synthetic Phase 1 preview presentation.
- native SwiftUI layout direction drives Arabic RTL without manual string reversal, forced
  direction overrides, duplicated Arabic components or artwork/media-glyph mirroring. Stable media
  IDs continue to drive tvOS focus memory and restoration.

## Phase 2A source/security foundation

- Phase 2 development has started in parallel while Phase 1 remains open.
- source configuration models provide stable IDs, Xtream-compatible and M3U kinds,
  non-credential endpoint metadata, indirect credential references and enabled state.
- source configurations are value-semantic, Codable and Sendable, with no plaintext password
  or token fields and no dependency on SwiftUI or Keychain APIs.
- the `AEVYNOSecurity` package boundary provides an async credential-store protocol and an
  actor-isolated Apple Keychain implementation for username plus password/token-like material.
- Keychain items are device-local generic-password records using
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; raw Keychain status values and secrets are
  excluded from safe diagnostics.
- reusable exact-value and URL sanitization helpers redact sensitive diagnostic content.
- no provider networking, M3U parsing, catalog persistence, source-management UI or playback
  implementation is included in Phase 2A.

## Validation evidence

- shared package tests: 30 passed, 0 failed (`swift test`), including catalog completeness checks
  for English, German and Arabic and critical synthetic-preview coverage.
- generic tvOS Simulator build: passed.
- generic iOS Simulator build: passed.
- tvOS and iOS Xcode static analysis: passed.
- tvOS 26.5 Apple TV 4K (3rd generation) UI tests: 11 passed, 0 failed, covering the default
  English flow, German launch, and targeted Arabic RTL Home/Detail/state/focus behavior.
- simulator accessibility audits passed for loaded Home and Detail; Detail/back focus
  restoration passed three consecutive cycles on the selected card.
- Phase 1 Home and Detail were visually inspected at 4K simulator resolution.
- Arabic Home and Detail were visually inspected at 4K simulator resolution: native RTL placed
  the first rail item on the right, semantic alignment and button order reflowed correctly, mixed
  Arabic/Latin names and numeric metadata rendered without visible clipping or overlap, and media
  artwork plus the play glyph remained unmirrored. The iPhone 17 Pro iOS 26.5 Simulator companion
  shell was smoke-inspected in Arabic RTL with the same content-direction behavior.
- the 10k-address-space stress launch passed UI automation with stable initial focus; cache
  bounds and cancellation passed deterministic shared tests.
- physical Apple TV: **PENDING** because the owner is currently away from the device. No
  physical build, install, launch, focus, accessibility or UX observation was performed.
- physical iPhone/iPad: **NOT RUN**.

No frame-rate, interaction-latency or peak-memory numbers are claimed. Lazy containers,
bounded Home materialization and a bounded image cache are verified structurally and by
tests, while Instruments profiling and long-session focus review remain real-device work.

## Continuous integration

- A GitHub Actions CI foundation validates Pull Requests targeting `main`, pushes to `main`
  and manual dispatches on GitHub-hosted macOS 26 with explicitly selected Xcode 26.6.
- Blocking checks cover shared Swift tests, independent tvOS and iOS Simulator builds,
  tvOS and iOS static analysis, and the tvOS UI suite on an Apple TV 4K (3rd generation)
  tvOS 26.5 Simulator.
- A repository-wide Swift formatting baseline covers all 36 tracked Swift/package source and
  test files after Phase 2A. Strict `swift format lint` is clean locally and CI enforces it
  for Pull Requests, pushes to `main` and manual dispatches.
- Hosted CI health is reported only from actual GitHub Actions results. Main run `34200518183`
  confirmed the synchronized Phase 2A base at `c53ff99` green before localization implementation.
  Localization branch CI is recorded only after its Pull Request run.
- CI uses no signing identity, repository secret, Apple ID, provider credential or external
  runtime dependency. It does not replace physical Apple TV validation.
- Phase 1 remains physically **PENDING**. Phase 2A has started in parallel; Phase 2 is not
  complete, and Phase 3 has not started.

## Repository state

- The GitHub Actions CI foundation is defined in `.github/workflows/ci.yml`. Phase 2A was merged
  into `main` through PR #8 at `c53ff99`; the source/security foundation remains intact.
- Phase 1 localization work is isolated on `feature/phase-1-localization-rtl`, created from the
  synchronized and hosted-CI-green `c53ff99` base.
- Phase 1 simulator implementation and hardening are merged into `main` through PRs #3
  and #4. The physical Apple TV exit gate remains pending.
- Phase 0 is recorded in coherent source-of-truth, shared-foundation and
  native-application commits.
- Git author identity is configured locally by the repository owner.
- `origin` is configured for the project GitHub repository.
- Phase 0 was merged to `main` through PR #2 at `521888e`.

## Confirmed product decisions

- first-class interface languages: English, German and Arabic.
- Arabic is mandatory native RTL with premium typography, layout, focus and accessibility quality.
- Apple-native localization and system typography are the default; localization rules live in
  `docs/LOCALIZATION.md`.
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
on a physical Apple TV in both the base LTR experience and Arabic RTL. Include rapid directional
navigation, repeated open/back cycles and
a long stress-mode browsing session with Instruments. Resolve findings before marking Phase 1
complete.

In parallel, complete the remaining Phase 2 work: source validation flows, provider adapters,
M3U parsing, benchmark-driven local catalog persistence, refresh/import behavior, categories,
search and large-catalog performance evidence. These items remain outside Phase 2A. Do not begin
Phase 3 playback implementation before its approved phase gate.

## Active blockers

- No infrastructure/simulator blocker remains.
- The Phase 1 exit gate is pending because the physical Apple TV is currently unavailable
  to the owner. Pair/connect the Apple TV and select it as the AEVYNOTV run destination when
  the owner returns.

## Real-device validation status

Physical Apple TV: **PENDING — owner away from device; no Phase 1 real-device review run**.

Physical iPhone/iPad: **NOT RUN**.
