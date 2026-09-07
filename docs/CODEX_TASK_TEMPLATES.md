# Codex Task Templates

Use issue-like prompts. Keep one task focused.

## Feature task

```text
Read AGENTS.md and relevant project docs first.

Task: <specific feature>

Context:
- <module/path>
- <existing behavior>

Acceptance criteria:
1. ...
2. ...
3. ...

Constraints:
- no new third-party dependency.
- preserve existing architecture.
- add tests.
- do not change unrelated UI.

Validation:
- build affected targets.
- run relevant tests.
- state real-device validation status.

Update PROJECT_STATUS.md if this completes or changes a milestone.
```

## Performance task

```text
Read AGENTS.md and docs/PERFORMANCE_BUDGET.md.

Problem: <measured slowdown>
Evidence: <metric / trace / fixture>

First reproduce and measure. Do not optimize blindly.
Identify the bottleneck, make the smallest fix, then re-measure with the same fixture.
Do not trade correctness for speed.
Report before/after numbers and device/simulator/build configuration.
```

## Playback compatibility task

```text
Read AGENTS.md and docs/PLAYBACK_COMPATIBILITY.md.

Fixture: <lawful/synthetic stream identifier>
Observed failure: <exact normalized symptom>
Platform/device/OS: <...>

Reproduce using AVFoundation first. Determine whether the issue is source normalization, network/ATS, media format, or player state handling.
Do not add VLC/FFmpeg or another engine without the second-engine ADR gate.
Add/update the compatibility fixture test and report evidence.
```

## UI/tvOS task

```text
Read AGENTS.md and docs/DESIGN_SYSTEM.md.

Task: <screen/component>

Design constraints:
- tvOS first.
- native focus.
- original design.
- loading cannot steal focus.
- preserve focus on return where applicable.
- no expensive work in focus handlers.

Validate with UI tests/simulator and explicitly list what must still be checked on physical Apple TV.
```
