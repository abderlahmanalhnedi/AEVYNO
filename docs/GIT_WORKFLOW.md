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

## Pull request/task evidence

Include:
- problem.
- solution.
- affected modules.
- test/build evidence.
- screenshots/video only when useful and free of sensitive data.
- performance evidence for performance-sensitive changes.
- physical-device status.
- known risks.

## Architecture changes

Add/update an ADR in the same branch.
