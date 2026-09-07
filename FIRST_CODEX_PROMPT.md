# First Codex Prompt

Read `AGENTS.md`, `PROJECT_STATUS.md`, all files under `docs/`, and the existing ADRs before changing anything.

Perform a read-only repository audit first. Then implement **Phase 0 foundation only**. Do not implement IPTV provider integration or real playback yet.

## Goal

Create a clean, native Apple project foundation for a premium IPTV/media client with tvOS as the primary target and iOS/iPadOS as a companion target.

## Required outcome

1. Create an Xcode project/workspace that builds with the latest stable toolchain available in the environment.
2. Add tvOS app target.
3. Add iOS/iPadOS app target.
4. Establish shared modules/packages for:
   - Domain
   - IPTVCore
   - Library
   - Playback
   - Persistence
   - CloudSync
   - Security
   - DesignSystem
5. Keep platform-specific UI in the app targets.
6. Add a minimal original Home screen with synthetic/mock sections only:
   - Continue Watching
   - Movies
   - Series
   - Live TV
   - Favorites
7. On tvOS, implement a deliberate focus state for cards using native focus behavior.
8. Add unit-test targets and at least one smoke/unit test proving the shared foundation can be imported and executed.
9. No third-party dependencies.
10. No real IPTV credentials, URLs or copyrighted content.
11. No CloudKit schema yet beyond the capability/foundation only if it can be added safely without requiring unavailable signing resources. If signing blocks it, document the exact blocker and leave code buildable.
12. Do not add a second playback engine.
13. Do not add networking code that is not needed for Phase 0.

## Validation

Run the strongest build/test commands available in the environment for the targets you create. Report exact commands and results. Do not claim physical Apple TV validation.

## Documentation

Update `PROJECT_STATUS.md` with completed work, remaining blockers, and the next recommended milestone. If you make any architectural decision not already covered by an ADR, add a new ADR.

## Completion format

Return:
- Summary
- Files changed
- Build/test evidence
- Architecture notes
- tvOS focus notes
- Known limitations
- Real-device validation still required
- Next milestone
