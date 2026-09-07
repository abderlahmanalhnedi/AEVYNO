# Test Strategy

## 1. Testing philosophy

Quality is a product feature. The project cannot reach the desired speed/design/compatibility level through manual happy-path testing alone.

## 2. Test pyramid

### Unit tests
Must cover:
- M3U parsing.
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

## 3. Performance tests

Maintain synthetic catalog generators/fixtures for 10k/50k/100k items.

Measure:
- parser throughput.
- import duration.
- query latency.
- memory behavior.
- search latency.

## 4. Playback compatibility tests

Maintain lawful fixture matrix.

Record for each fixture:
- container/protocol.
- expected behavior.
- actual engine result.
- OS/device.
- error signature if failed.

Do not mark a stream supported based only on one simulator run.

## 5. Physical Apple TV validation checklist

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

## 6. Device matrix

Once minimum OS and hardware baseline are selected, record the exact matrix in this file.

At least:
- oldest supported Apple TV hardware/OS available for validation.
- current representative Apple TV hardware.
- representative iPhone.
- representative iPad if layout differs materially.

## 7. Test evidence

Every completed Codex task must state:
- tests run.
- build command(s).
- result.
- simulator/device used.
- tests not run and why.

No "all good" without evidence.
