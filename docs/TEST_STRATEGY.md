# Test Strategy

## 1. Testing philosophy

Quality is a product feature. The project cannot reach the desired speed/design/compatibility level through manual happy-path testing alone.

## 2. Test pyramid

### Unit tests
Must cover:
- M3U parsing.
- XMLTV explicit-offset time parsing, malformed-entry isolation, bounded streaming behavior, and
  deterministic Now/Next interval/overlap semantics.
- Synthetic XMLTV compatibility fixtures, spool/staging cleanup, retry/reopen behavior, and
  last-known-good preservation.
- XMLTV cancellation injection at parse, spool-production, staging, and pre-publication boundaries;
  the test must prove no source publication, no staged rows, no retained spool, and LKG readability.
- bounded source-scoped Guide intervals, channel pages, deterministic programme ordering, gaps, and
  100/1,000/10,000-channel synthetic persistence measurements.
- provider response normalization.
- stable ID construction.
- watch-progress rules.
- completion policy.
- Cloud conflict resolution.
- redaction.
- search normalization.

### Persistence tests
Cover:
- batch import.
- replacement/refresh transaction behavior.
- indexes/query correctness.
- large fixture query performance.
- migration behavior.

### Integration tests
Cover:
- provider adapter -> normalized models -> persistence.
- local progress -> sync queue.
- Cloud sync fakes -> conflict resolver.
- playback state machine with controlled fakes.

### UI tests
Critical journeys:
- tvOS Home focus movement.
- open Detail and return with focus restoration.
- open Player and exit.
- source setup error/success.
- Continue Watching appears after progress.
- English/German/Arabic locale launches for owned screens.
- Arabic RTL Home focus movement.
- Arabic RTL Detail/back focus restoration.
- Guide entry, deterministic programme focus/detail/back restoration, safe empty Guide state, and
  Arabic Guide accessibility with synthetic fixtures only.
- long and mixed-direction Arabic text does not break critical layouts.

## 3. Localization and RTL tests

The required first-class interface locales are English, German and Arabic.

For Arabic, test:

- native RTL layout direction.
- Home and Detail layout.
- loading, empty and error states.
- long titles and Arabic/Latin mixed-direction metadata.
- focus movement and restoration.
- accessibility labels.
- Reduce Motion behavior where relevant.
- locale-aware numbers, durations and other formatted values.

Physical Apple TV milestone review must include Arabic RTL. Simulator screenshots alone do not
prove Siri Remote focus behavior.

Read `docs/LOCALIZATION.md`.

## 4. Performance tests

Maintain synthetic catalog generators/fixtures for 10k/50k/100k items.

Measure:
- parser throughput.
- import duration.
- query latency.
- memory behavior.
- search latency.

## 5. Playback compatibility tests

Maintain lawful fixture matrix.

Record for each fixture:
- container/protocol.
- expected behavior.
- actual engine result.
- OS/device.
- error signature if failed.

Do not mark a stream supported based only on one simulator run.

## 6. Physical Apple TV validation checklist

Before major milestone/TestFlight:
- cold launch.
- warm launch.
- Home focus behavior.
- rapid directional remote navigation.
- long scrolling session.
- repeated open/back navigation.
- player start/seek/pause/resume.
- subtitles/audio tracks where available.
- network loss and recovery.
- memory behavior during long session.
- app background/foreground.
- Continue Watching sync with iPhone/iPad.
- Arabic RTL Home/Detail visual quality.
- Arabic RTL rapid focus navigation and repeated Detail/back restoration.

## 7. Device matrix

Once minimum OS and hardware baseline are selected, record the exact matrix in this file.

At least:
- oldest supported Apple TV hardware/OS available for validation.
- current representative Apple TV hardware.
- representative iPhone.
- representative iPad if layout differs materially.

## 8. Test evidence

Every completed Codex task must state:
- tests run.
- build command(s).
- result.
- simulator/device used.
- tests not run and why.

No "all good" without evidence.
