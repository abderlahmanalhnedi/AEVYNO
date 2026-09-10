# Definition of Done

A change is done only when all applicable gates pass.

## Functional

- acceptance criteria met.
- error/empty/loading paths handled.
- no known data corruption path introduced.

## Architecture

- respects module boundaries.
- no accidental direct UI -> CloudKit/Keychain/provider coupling.
- architecture decision documented if applicable.

## Performance

- no obvious main-thread heavy work.
- large-list behavior considered.
- relevant benchmark/profile run for performance-sensitive work.
- 10k/50k/100k benchmarks are not ceremonial; rerun them only when a performance-sensitive path materially changes.

## Security

- no secrets in code/logs/tests.
- URLs redacted where needed.
- no global ATS weakening.
- security, Keychain, credential, persistence-integrity, and last-known-good guarantees are never skipped merely to shorten CI.

## Tests

- affected target builds.
- relevant automated tests pass.
- tests added/updated for new logic.
- validation scope is proportional to the risk and affected surface.

### Validation proportionality

- documentation-only: `git diff --check`, Markdown/basic relative-link checks, and status consistency where relevant; Xcode builds, UI tests, performance benchmarks, and device validation are not required by default.
- backend/domain/data: relevant Swift tests plus affected app builds when integration can be impacted; unrelated UI suites are not required unless the changed contract can alter UI behavior.
- user-facing UI: affected builds plus targeted navigation/focus/localization/accessibility coverage; Arabic RTL remains mandatory for milestone-critical user-facing work.
- full validation: phase gates, playback changes, broad security changes, persistence migrations/corruption-risk work, CloudKit conflict/sync changes, large cross-module refactors, and pre-TestFlight/pre-release work.
- any intentionally omitted expensive check must be reported as not applicable with a concise reason.

Read `DELIVERY_EFFICIENCY.md` for the fixed baseline.

## tvOS

- focus behavior considered.
- remote navigation considered.
- physical Apple TV validation recorded for milestone-critical UX/playback/performance work.
- a full physical-device checklist is not repeated for changes that cannot affect those behaviors.

## Design quality

For user-facing milestone work:
- design remains original.
- no copied competitive assets/layouts/text.
- premium-state quality includes loading, empty and error states.
- Arabic RTL receives equivalent polish.
- where a competitive review is applicable, improvements are stated in observable terms rather than
  unsupported claims that the design is "better".

## Commercialization

For monetization-related work:
- entitlement logic is separated from view code.
- purchase/restore/error states are tested.
- prices are not hard-coded when StoreKit-provided pricing is available.
- monetization does not introduce intrusive advertising or weaken the player-only legal boundary.
- then-current App Store requirements are reviewed before launch.

## Documentation

- `PROJECT_STATUS.md` updated for milestone completion/blockers in the same implementation PR whenever the information is already known.
- roadmap status updated in the same PR when applicable.
- ADR updated/added if needed.
- relevant docs changed with implementation.
- do not create a routine follow-up status-only PR after a feature merge.

## Completion statement

Codex must state what was actually verified and what remains unverified. Simulator success must not be described as real-device success.
