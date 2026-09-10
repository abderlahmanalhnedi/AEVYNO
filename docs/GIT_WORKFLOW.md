# Git Workflow

## Branching

Use focused branches:
- `feature/<topic>`
- `fix/<topic>`
- `perf/<topic>`
- `refactor/<topic>`
- `docs/<topic>`

Keep `main` releasable/buildable.

## Commits

Prefer coherent commits with clear messages, for example:
- `feat(tvOS): add focused poster card component`
- `perf(library): batch catalog imports`
- `fix(playback): persist progress on player exit`
- `docs(adr): choose CloudKit private sync model`

## Rules for Codex

- inspect `git status` before editing.
- never erase unrelated user work.
- do not amend/rebase unless explicitly requested.
- do not commit secrets.
- do not commit DerivedData/build outputs.
- keep generated code to the minimum required.
- show changed files in completion summary.
- follow `DELIVERY_EFFICIENCY.md` when selecting validation scope.

## One coherent change = one Pull Request

A feature or fix PR should contain everything needed to make that change complete:
- implementation.
- relevant tests.
- documentation and ADR updates when applicable.
- `PROJECT_STATUS.md` and roadmap status updates when the change completes or materially changes a milestone.

Do not create a second PR only to mark the just-merged feature complete. A separate documentation PR is appropriate only for a genuine factual correction, a conflict discovered after merge, or information that could not reasonably have been recorded in the implementation PR.

## Pull request/task evidence

Include:
- problem.
- solution.
- affected modules.
- test/build evidence selected according to change risk.
- screenshots/video only when useful and free of sensitive data.
- performance evidence only for performance-sensitive changes.
- physical-device status when applicable.
- known risks.

Do not run expensive unrelated validation merely to repeat evidence already established for unaffected code. Explain any intentionally omitted validation as not applicable.

## Architecture changes

Add/update an ADR in the same branch.

## Delivery efficiency

The fixed baseline for risk-proportional validation, documentation-only fast paths, benchmark frequency, and physical-device validation is defined in `DELIVERY_EFFICIENCY.md`.
