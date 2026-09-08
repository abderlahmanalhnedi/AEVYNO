# AGENTS.md — Mandatory Codex Instructions

## 1. Scope and authority

These instructions apply to the entire repository unless a deeper `AGENTS.md` explicitly overrides a narrow subtree.

Instruction priority:
1. Explicit current user request.
2. This `AGENTS.md`.
3. Approved ADRs in `decisions/`.
4. Product/architecture/security/testing documents in `docs/`.
5. Existing implementation patterns.

If two project documents conflict, stop changing architecture and surface the conflict in the task summary. Do not silently choose one.

## 2. Product mission

Build a premium, native Apple IPTV/media client with:
- tvOS as the primary experience.
- iPhone/iPad as companion experiences.
- fast local browsing of large catalogs.
- reliable playback.
- cross-device Continue Watching and favorites through iCloud.
- original Apple-native design.

Non-negotiable priority order:
1. Design quality.
2. Performance.
3. Compatibility/reliability.
4. Cross-device continuity.
5. Maintainability.

A feature that damages a higher priority must not ship merely to increase feature count.

AEVYNO is intended to become a commercial product. Monetization must not reduce design quality,
performance, compatibility, privacy or the lawful player-only product boundary.

## 3. Mandatory startup protocol for every engineering task

Before editing code:
1. Read this file.
2. Read `PROJECT_STATUS.md`.
3. Read the relevant documents under `docs/` and any applicable ADRs.
4. Inspect `git status` and current branch.
5. Inspect the code path related to the request before proposing a rewrite.
6. Define a small implementation slice and explicit acceptance criteria.
7. Identify which validation can be automated and which needs a real Apple TV/device.

Do not start with mass refactors.

## 4. Platform and technology rules

### MUST use/prefer
- Swift.
- SwiftUI for app UI.
- AVFoundation/AVKit as the default playback stack.
- Swift Concurrency (`async/await`, actors) for asynchronous work.
- CloudKit private database for eligible synchronized user state.
- Keychain for credentials/secrets.
- Apple-native local persistence behind repository abstractions.
- Structured logging with sensitive-data redaction.

### MUST NOT introduce without an approved ADR
- Flutter.
- React Native.
- Electron.
- webview-first application architecture.
- FFmpeg.
- VLC/MobileVLCKit.
- large networking/database frameworks.
- global service locator.
- global mutable singleton state.
- new backend/server dependency.

A dependency is not justified by "it is easier". It must solve a demonstrated problem and pass licensing, binary-size, maintenance, security and performance review.

## 5. Architecture rules

Keep platform UI separate from reusable domain/data services.

Expected conceptual modules:
- `App/tvOS`
- `App/iOS`
- `Core/Domain`
- `Core/IPTV`
- `Core/Library`
- `Core/Playback`
- `Core/Persistence`
- `Core/CloudSync`
- `Core/Security`
- `DesignSystem`

Rules:
- UI must not parse M3U/XMLTV/Xtream responses directly.
- UI must not access CloudKit directly.
- UI must not access Keychain directly.
- Networking must not write view state directly.
- Domain models must not depend on SwiftUI.
- Persistence implementations must sit behind protocols/interfaces.
- Playback engine must be behind a `PlaybackEngine`-style abstraction so compatibility fallbacks can be added later without rewriting screens.
- Avoid inheritance-heavy designs. Prefer composition and protocols where useful.
- Keep views small. Split complex views by responsibility, not arbitrary line count.

## 6. Main-thread and concurrency rules

Never perform these on the main actor:
- playlist parsing.
- XMLTV parsing.
- large JSON decoding.
- database imports.
- image decoding/caching work that can be off-main.
- CloudKit/network waits.
- bulk search indexing.

Use actors or other safe isolation for mutable shared state.

Do not use detached tasks casually. Explain why a task needs detached execution.

No blocking semaphores around async APIs.

## 7. Performance rules

Every list/grid must support large datasets without eager creation of all cells.

Forbidden:
- loading the full remote catalog into SwiftUI state.
- reparsing the entire provider catalog on every launch if a valid local cache exists.
- unbounded image caches.
- synchronous disk/network access on the main thread.
- accidental N+1 remote requests per row/card.
- saving playback progress to CloudKit every second.

Performance-sensitive changes require measurement or a benchmark plan. Never claim "fast" without evidence.

Read `docs/PERFORMANCE_BUDGET.md`.

## 8. tvOS UX rules

The Apple TV experience is not an enlarged iPhone UI.

Mandatory:
- focus behavior is a first-class design concern.
- every actionable element has a clear focus state.
- directional movement should be predictable.
- focus must restore sensibly after returning from details/player.
- Siri Remote interactions must not require precision pointer behavior.
- avoid dense settings-style screens for primary browsing.
- critical UI must remain legible at TV viewing distance.
- loading states must not steal focus.
- errors must offer a useful next action.

Do not use custom focus hacks if native focus behavior solves the problem.

## 9. Design rules

The product may learn from the quality bar of IPTVX, Apple TV and premium streaming apps, but it must not clone them.

Forbidden:
- copied assets.
- copied branding.
- pixel-identical screens.
- copied proprietary text/content.
- reverse-engineered private implementation.

Use the project design system and Apple interaction conventions.

The competitive design target is to clearly exceed the perceived IPTVX quality bar while remaining
fully original. Never treat IPTVX as a screen specification. Do not copy its layout, visual tokens,
assets, text or private implementation. Prefer measurable improvements in focus, responsiveness,
RTL, accessibility, state design and coherence.

Read `docs/DESIGN_SYSTEM.md`.

## 10. Localization and Arabic RTL rules

The first-class interface languages are English, German and Arabic.

Arabic is mandatory first-class RTL support, not a late translation pass.

For user-facing UI:

- use Apple-native localization and String Catalogs where appropriate.
- use semantic leading/trailing alignment; do not hard-code left/right layout assumptions.
- use Apple system typography by default, including native Arabic font behavior.
- do not manually reverse Arabic strings or add bidirectional layout hacks.
- do not add a custom Arabic font without explicit design, shaping, licensing and performance review.
- preserve tvOS focus predictability and focus restoration under RTL.
- test long Arabic strings, Arabic/Latin mixed metadata and localized accessibility labels.
- provider content may be in any language and must not be forcibly translated or reordered.
- a milestone-critical tvOS screen is not localization-complete until Arabic RTL has been reviewed
  on simulator and, when required by the roadmap gate, physical Apple TV.

Read `docs/LOCALIZATION.md` and `docs/DESIGN_SYSTEM.md`.

## 11. Playback compatibility rules

AVPlayer/AVFoundation is the primary engine.

Do not add a second engine preemptively.

Before adding a fallback engine:
1. maintain a reproducible compatibility fixture/corpus.
2. demonstrate a material group of legitimate streams that fail with AVFoundation.
3. document failure signatures.
4. create an ADR comparing alternatives, licenses, App Store impact, binary size and maintenance.
5. keep the player UI independent of the engine.

Never implement DRM bypassing, stream theft, credential harvesting, or unauthorized content extraction.

Read `docs/PLAYBACK_COMPATIBILITY.md`.

## 12. iCloud and persistence rules

CloudKit is not the main media catalog database.

CloudKit private data may include:
- watch progress.
- favorites.
- watch history metadata.
- hidden categories/user preferences.
- non-secret source metadata where appropriate.

CloudKit must NOT contain:
- provider passwords.
- provider tokens unless an explicit approved security design says otherwise.
- full imported catalog unless a future ADR proves a need.
- large poster caches.
- full EPG datasets.

Credentials belong in Keychain.

Local catalog data is cacheable/rebuildable and should live locally.

Read `docs/CLOUD_SYNC.md` and `docs/SECURITY_PRIVACY.md`.

## 13. Networking and security rules

- Prefer HTTPS.
- Never globally disable App Transport Security merely to support one provider.
- Any HTTP-media support must be narrowly scoped, documented and tested against current Apple platform capabilities.
- Redact usernames, passwords, tokens and sensitive query parameters from logs.
- Never commit real provider URLs/credentials.
- Test fixtures must use synthetic/demo data.
- Do not log full playlist lines when they can contain credentials.
- No secrets in source, xcconfig committed files, screenshots or sample plist files.

## 14. Error handling rules

No silent failures.

Production code must not use `fatalError`, `preconditionFailure`, or force unwraps as normal control flow.

Errors shown to users must be actionable and non-technical where possible. Diagnostic detail belongs in structured logs, redacted of secrets.

Network/media failures should distinguish at least:
- authentication failure.
- unreachable provider.
- timeout.
- unsupported media.
- malformed playlist/provider response.
- expired URL/session.
- CloudKit unavailable/account missing.

## 15. Testing rules

For every behavior change, add/update the smallest appropriate test.

Minimum layers:
- parser unit tests.
- repository/persistence tests.
- Cloud sync conflict-resolution tests.
- playback state/progress tests.
- UI tests for critical navigation journeys.
- performance fixtures for large catalogs.

A simulator passing does not prove physical Apple TV behavior.

Never state that real-device behavior passed unless a physical device was used.

Read `docs/TEST_STRATEGY.md`.

## 16. Source-control rules

- Do not work directly on protected `main` when a feature branch is expected.
- Use focused branches: `feature/...`, `fix/...`, `perf/...`, `docs/...`.
- Do not mix unrelated refactors with feature work.
- Do not rewrite history unless explicitly requested.
- Preserve user changes in a dirty worktree.
- Do not delete files you do not understand.
- Update `PROJECT_STATUS.md` for completed milestones or important blockers.
- Add an ADR for architecture-level decisions.

Read `docs/GIT_WORKFLOW.md`.

## 17. Definition of Done gate

A task is not complete merely because code was written.

Before declaring completion:
1. build the affected target(s).
2. run relevant tests.
3. run lint/static checks if configured.
4. verify no secrets entered the diff.
5. verify no unrelated files changed.
6. update tests.
7. update docs/ADR/status when required.
8. state what was verified on simulator vs real device.
9. list remaining known risks honestly.

Read `docs/DEFINITION_OF_DONE.md`.

## 18. Monetization rules

The preferred direction is a premium freemium product with AEVYNO Pro and possible recurring and
lifetime purchase options.

Engineering rules:
- no intrusive advertising in Home, library or playback.
- commerce logic must sit behind a dedicated entitlement/service boundary.
- prefer StoreKit 2 when commerce implementation begins.
- do not hard-code product prices into UI copy.
- purchase/restore states must be localizable and testable.
- do not start monetization implementation merely because documentation exists; follow the roadmap gate.
- verify then-current App Store policy before shipping paid features.
- never sell or bundle IPTV channels, copyrighted catalogs, provider accounts or piracy access.

Read `docs/MONETIZATION.md`.

## 19. Documentation discipline

Architecture changes require an ADR.

Behavioral assumptions must not live only in chat history. Put durable decisions in the repository.

When a documented rule becomes obsolete, update the document in the same change that replaces it.

## 20. Codex communication style

For each task, return a concise engineering summary containing:
- what changed.
- files changed.
- tests/build commands run and results.
- performance implications if relevant.
- compatibility implications if relevant.
- real-device validation still required.
- any new ADR or documented decision.

Do not overclaim success.
