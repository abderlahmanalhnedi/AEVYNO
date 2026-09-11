# Delivery Efficiency Policy

Status: **ACTIVE BASELINE**

This policy reduces repeated delivery work without weakening AEVYNO's quality, security, localization, playback, or real-device gates.

## Fixed baseline rules

1. **One coherent feature or fix = one Pull Request.**
   - The implementation PR must include the code, relevant tests, documentation, ADR changes when required, and `PROJECT_STATUS.md` / roadmap updates needed to describe completion.
   - Do not create a second status-only PR merely to mark the just-merged feature complete.
   - A follow-up documentation PR is justified only to correct a factual error, resolve a real conflict, or document information that was genuinely unavailable before merge.

2. **Validation is proportional to risk and affected surface.**
   - Run the smallest validation set that can credibly prove the change.
   - Skipping an irrelevant expensive check is allowed; the completion summary must state why it was not applicable.

3. **Documentation-only changes use a lightweight path.**
   - Required: `git diff --check`, Markdown structure/basic relative-link validation, and repository status consistency where relevant.
   - Not required by default: Xcode build, static analysis, simulator UI tests, performance benchmarks, or physical-device validation.

4. **Backend/domain/data changes use focused engineering validation.**
   - Run relevant Swift tests and build affected application targets when integration can be impacted.
   - Do not run unrelated UI suites unless the changed contract can affect UI behavior.
   - Security, persistence, migrations, atomic refresh, and credential changes keep their dedicated regression coverage.

5. **User-facing UI changes use targeted UI validation.**
   - Build affected targets.
   - Run the relevant navigation/focus/localization/accessibility tests for the changed screen or flow.
   - Arabic RTL remains mandatory for milestone-critical user-facing changes.
   - Full unrelated UI journeys are not required for every small visual change.

6. **Full validation is reserved for high-risk or milestone work.**
   Run the complete relevant CI/test matrix for:
   - phase/roadmap exit gates,
   - playback-engine or playback-state changes,
   - security/credential changes with broad impact,
   - persistence schema/migration or corruption-risk changes,
   - CloudKit conflict/synchronization changes,
   - large cross-module refactors,
   - pre-TestFlight / pre-release validation,
   - any change where focused validation leaves material uncertainty.

7. **Large-catalog benchmarks are evidence, not ceremony.**
   - 10k/50k/100k benchmarks are required when import, refresh, persistence, search/query, image pipeline, playback startup, or another performance-sensitive path changes materially.
   - Do not rerun them for documentation-only or unrelated UI/settings work.

8. **Physical Apple TV validation is milestone-driven.**
   - Required for roadmap gates and milestone-critical tvOS UX, focus, playback, lifecycle, performance, or compatibility claims.
   - Do not repeat a full physical-device checklist after changes that cannot affect those behaviors.
   - Simulator success must never be reported as physical-device success.

9. **Diagnostics should be useful, not noisy.**
   - Normal successful CI should keep concise toolchain output.
   - Expanded simulator/SDK/environment diagnostics should be used for manual diagnostic runs or when a failure needs investigation.

10. **Automation must preserve quality gates.**
    - Never skip security redaction, Keychain boundaries, Arabic RTL requirements, last-known-good/atomic catalog guarantees, or playback compatibility evidence just to make CI faster.
    - Optimization is allowed only when the omitted work is demonstrably irrelevant to the change.

## Delivery target

Prefer fewer, more complete PRs with focused evidence. AEVYNO should spend engineering time on product capability and meaningful risk reduction rather than repeated status-only commits or unrelated validation runs.
