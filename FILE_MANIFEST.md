# File Manifest

- `README.md` — project overview/index.
- `00_START_HERE_AR.md` — Arabic owner instructions.
- `CHATGPT_PROJECT_INSTRUCTIONS.md` — paste/use in ChatGPT Project instructions.
- `AGENTS.md` — mandatory Codex repository instructions.
- `FIRST_CODEX_PROMPT.md` — first implementation prompt.
- `PROJECT_STATUS.md` — living project state.
- `docs/PRODUCT_REQUIREMENTS.md` — product scope/MVP/quality.
- `docs/ARCHITECTURE.md` — module/data-flow architecture.
- `docs/DESIGN_SYSTEM.md` — tvOS/iOS UX rules.
- `docs/PERFORMANCE_BUDGET.md` — performance targets and anti-patterns.
- `docs/PLAYBACK_COMPATIBILITY.md` — AVFoundation-first compatibility strategy.
- `docs/CLOUD_SYNC.md` — CloudKit sync and conflicts.
- `docs/SECURITY_PRIVACY.md` — credentials/privacy/network rules.
- `docs/TEST_STRATEGY.md` — unit/integration/UI/performance/real-device testing.
- `docs/ROADMAP.md` — staged implementation plan.
- `docs/CODING_STANDARDS.md` — Swift/SwiftUI coding rules.
- `docs/GIT_WORKFLOW.md` — branch/commit/evidence discipline.
- `docs/DEFINITION_OF_DONE.md` — completion gates.
- `docs/CODEX_TASK_TEMPLATES.md` — reusable Codex prompt patterns.
- `docs/REFERENCES.md` — official OpenAI/Apple references.
- `decisions/ADR-0001-native-apple-stack.md` — accepted native stack decision.
- `decisions/ADR-0002-cloudkit-private-sync.md` — accepted CloudKit decision.
- `decisions/ADR-0003-local-first-library.md` — accepted local-catalog decision.
- `decisions/ADR-0004-phase-0-project-structure.md` — accepted Phase 0 project/module and
  provisional deployment-baseline decision.
- `codex-skill/apple-iptv-engineering/SKILL.md` — optional reusable Skill.
- `.gitignore` — build/secrets exclusions.
- `LICENSE_NOTE.md` — prevents accidental license choice.

## Phase 0 implementation

- `AEVYNO.xcworkspace/` — primary native Xcode workspace.
- `AEVYNO.xcodeproj/` — tvOS, iOS/iPadOS and tvOS UI-test targets and shared schemes.
- `AEVYNO.code-workspace` — VS Code workspace rooted only at this source-of-truth tree.
- `Package.swift` — local shared-module graph with no external dependencies.
- `App/tvOS/` — tvOS-first synthetic Home shell and native focus behavior.
- `App/iOS/` — touch-adapted iOS/iPadOS companion shell.
- `App/Shared/` — small shared Home view model.
- `Core/Domain/` — SwiftUI-independent Phase 0 media/Home models.
- `Core/Library/` — Home repository, use case, loader and deterministic mock content.
- `Core/IPTVCore/`, `Core/Playback/`, `Core/Persistence/`, `Core/CloudSync/` and
  `Core/Security/` — importable Phase 0 boundaries without production implementations.
- `DesignSystem/` — shared visual tokens, programmatic artwork, state presentation and
  tvOS-only focus treatment.
- `Tests/LibraryTests/` — deterministic shared foundation tests.
- `Tests/tvOSUITests/` — tvOS launch and directional-focus smoke test.
