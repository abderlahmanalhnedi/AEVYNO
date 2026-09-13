import Domain
import Foundation
import Library
import Persistence
import Playback
import Testing

@Suite("Playback foundation", .serialized)
struct PlaybackFoundationTests {
  @MainActor
  @Test("Session normalizes ready, playing, buffering, paused, ended, and stop")
  func stateMachine() async throws {
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: FakePlaybackResolver(),
      progressRepository: FakeProgressRepository(),
      engineFactory: { engine }
    )

    session.start(mediaID: "media-1", title: "Fixture", kind: .vod)
    #expect(session.state == .loading)
    try await waitUntil { engine.loadCount == 1 }
    engine.emit(.ready, elapsed: 0, duration: 100, isSeekable: true)
    try await waitUntil { session.state == .playing }
    engine.emit(.buffering, elapsed: 10, duration: 100, isSeekable: true)
    try await waitUntil { session.state == .buffering }
    engine.emit(.playing, elapsed: 11, duration: 100, isSeekable: true)
    try await waitUntil { session.state == .playing }
    session.pause()
    try await waitUntil { session.state == .paused }
    engine.emit(.ended, elapsed: 100, duration: 100, isSeekable: true)
    try await waitUntil { session.state == .ended }
    await session.dismiss()
    #expect(session.state == .idle)
    #expect(engine.stopCount >= 2)
  }

  @MainActor
  @Test("Failure, retry, cancellation, replacement, and stale events are deterministic")
  func failureRetryAndStaleEvents() async throws {
    let resolver = FakePlaybackResolver(failuresBeforeSuccess: 1)
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: resolver,
      progressRepository: FakeProgressRepository(),
      engineFactory: { engine }
    )

    session.start(mediaID: "media-1", title: "Fixture", kind: .vod)
    try await waitUntil { session.state == .failed }
    #expect(session.failure == .transport)
    session.retry()
    try await waitUntil { engine.loadCount == 1 }
    #expect(await resolver.resolveCount == 2)

    let firstAttempt = try #require(engine.lastAttemptID)
    session.start(mediaID: "media-2", title: "New Fixture", kind: .vod)
    try await waitUntil { engine.loadCount == 2 }
    let secondAttempt = try #require(engine.lastAttemptID)
    #expect(firstAttempt != secondAttempt)
    engine.emit(
      .failed,
      attemptID: firstAttempt,
      failure: .unknown
    )
    await Task.yield()
    #expect(session.state != .failed)
    engine.emit(.ready, attemptID: secondAttempt, duration: 100, isSeekable: true)
    try await waitUntil { session.state == .playing }
    #expect(session.mediaID == "media-2")
  }

  @MainActor
  @Test("Cancellation does not become a user-facing failure")
  func cancellationIsNotFailure() async throws {
    let resolver = FakePlaybackResolver(delay: .seconds(30))
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: resolver,
      progressRepository: FakeProgressRepository(),
      engineFactory: { engine }
    )
    session.start(mediaID: "slow", title: "Slow", kind: .vod)
    await session.dismiss()
    await Task.yield()
    #expect(session.state == .idle)
    #expect(session.failure == nil)
  }

  @MainActor
  @Test("Seek clamps to the known finite duration")
  func seekClamps() async throws {
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: FakePlaybackResolver(),
      progressRepository: FakeProgressRepository(),
      engineFactory: { engine }
    )
    session.start(mediaID: "media-1", title: "Fixture", kind: .vod)
    try await waitUntil { engine.loadCount == 1 }
    engine.emit(.ready, duration: 100, isSeekable: true)
    try await waitUntil { session.isSeekable }
    await session.seek(to: 900)
    #expect(engine.seekPositions.last == 100)
    await session.seek(to: -20)
    #expect(engine.seekPositions.last == 0)
  }

  @MainActor
  @Test("Progress throttles playing writes and checkpoints pause and dismissal")
  func progressWritePolicy() async throws {
    let progress = FakeProgressRepository()
    let clock = FakePlaybackClock(date: Date(timeIntervalSince1970: 1_700_000_000))
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: FakePlaybackResolver(),
      progressRepository: progress,
      clock: clock,
      engineFactory: { engine }
    )
    session.start(mediaID: "media-1", title: "Fixture", kind: .unspecified)
    try await waitUntil { engine.loadCount == 1 }
    engine.emit(.ready, duration: 200, isSeekable: true)
    try await waitUntil { session.state == .playing }
    engine.emit(.playing, elapsed: 10, duration: 200, isSeekable: true)
    try await waitUntil { await progress.saveCount == 0 }
    await clock.advance(by: 11)
    engine.emit(.playing, elapsed: 25, duration: 200, isSeekable: true)
    await Task.yield()
    #expect(await progress.saveCount == 0)
    await clock.advance(by: 1)
    engine.emit(.playing, elapsed: 30, duration: 200, isSeekable: true)
    try await waitUntil { await progress.saveCount == 1 }
    session.pause()
    try await waitUntil { await progress.saveCount == 2 }
    await session.dismiss()
    #expect(await progress.saveCount == 3)
  }

  @MainActor
  @Test("Live playback never writes VOD progress")
  func liveDoesNotPersist() async throws {
    let progress = FakeProgressRepository()
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: FakePlaybackResolver(kind: .live),
      progressRepository: progress,
      engineFactory: { engine }
    )
    session.start(mediaID: "live-1", title: "Live", kind: .live)
    try await waitUntil { engine.loadCount == 1 }
    engine.emit(.ready, duration: 100, isSeekable: true)
    engine.emit(.playing, elapsed: 50, duration: 100, isSeekable: true)
    session.pause()
    await session.dismiss()
    #expect(await progress.saveCount == 0)
  }

  @MainActor
  @Test("Resume seeks only finite VOD and completed media starts over")
  func resumeAndCompletion() async throws {
    let saved = WatchProgress(
      mediaID: "media-1",
      position: 40,
      duration: 100,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      isCompleted: false
    )
    let progress = FakeProgressRepository(records: [saved.mediaID: saved])
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: FakePlaybackResolver(),
      progressRepository: progress,
      engineFactory: { engine }
    )
    session.start(mediaID: "media-1", title: "Fixture", kind: .vod)
    try await waitUntil { engine.loadCount == 1 }
    engine.emit(.ready, duration: 100, isSeekable: true)
    try await waitUntil { engine.seekPositions == [40] }
    #expect(session.resumePosition == 40)

    let completed = WatchProgress(
      mediaID: "media-2",
      position: 95,
      duration: 100,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
      isCompleted: true
    )
    await progress.set(completed)
    session.start(mediaID: "media-2", title: "Complete", kind: .vod)
    try await waitUntil { engine.loadCount == 2 }
    let seekCount = engine.seekPositions.count
    engine.emit(.ready, duration: 100, isSeekable: true)
    try await waitUntil { session.state == .playing }
    #expect(engine.seekPositions.count == seekCount)
    #expect(session.resumePosition == nil)
  }

  @MainActor
  @Test("End and the 95 percent threshold persist completion")
  func completionPolicy() async throws {
    #expect(!PlaybackCompletionPolicy.isCompleted(position: 94.9, duration: 100))
    #expect(PlaybackCompletionPolicy.isCompleted(position: 95, duration: 100))
    #expect(PlaybackCompletionPolicy.clampedResumePosition(99, duration: 100) == nil)

    let progress = FakeProgressRepository()
    let engine = FakePlaybackEngine()
    let session = PlaybackSession(
      resolver: FakePlaybackResolver(),
      progressRepository: progress,
      engineFactory: { engine }
    )
    session.start(mediaID: "media-1", title: "Fixture", kind: .vod)
    try await waitUntil { engine.loadCount == 1 }
    engine.emit(.ready, duration: 100, isSeekable: true)
    engine.emit(.ended, elapsed: 96, duration: 100, isSeekable: true)
    try await waitUntil { await progress.saveCount == 1 }
    let record = await progress.progress(for: "media-1")
    #expect(record?.isCompleted == true)
    #expect(record?.position == 100)
  }

  @Test("Playback asset and normalized failures never describe a URL")
  func redactionAndFailureMapping() throws {
    let secretURL = try #require(
      URL(string: "https://user:secret@example.invalid/live?token=hidden"))
    let asset = PlaybackAsset(
      mediaID: "safe-id",
      title: "Fixture",
      catalogKind: .unspecified,
      mediaURL: secretURL
    )
    #expect(asset.description.contains("<redacted>"))
    #expect(!asset.description.contains("secret"))
    #expect(!asset.debugDescription.contains("token"))
    #expect(
      NativeAVPlayerEngine.normalizedFailure(from: URLError(.timedOut)) == .transport
    )
    #expect(NativeAVPlayerEngine.normalizedFailure(from: nil, statusCode: 403) == .forbidden)
    #expect(NativeAVPlayerEngine.normalizedFailure(from: nil, statusCode: 404) == .notFound)
  }

  @MainActor
  @Test("Application-side playback preparation overhead stays bounded to one item")
  func applicationPreparationMeasurement() async throws {
    let catalog = PlaybackCatalogFixture(
      item: try makeCatalogItem(origin: .m3u, kind: .unspecified))
    let resolver = ProductionPlaybackAssetResolver(catalog: catalog)
    let progressURL = temporaryURL(named: "performance-progress.json")
    let repository = FileWatchProgressRepository(url: progressURL)
    let iterations = 200

    var start = Date.timeIntervalSinceReferenceDate
    for _ in 0..<iterations { _ = try await resolver.resolve(mediaID: "media-1") }
    let resolutionMilliseconds =
      (Date.timeIntervalSinceReferenceDate - start) * 1_000 / Double(iterations)

    start = Date.timeIntervalSinceReferenceDate
    for _ in 0..<iterations { _ = try await repository.progress(for: "media-1") }
    let progressMilliseconds =
      (Date.timeIntervalSinceReferenceDate - start) * 1_000 / Double(iterations)

    let engine = FakePlaybackEngine()
    start = Date.timeIntervalSinceReferenceDate
    for _ in 0..<iterations {
      _ = PlaybackSession(
        resolver: resolver,
        progressRepository: repository,
        engineFactory: { engine }
      )
    }
    let sessionMilliseconds =
      (Date.timeIntervalSinceReferenceDate - start) * 1_000 / Double(iterations)
    print(
      "PLAYBACK-PREPARATION iterations=\(iterations) "
        + "resolution-average-ms=\(resolutionMilliseconds) "
        + "progress-average-ms=\(progressMilliseconds) "
        + "session-average-ms=\(sessionMilliseconds)"
    )
    #expect(resolutionMilliseconds < 10)
    #expect(progressMilliseconds < 10)
    #expect(sessionMilliseconds < 10)
  }
}

@Suite("Playback asset resolution")
struct PlaybackAssetResolverTests {
  @Test("Committed M3U resolves by stable ID and stays unspecified")
  func m3uResolution() async throws {
    let item = try makeCatalogItem(origin: .m3u, kind: .unspecified)
    let resolver = ProductionPlaybackAssetResolver(catalog: PlaybackCatalogFixture(item: item))
    #expect(await resolver.availability(for: item.id) == .playable)
    let asset = try await resolver.resolve(mediaID: item.id)
    #expect(asset.mediaID == item.id)
    #expect(asset.catalogKind == .unspecified)
    #expect(!asset.description.contains("example.invalid"))
  }

  @Test("Missing items and corrupt references fail safely")
  func missingAndMalformed() async throws {
    let missing = ProductionPlaybackAssetResolver(catalog: PlaybackCatalogFixture(item: nil))
    #expect(await missing.availability(for: "missing") == .unavailable(.itemUnavailable))
    await #expect(throws: PlaybackFailure.itemUnavailable) {
      try await missing.resolve(mediaID: "missing")
    }

    let malformed = try makeCatalogItem(origin: .m3u, kind: .unspecified, mediaURL: nil)
    let resolver = ProductionPlaybackAssetResolver(catalog: PlaybackCatalogFixture(item: malformed))
    #expect(await resolver.availability(for: malformed.id) == .unavailable(.mediaUnavailable))
  }

  @Test("Xtream live, VOD, and series remain unsupported without a playback contract")
  func xtreamDoesNotGuess() async throws {
    for kind in [CatalogMediaKind.live, .vod, .series] {
      let item = try makeCatalogItem(origin: .xtream, kind: kind, mediaURL: nil)
      let resolver = ProductionPlaybackAssetResolver(catalog: PlaybackCatalogFixture(item: item))
      #expect(await resolver.availability(for: item.id) == .unavailable(.unsupported))
      await #expect(throws: PlaybackFailure.unsupported) {
        try await resolver.resolve(mediaID: item.id)
      }
    }
  }

  @Test("Catalog failures become safe source-unavailable failures")
  func catalogFailure() async {
    let resolver = ProductionPlaybackAssetResolver(
      catalog: PlaybackCatalogFixture(item: nil, fails: true)
    )
    #expect(await resolver.availability(for: "media-1") == .unavailable(.sourceUnavailable))
    await #expect(throws: PlaybackFailure.sourceUnavailable) {
      try await resolver.resolve(mediaID: "media-1")
    }
  }
}

@Suite("Durable watch progress")
struct WatchProgressRepositoryTests {
  @Test("Progress saves, updates, reopens, removes, and supports multiple IDs")
  func durableCRUD() async throws {
    let url = temporaryURL(named: "watch-progress.json")
    let first = FileWatchProgressRepository(url: url)
    try await first.save(progress(mediaID: "one", position: 10, duration: 100))
    try await first.save(progress(mediaID: "two", position: 20, duration: 200))
    try await first.save(progress(mediaID: "one", position: 30, duration: 100))

    let reopened = FileWatchProgressRepository(url: url)
    #expect(try await reopened.progress(for: "one")?.position == 30)
    #expect(try await reopened.progress(for: "two")?.position == 20)
    try await reopened.remove(mediaID: "one")
    #expect(try await FileWatchProgressRepository(url: url).progress(for: "one") == nil)
    #expect(try await FileWatchProgressRepository(url: url).progress(for: "two") != nil)
  }

  @Test("Completed state is durable and serialized records contain no URL fields")
  func completedAndPrivate() async throws {
    let url = temporaryURL(named: "private-progress.json")
    let repository = FileWatchProgressRepository(url: url)
    try await repository.save(
      WatchProgress(
        mediaID: "stable-id",
        position: 100,
        duration: 100,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isCompleted: true
      ))
    #expect(
      try await FileWatchProgressRepository(url: url).progress(for: "stable-id")?.isCompleted
        == true)
    let serialized = try String(contentsOf: url, encoding: .utf8)
    #expect(!serialized.lowercased().contains("url"))
    #expect(!serialized.lowercased().contains("password"))
    #expect(!serialized.lowercased().contains("token"))
  }

  @Test("Explicit Start Over durably clears completion without removing identity")
  func startOverIsDurable() async throws {
    let url = temporaryURL(named: "start-over.json")
    let repository = FileWatchProgressRepository(url: url)
    try await repository.save(
      WatchProgress(
        mediaID: "stable-id",
        position: 100,
        duration: 100,
        updatedAt: Date(timeIntervalSince1970: 100),
        isCompleted: true
      )
    )

    let reset = try await repository.startOver(
      mediaID: "stable-id",
      at: Date(timeIntervalSince1970: 200)
    )
    #expect(reset?.position == 0)
    #expect(reset?.isCompleted == false)
    #expect(try await FileWatchProgressRepository(url: url).progress(for: "stable-id") == reset)
  }

  @Test("Progress remains when unrelated catalog state is removed or replaced")
  func catalogIndependence() async throws {
    let url = temporaryURL(named: "catalog-independent-progress.json")
    let repository = FileWatchProgressRepository(url: url)
    try await repository.save(progress(mediaID: "stable-id", position: 42, duration: 100))

    let missingResolver = ProductionPlaybackAssetResolver(
      catalog: PlaybackCatalogFixture(item: nil)
    )
    #expect(await missingResolver.availability(for: "stable-id") == .unavailable(.itemUnavailable))

    let replacement = try makeCatalogItem(origin: .m3u, kind: .unspecified)
    let replacementResolver = ProductionPlaybackAssetResolver(
      catalog: PlaybackCatalogFixture(item: replacement)
    )
    #expect(await replacementResolver.availability(for: replacement.id) == .playable)
    #expect(
      try await FileWatchProgressRepository(url: url).progress(for: "stable-id")?.position == 42)
  }

  @Test("Corrupt, invalid, and future-schema stores fail without reset")
  func safeFailures() async throws {
    let corruptURL = temporaryURL(named: "corrupt-progress.json")
    try Data("not-json".utf8).write(to: corruptURL)
    await #expect(throws: WatchProgressRepositoryError.corruptedStore) {
      try await FileWatchProgressRepository(url: corruptURL).progress(for: "media")
    }

    let futureURL = temporaryURL(named: "future-progress.json")
    try Data("{\"schemaVersion\":2,\"records\":[]}".utf8).write(to: futureURL)
    await #expect(throws: WatchProgressRepositoryError.unsupportedSchema) {
      try await FileWatchProgressRepository(url: futureURL).progress(for: "media")
    }

    let repository = FileWatchProgressRepository(url: temporaryURL(named: "invalid-progress.json"))
    await #expect(throws: WatchProgressRepositoryError.invalidProgress) {
      try await repository.save(progress(mediaID: "media", position: 101, duration: 100))
    }
  }
}

@MainActor
private final class FakePlaybackEngine: PlaybackEngine {
  private let stream: AsyncStream<PlaybackEngineEvent>
  private let continuation: AsyncStream<PlaybackEngineEvent>.Continuation
  private(set) var loadCount = 0
  private(set) var stopCount = 0
  private(set) var seekPositions: [TimeInterval] = []
  private(set) var lastAttemptID: UUID?
  private var timeline = PlaybackTimeline()

  init() {
    (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
  }

  var events: AsyncStream<PlaybackEngineEvent> { stream }

  func load(_: PlaybackAsset, attemptID: UUID) {
    loadCount += 1
    lastAttemptID = attemptID
    emit(.loading, attemptID: attemptID)
  }

  func play() { emit(.playing, timeline: timeline) }
  func pause() { emit(.paused, timeline: timeline) }

  func seek(to seconds: TimeInterval) async {
    seekPositions.append(seconds)
  }

  func stop() { stopCount += 1 }

  func emit(
    _ state: PlaybackState,
    attemptID: UUID? = nil,
    elapsed: TimeInterval = 0,
    duration: TimeInterval? = nil,
    isSeekable: Bool = false,
    failure: PlaybackFailure? = nil
  ) {
    emit(
      state,
      attemptID: attemptID,
      timeline: PlaybackTimeline(
        elapsed: elapsed,
        duration: duration,
        isSeekable: isSeekable
      ),
      failure: failure
    )
  }

  private func emit(
    _ state: PlaybackState,
    attemptID: UUID? = nil,
    timeline: PlaybackTimeline,
    failure: PlaybackFailure? = nil
  ) {
    guard let attemptID = attemptID ?? lastAttemptID else { return }
    self.timeline = timeline
    continuation.yield(
      PlaybackEngineEvent(
        attemptID: attemptID,
        state: state,
        timeline: timeline,
        failure: failure
      ))
  }
}

private actor FakePlaybackResolver: PlaybackAssetResolving {
  private var failuresRemaining: Int
  private let delay: Duration?
  private let kind: CatalogMediaKind
  private(set) var resolveCount = 0

  init(
    failuresBeforeSuccess: Int = 0,
    delay: Duration? = nil,
    kind: CatalogMediaKind = .vod
  ) {
    failuresRemaining = failuresBeforeSuccess
    self.delay = delay
    self.kind = kind
  }

  func availability(for _: String) -> PlaybackAvailability { .playable }

  func resolve(mediaID: String) async throws -> PlaybackAsset {
    resolveCount += 1
    if let delay { try await Task.sleep(for: delay) }
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw PlaybackFailure.transport
    }
    guard let url = URL(string: "https://example.invalid/fixture.m3u8") else {
      throw PlaybackFailure.mediaUnavailable
    }
    return PlaybackAsset(
      mediaID: mediaID,
      title: "Fixture",
      catalogKind: kind,
      mediaURL: url
    )
  }
}

private actor FakeProgressRepository: WatchProgressRepository {
  private var records: [String: WatchProgress]
  private(set) var saveCount = 0

  init(records: [String: WatchProgress] = [:]) { self.records = records }

  func progress(for mediaID: String) -> WatchProgress? { records[mediaID] }

  func allProgress() -> [WatchProgress] {
    records.values.sorted { $0.mediaID < $1.mediaID }
  }

  func save(_ progress: WatchProgress) {
    saveCount += 1
    records[progress.mediaID] = progress
  }

  func remove(mediaID: String) { records.removeValue(forKey: mediaID) }
  func set(_ progress: WatchProgress) { records[progress.mediaID] = progress }
}

private actor FakePlaybackClock: PlaybackClock {
  private var date: Date
  init(date: Date) { self.date = date }
  func now() -> Date { date }
  func advance(by interval: TimeInterval) { date = date.addingTimeInterval(interval) }
}

private actor PlaybackCatalogFixture: CatalogLibraryQuerying {
  private let storedItem: CatalogItem?
  private let fails: Bool

  init(item: CatalogItem?, fails: Bool = false) {
    storedItem = item
    self.fails = fails
  }

  func item(id: String) throws -> CatalogItem? {
    if fails { throw CatalogStoreError.unavailable }
    return storedItem?.id == id ? storedItem : nil
  }

  func browseItems(matching _: CatalogFilter, page _: CatalogPage) -> [CatalogItem] { [] }
  func searchItems(_: String, matching _: CatalogFilter, page _: CatalogPage) -> [CatalogItem] {
    []
  }
  func categories(matching _: CatalogFilter, page _: CatalogPage) -> [CatalogCategorySummary] { [] }
  func itemCount(matching _: CatalogFilter) -> Int { 0 }
  func sourceCatalogCount(sourceID _: SourceConfiguration.ID?) -> Int { 0 }
}

private func makeCatalogItem(
  origin: CatalogOrigin,
  kind: CatalogMediaKind,
  mediaURL: URL? = URL(string: "https://example.invalid/fixture.m3u8")
) throws -> CatalogItem {
  let sourceID = SourceConfiguration.ID(
    rawValue: try #require(UUID(uuidString: "91000000-0000-0000-0000-000000000001"))
  )
  let providerReference: ProviderItemReference? =
    origin == .xtream
    ? ProviderItemReference(
      kind: kind == .live ? .live : (kind == .vod ? .vod : .series),
      providerID: "provider-1"
    )
    : nil
  return CatalogItem(
    id: "media-1",
    scope: CatalogScope(sourceID: sourceID, origin: origin, kind: kind),
    title: "Fixture",
    mediaURL: mediaURL,
    providerReference: providerReference
  )
}

private func progress(
  mediaID: String,
  position: TimeInterval,
  duration: TimeInterval
) -> WatchProgress {
  WatchProgress(
    mediaID: mediaID,
    position: position,
    duration: duration,
    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
    isCompleted: false
  )
}

private func temporaryURL(named name: String) -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("AEVYNO-Playback-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent(name)
}

@MainActor
private func waitUntil(
  _ condition: @escaping @MainActor () async -> Bool
) async throws {
  for _ in 0..<200 {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(2))
  }
  Issue.record("Timed out waiting for playback state")
}
