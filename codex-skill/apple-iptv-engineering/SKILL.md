---
name: apple-iptv-engineering
description: Build, review, debug, and optimize the Apple IPTV Client using strict tvOS-first native Apple engineering rules for design quality, performance, playback compatibility, CloudKit continuity, security, testing, and evidence-based completion.
---

# Apple IPTV Engineering Skill

## Use this skill when

The task changes or reviews this project's:
- Swift/SwiftUI code.
- tvOS/iOS UI.
- IPTV parsing/import.
- playback.
- CloudKit sync.
- Keychain/security.
- local persistence/search.
- performance.
- test strategy.
- architecture.

## Required inputs

Before work, read:
1. repository `AGENTS.md`.
2. `PROJECT_STATUS.md`.
3. relevant `docs/*.md` files.
4. applicable ADRs under `decisions/`.
5. the requested code path and its tests.

## Workflow

### Step 1 — Audit

- inspect git status/branch.
- inspect existing implementation.
- identify the smallest vertical slice.
- identify compatibility/security/performance risks.
- define acceptance criteria.

### Step 2 — Design before code

Confirm the task does not violate these invariants:
- native Apple stack.
- tvOS first.
- UI does not own provider parsing, CloudKit or Keychain logic.
- secrets never enter logs/CloudKit.
- full catalog remains local.
- AVFoundation remains first playback engine.
- no unapproved large dependency.
- original UI; no IPTVX cloning.

If an invariant must change, create an ADR before implementation.

### Step 3 — Implement minimally

- preserve module boundaries.
- use structured concurrency.
- keep heavy work off main actor.
- preserve local usable state during network refresh failures.
- use stable media IDs.
- add/update tests with behavior.

### Step 4 — Validate

Run applicable:
- target build.
- unit tests.
- UI tests.
- performance fixture/benchmark.
- static/lint checks configured by repo.

Do not claim real Apple TV validation unless a physical device was used.

### Step 5 — Close out

Check:
- no secrets in diff.
- no unrelated files changed.
- docs/ADR/status updated if needed.
- build/test evidence recorded.
- remaining device validation/risk clearly listed.

## Required response format

Return these sections:
1. Summary
2. Files changed
3. Build/test evidence
4. Performance impact
5. Compatibility impact
6. Security/privacy impact
7. Physical-device validation status
8. Known limitations/risks
9. Next recommended task

## Hard stops

Do not silently:
- add Flutter/React Native.
- add VLC/FFmpeg.
- disable ATS globally.
- store passwords/tokens in CloudKit.
- bundle copyrighted IPTV content.
- copy IPTVX assets/code/layouts.
- migrate architecture/data model broadly.
- claim performance without measurement.
