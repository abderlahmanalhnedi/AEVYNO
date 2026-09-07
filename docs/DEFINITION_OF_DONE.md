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

## Documentation

- `PROJECT_STATUS.md` updated for milestone completion/blockers.
- ADR updated/added if needed.
- relevant docs changed with implementation.

## Completion statement

Codex must state what was actually verified and what remains unverified. Simulator success must not be described as real-device success.
