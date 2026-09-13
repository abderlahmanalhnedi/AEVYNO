import Domain
import Foundation
import Observation

#if os(iOS) || os(tvOS)
  import AVKit
#endif

public protocol PlaybackClock: Sendable {
  func now() async -> Date
}

public struct SystemPlaybackClock: PlaybackClock {
  public init() {}
  public func now() -> Date { Date() }
}

@MainActor
@Observable
public final class PlaybackSession: Identifiable {
  public static let progressWriteInterval: TimeInterval = 12
  public static let meaningfulPositionChange: TimeInterval = 5

  public let id = UUID()
  public private(set) var mediaID: String?
  public private(set) var title = ""
  public private(set) var state: PlaybackState = .idle
  public private(set) var elapsed: TimeInterval = 0
  public private(set) var duration: TimeInterval?
  public private(set) var isSeekable = false
  public private(set) var failure: PlaybackFailure?
  public private(set) var resumePosition: TimeInterval?

  private let resolver: any PlaybackAssetResolving
  private let progressRepository: any WatchProgressRepository
  private let clock: any PlaybackClock
  private let engine: any PlaybackEngine
  private var kind: CatalogMediaKind = .unspecified
  private var attemptID = UUID()
  private var resolutionTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?
  private var pendingResumePosition: TimeInterval?
  private var startedPlayback = false
  private var lastPersistedAt: Date?
  private var lastPersistedPosition: TimeInterval?

  public init(
    resolver: any PlaybackAssetResolving,
    progressRepository: any WatchProgressRepository,
    clock: any PlaybackClock = SystemPlaybackClock(),
    engineFactory: @MainActor () -> any PlaybackEngine = { NativeAVPlayerEngine() }
  ) {
    self.resolver = resolver
    self.progressRepository = progressRepository
    self.clock = clock
    engine = engineFactory()
  }

  public func start(
    mediaID: String,
    title: String,
    kind: CatalogMediaKind,
    startOver: Bool = false
  ) {
    cancelCurrentAttempt(resetEngine: true, cancelEventObservation: false)
    self.mediaID = mediaID
    self.title = title
    self.kind = kind
    state = .loading
    elapsed = 0
    duration = nil
    isSeekable = false
    failure = nil
    resumePosition = nil
    pendingResumePosition = nil
    startedPlayback = false
    lastPersistedAt = nil
    lastPersistedPosition = nil
    attemptID = UUID()
    let activeAttempt = attemptID
    observeEngineEventsIfNeeded()

    resolutionTask = Task { [weak self, resolver, progressRepository, clock] in
      do {
        async let resolvedAsset = resolver.resolve(mediaID: mediaID)
        async let storedProgress = Self.prepareProgress(
          from: progressRepository,
          mediaID: mediaID,
          startOver: startOver,
          clock: clock
        )
        let (asset, progress) = try await (resolvedAsset, storedProgress)
        try Task.checkCancellation()
        self?.resolved(
          asset: asset,
          progress: progress,
          attemptID: activeAttempt
        )
      } catch is CancellationError {
        return
      } catch let playbackFailure as PlaybackFailure {
        self?.fail(playbackFailure, attemptID: activeAttempt)
      } catch {
        self?.fail(.unknown, attemptID: activeAttempt)
      }
    }
  }

  public func retry() {
    guard let mediaID else { return }
    start(mediaID: mediaID, title: title, kind: kind)
  }

  public func play() { engine.play() }
  public func pause() { engine.pause() }

  public func seek(to requestedPosition: TimeInterval) async {
    guard isSeekable, let duration else { return }
    let clamped = min(max(requestedPosition, 0), duration)
    await engine.seek(to: clamped)
  }

  public func checkpoint() async {
    await persistProgress(force: true, completed: state == .ended)
  }

  public func dismiss() async {
    await persistProgress(force: true, completed: state == .ended)
    cancelCurrentAttempt(resetEngine: true, cancelEventObservation: true)
    mediaID = nil
    title = ""
    state = .idle
    elapsed = 0
    duration = nil
    isSeekable = false
    failure = nil
    resumePosition = nil
  }

  #if os(iOS) || os(tvOS)
    public func makePlayerViewController() -> AVPlayerViewController {
      engine.makePlayerViewController()
    }
  #endif

  public static func resumablePosition(from progress: WatchProgress?) -> TimeInterval? {
    guard let progress, !progress.isCompleted else { return nil }
    return PlaybackCompletionPolicy.clampedResumePosition(
      progress.position,
      duration: progress.duration
    )
  }

  private static func readProgress(
    from repository: any WatchProgressRepository,
    mediaID: String
  ) async -> WatchProgress? {
    try? await repository.progress(for: mediaID)
  }

  private static func prepareProgress(
    from repository: any WatchProgressRepository,
    mediaID: String,
    startOver: Bool,
    clock: any PlaybackClock
  ) async -> WatchProgress? {
    guard startOver else { return await readProgress(from: repository, mediaID: mediaID) }
    let date = await clock.now()
    _ = try? await repository.startOver(mediaID: mediaID, at: date)
    return nil
  }

  private func observeEngineEventsIfNeeded() {
    guard eventTask == nil else { return }
    eventTask = Task { [weak self] in
      guard let self else { return }
      for await event in engine.events {
        guard !Task.isCancelled else { return }
        await handle(event)
      }
    }
  }

  private func resolved(
    asset: PlaybackAsset,
    progress: WatchProgress?,
    attemptID activeAttempt: UUID
  ) {
    guard attemptID == activeAttempt else { return }
    kind = asset.catalogKind
    let resumable = kind == .live ? nil : Self.resumablePosition(from: progress)
    resumePosition = resumable
    pendingResumePosition = resumable
    engine.load(asset, attemptID: activeAttempt)
  }

  private func fail(_ failure: PlaybackFailure, attemptID activeAttempt: UUID) {
    guard attemptID == activeAttempt else { return }
    self.failure = failure
    state = .failed
  }

  private func handle(_ event: PlaybackEngineEvent) async {
    guard event.attemptID == attemptID else { return }
    elapsed = event.timeline.elapsed
    duration = event.timeline.duration
    isSeekable = event.timeline.isSeekable
    failure = event.failure
    state = event.state

    switch event.state {
    case .ready:
      guard !startedPlayback else { return }
      startedPlayback = true
      if let pendingResumePosition,
        event.timeline.isSeekable,
        let duration = event.timeline.duration,
        let clamped = PlaybackCompletionPolicy.clampedResumePosition(
          pendingResumePosition,
          duration: duration
        )
      {
        self.pendingResumePosition = nil
        await engine.seek(to: clamped)
      }
      engine.play()
    case .playing:
      if let pendingResumePosition, event.timeline.isSeekable,
        let duration = event.timeline.duration
      {
        self.pendingResumePosition = nil
        if let clamped = PlaybackCompletionPolicy.clampedResumePosition(
          pendingResumePosition,
          duration: duration
        ) {
          await engine.seek(to: clamped)
        }
      }
      await persistProgress(force: false, completed: false)
    case .paused:
      await persistProgress(force: true, completed: false)
    case .ended:
      await persistProgress(force: true, completed: true)
    case .idle, .loading, .buffering, .failed:
      break
    }
  }

  private func persistProgress(force: Bool, completed: Bool) async {
    guard
      kind != .live,
      let mediaID,
      isSeekable,
      let duration,
      duration.isFinite,
      duration > 0,
      elapsed.isFinite,
      elapsed >= 0
    else { return }

    let clampedPosition = min(elapsed, duration)
    let now = await clock.now()
    if !force {
      guard
        let lastPersistedAt,
        let lastPersistedPosition,
        now.timeIntervalSince(lastPersistedAt) >= Self.progressWriteInterval,
        abs(clampedPosition - lastPersistedPosition) >= Self.meaningfulPositionChange
      else {
        if lastPersistedAt == nil {
          self.lastPersistedAt = now
          self.lastPersistedPosition = clampedPosition
        }
        return
      }
    }

    let isCompleted =
      completed
      || PlaybackCompletionPolicy.isCompleted(position: clampedPosition, duration: duration)
    let progress = WatchProgress(
      mediaID: mediaID,
      position: isCompleted ? duration : clampedPosition,
      duration: duration,
      updatedAt: now,
      isCompleted: isCompleted
    )
    do {
      try await progressRepository.save(progress)
      lastPersistedAt = now
      lastPersistedPosition = progress.position
      resumePosition = Self.resumablePosition(from: progress)
    } catch {
      // Playback remains available when a local checkpoint cannot be written.
    }
  }

  private func cancelCurrentAttempt(
    resetEngine: Bool,
    cancelEventObservation: Bool
  ) {
    attemptID = UUID()
    resolutionTask?.cancel()
    resolutionTask = nil
    if cancelEventObservation {
      eventTask?.cancel()
      eventTask = nil
    }
    if resetEngine { engine.stop() }
  }
}
