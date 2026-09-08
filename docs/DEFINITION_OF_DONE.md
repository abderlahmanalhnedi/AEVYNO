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

## Security

- no secrets in code/logs/tests.
- URLs redacted where needed.
- no global ATS weakening.

## Tests

- affected target builds.
- relevant automated tests pass.
- tests added/updated for new logic.

## tvOS

- focus behavior considered.
- remote navigation considered.
- physical Apple TV validation recorded for milestone-critical UX/playback/performance work.

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

- `PROJECT_STATUS.md` updated for milestone completion/blockers.
- ADR updated/added if needed.
- relevant docs changed with implementation.

## Completion statement

Codex must state what was actually verified and what remains unverified. Simulator success must not be described as real-device success.
