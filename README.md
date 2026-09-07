# Apple IPTV Client — Project Context Pack

Working title only. The final product name is intentionally undecided.

This repository/context pack defines the source of truth for building a premium, native Apple IPTV/media client with tvOS as the primary platform and iPhone/iPad as companion platforms.

## Core priorities — in this order

1. **Design quality** — premium Apple-native experience, especially on tvOS.
2. **Performance** — instant-feeling navigation, bounded memory, asynchronous data work, fast playback start.
3. **Compatibility and reliability** — resilient playback, large libraries, varied providers, real-device testing.
4. **Cross-device continuity** — Continue Watching, favorites and selected settings synchronized through iCloud/CloudKit.
5. **Maintainability** — modular architecture, measurable behavior, tests, ADRs, minimal dependencies.

## Interface languages

AEVYNO treats localization as a product-quality requirement from the foundation:

- English.
- German.
- Arabic with first-class native RTL support.

Arabic must receive the same premium design, focus, accessibility and testing quality as the LTR
interfaces. See `docs/LOCALIZATION.md`.

## Start here

- Arabic owner guide: `00_START_HERE_AR.md`
- Codex mandatory instructions: `AGENTS.md`
- ChatGPT Project instructions: `CHATGPT_PROJECT_INSTRUCTIONS.md`
- Product requirements: `docs/PRODUCT_REQUIREMENTS.md`
- Architecture: `docs/ARCHITECTURE.md`
- Design rules: `docs/DESIGN_SYSTEM.md`\n- Localization / Arabic RTL: `docs/LOCALIZATION.md`
- Performance rules: `docs/PERFORMANCE_BUDGET.md`
- Playback compatibility: `docs/PLAYBACK_COMPATIBILITY.md`
- Cloud sync: `docs/CLOUD_SYNC.md`
- Security/privacy: `docs/SECURITY_PRIVACY.md`
- Testing: `docs/TEST_STRATEGY.md`
- Roadmap: `docs/ROADMAP.md`
- Coding standards: `docs/CODING_STANDARDS.md`
- Git workflow: `docs/GIT_WORKFLOW.md`
- Definition of Done: `docs/DEFINITION_OF_DONE.md`
- First Codex task: `FIRST_CODEX_PROMPT.md`
- Project status: `PROJECT_STATUS.md`
- Decisions: `decisions/`
- Optional Codex/Agent Skill: `codex-skill/apple-iptv-engineering/SKILL.md`

## Product boundary

This app is a **media player/client**. It must not ship bundled channels, movies, series, copyrighted playlists, provider credentials, scraping logic for unauthorized catalogs, DRM bypasses, or piracy-enabling features. Users provide their own lawful media sources and credentials.

## Technology baseline

- Swift
- SwiftUI
- AVFoundation / AVKit
- CloudKit private database
- Keychain for secrets
- Core Data or another Apple-native/local persistence implementation behind an abstraction
- Swift Concurrency
- XCTest / Swift Testing where suitable; XCUITest for critical UI journeys
- Xcode latest stable supported by the project

No cross-platform UI framework is allowed for the primary app.

## Phase 0 developer entry point

Open `AEVYNO.xcworkspace` in Xcode. The shared schemes are:

- `AEVYNOTV` for the primary tvOS application and focus smoke test.
- `AEVYNOiOS` for the iPhone/iPad companion shell.

Shared boundaries are native Swift package products rooted in `Package.swift`. Run their
deterministic foundation tests with `swift test`.
