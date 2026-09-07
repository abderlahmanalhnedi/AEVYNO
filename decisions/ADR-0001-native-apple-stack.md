# ADR-0001 — Native Apple Stack

Status: Accepted
Date: 2026-09-07

## Context

The owner prioritizes design quality, performance and Apple-platform compatibility, especially tvOS.

## Decision

Use native Apple technologies as the primary stack:
- Swift.
- SwiftUI.
- AVFoundation/AVKit.
- Swift Concurrency.
- CloudKit.
- Keychain.

Do not use Flutter/React Native as the primary UI/application architecture.

## Consequences

Positive:
- best access to tvOS focus/remote/media capabilities.
- fewer abstraction layers.
- direct profiling with Apple tools.

Tradeoff:
- Apple-only codebase by design.
