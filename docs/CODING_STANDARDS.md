# Coding Standards

## Swift

- Prefer modern Swift and structured concurrency supported by the selected deployment targets.
- Enable strict concurrency checking appropriate for the toolchain when practical.
- Favor value types for domain data.
- Use actors for mutable service state when appropriate.
- Avoid force unwraps in production logic.
- Avoid `try!`.
- Avoid `fatalError` except unreachable development scaffolding that cannot ship.

## Naming

Use descriptive names over abbreviations.

Examples:
- `WatchProgressRepository`
- `SourceCredentialStore`
- `PlaybackSession`
- `CatalogRefreshService`

Avoid names such as `Manager2`, `Helper`, `Utils`, `Stuff`.

## Files and types

A file should have a clear responsibility.

Do not create giant "God" services or view models.

Extensions should group cohesive behavior.

## SwiftUI

- keep business logic out of `body`.
- avoid launching duplicate tasks due to view re-rendering.
- use stable IDs in lists/grids.
- do not construct expensive formatters/parsers repeatedly in cells.
- isolate platform-specific modifiers when behavior differs.

## Networking

- typed request/response models.
- normalized errors.
- explicit timeout/retry policy.
- no infinite retries.
- redact request URLs before logging.

## Comments

Comment why, not what obvious code does.

Use documentation comments for public/shared interfaces where semantics are non-obvious.

## TODO policy

A TODO must be actionable and preferably reference a task/issue. Do not leave vague TODOs such as "fix later".

## Dependencies

No new external package without an ADR if it is architecture/significant-runtime relevant. Small dev-only tooling may be approved separately but must still be documented.
