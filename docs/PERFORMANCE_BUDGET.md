# Performance Budget

These are engineering targets, not marketing claims. Every number must be measured on named hardware/OS/build configuration before being marked as passed.

## 1. Golden rule

No feature may make tvOS navigation visibly sluggish.

## 2. Interaction targets

- Focus response should feel immediate; avoid synchronous work in focus handlers.
- UI work should target smooth platform refresh behavior and avoid avoidable frame stalls.
- Returning to an already-cached Home screen should not trigger a full provider re-import.

## 3. Launch targets

Initial targets for a representative supported Apple TV device:
- show usable cached shell/content as early as possible.
- target warm cached Home usability around 1 second or better where feasible.
- target cold cached usability within roughly 2–3 seconds where feasible.

Do not fail the product solely on these provisional numbers until measured across chosen baseline hardware. Record measurements in performance notes.

## 4. Large catalog fixtures

Maintain synthetic fixtures at approximately:
- 10k items.
- 50k items.
- 100k items.

At minimum test:
- import time.
- memory peak.
- Home query time.
- category query time.
- search latency.
- scrolling/focus stability.

## 5. Import rules

- Parse off-main.
- Batch writes.
- Avoid per-item UI notifications during bulk import.
- Make refresh replace/update data safely.
- Do not keep duplicate full in-memory representations longer than necessary.

## 6. Search

Search must query an index/store rather than filtering an entire huge array on every keystroke.

Debounce user input only when needed; do not make search feel artificially delayed.

## 7. Images

- bounded memory cache.
- bounded disk cache if used.
- request/cancel per visible need.
- resize/downsample appropriately.
- avoid retaining full-resolution poster images in view state.

## 8. Playback startup

Measure and separate:
- app preparation overhead.
- DNS/network connect.
- provider response.
- AVPlayer item readiness.
- first rendered frame.

Provisional goal on healthy HLS/provider conditions:
- p50 first frame approximately <= 1.5–2.0 s.
- p95 approximately <= 4 s.

Do not blame app code for provider latency without instrumentation.

## 9. Watch progress writes

Do not persist/sync every playback second.

Baseline policy:
- update in-memory frequently enough for UI.
- local durable checkpoint periodically (for example around 10–20 seconds, tuned after testing).
- force checkpoint on pause, seek settlement, app background/termination opportunity, item exit and completion.
- CloudKit sync is throttled/coalesced independently.

Target resume error: normally within a few seconds of the last durable checkpoint.

## 10. Memory

Do not hard-code a single jetsam-safe MB budget without measuring supported devices.

Required:
- bounded caches.
- respond to memory pressure.
- no full-poster preloading.
- no unbounded retained player items.
- profile long browsing sessions on real Apple TV.

## 11. Performance regression policy

For performance-critical paths, a feature PR/task must not be accepted if it introduces a clearly measurable regression without an explicit tradeoff decision.
