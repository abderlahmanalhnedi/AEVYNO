# ADR-0004 — Phase 0 Project Structure and Deployment Baseline

Status: Accepted
Date: 2026-09-07

## Context

Phase 0 needs native tvOS and iOS applications while preserving independently testable
shared boundaries. The repository previously had no Xcode project, package or deployment
target. A minimum OS value is required for reproducible builds even though the final
distribution baseline has not been product-validated.

## Decision

- Use `AEVYNO.xcworkspace` with one native Xcode project for the tvOS and iOS app targets.
- Use the repository-root local Swift package for the Domain, IPTVCore, Library, Playback,
  Persistence, CloudSync, Security and DesignSystem modules.
- Keep platform UI under `App/tvOS` and `App/iOS`; share only the small Home view model under
  `App/Shared`.
- Use iOS 17.0 and tvOS 17.0 as the Phase 0 deployment baseline so the project can use the
  Observation framework and current native SwiftUI focus APIs without compatibility shims.
- Reassess the distribution minimum against the eventual device matrix before TestFlight.

## Consequences

Positive:
- shared boundaries compile and test independently of either app target.
- platform UI remains separate while Domain stays free of SwiftUI.
- no project-generation tool or third-party runtime dependency is introduced.

Tradeoffs:
- package and project settings must remain aligned when the deployment baseline changes.
- iOS/tvOS versions earlier than 17.0 are not supported by the Phase 0 project.
- the minimum OS decision remains subject to device/product validation before distribution.
