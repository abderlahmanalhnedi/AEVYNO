import AVKit
import Domain
import Foundation
import Playback

@MainActor
final class TVPlaybackFixture {
  enum EngineScenario {
    case loading
    case playing
    case paused
    case buffering
    case failure
    case retry
    case ended
  }

  let dependencies: PlaybackDependencies
  private let scenario: EngineScenario

  init(arguments: [String]) {
    if arguments.contains("--ui-playback-loading") {
      scenario = .loading
    } else if arguments.contains("--ui-playback-paused") {
      scenario = .paused
    } else if arguments.contains("--ui-playback-buffering") {
      scenario = .buffering
    } else if arguments.contains("--ui-playback-failure") {
      scenario = .failure
    } else if arguments.contains("--ui-playback-retry") {
      scenario = .retry
    } else if arguments.contains("--ui-playback-ended") {
      scenario = .ended
    } else {
      scenario = .playing
    }

    let progress: WatchProgress?
    if arguments.contains("--ui-playback-resumable") {
      progress = WatchProgress(
        mediaID: "m3u-1",
        position: 125,
        duration: 600,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isCompleted: false
      )
    } else if arguments.contains("--ui-playback-completed") {
      progress = WatchProgress(
        mediaID: "m3u-1",
        position: 600,
        duration: 600,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isCompleted: true
      )
    } else {
      progress = nil
    }
    dependencies = PlaybackDependencies(
      resolver: TVPlaybackAssetResolver(),
      progressRepository: TVPlaybackProgressRepository(progress: progress)
    )
  }

  func makeEngine() -> any PlaybackEngine {
    TVPlaybackEngine(scenario: scenario)
  }
}

private actor TVPlaybackAssetResolver: PlaybackAssetResolving {
  func availability(for mediaID: String) -> PlaybackAvailability {
    mediaID == "m3u-1" ? .playable : .unavailable(.unsupported)
  }

  func resolve(mediaID: String) throws -> PlaybackAsset {
    guard mediaID == "m3u-1" else { throw PlaybackFailure.unsupported }
    guard let url = URL(string: "https://example.invalid/synthetic-playback.m3u8") else {
      throw PlaybackFailure.mediaUnavailable
    }
    return PlaybackAsset(
      mediaID: mediaID,
      title: "Synthetic Playback",
      catalogKind: .unspecified,
      mediaURL: url
    )
  }
}

private actor TVPlaybackProgressRepository: WatchProgressRepository {
  private var stored: WatchProgress?

  init(progress: WatchProgress?) { stored = progress }

  func progress(for mediaID: String) -> WatchProgress? {
    stored?.mediaID == mediaID ? stored : nil
  }

  func save(_ progress: WatchProgress) { stored = progress }
  func remove(mediaID _: String) { stored = nil }
}

@MainActor
private final class TVPlaybackEngine: PlaybackEngine {
  private let scenario: TVPlaybackFixture.EngineScenario
  private let stream: AsyncStream<PlaybackEngineEvent>
  private let continuation: AsyncStream<PlaybackEngineEvent>.Continuation
  private var loadCount = 0
  private var activeAttempt = UUID()

  init(scenario: TVPlaybackFixture.EngineScenario) {
    self.scenario = scenario
    (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
  }

  var events: AsyncStream<PlaybackEngineEvent> { stream }

  func load(_: PlaybackAsset, attemptID: UUID) {
    activeAttempt = attemptID
    loadCount += 1
    emit(.loading)
    switch scenario {
    case .loading:
      break
    case .failure:
      emit(.failed, failure: .transport)
    case .retry where loadCount == 1:
      emit(.failed, failure: .transport)
    default:
      emit(.ready)
    }
  }

  func play() {
    switch scenario {
    case .paused:
      emit(.paused)
    case .buffering:
      emit(.buffering)
    case .ended:
      emit(.ended)
    default:
      emit(.playing)
    }
  }

  func pause() { emit(.paused) }

  func seek(to seconds: TimeInterval) async {
    emit(.paused, elapsed: seconds)
  }

  func stop() { emit(.idle, elapsed: 0, duration: nil, isSeekable: false) }

  func makePlayerViewController() -> AVPlayerViewController {
    AVPlayerViewController()
  }

  private func emit(
    _ state: PlaybackState,
    elapsed: TimeInterval = 30,
    duration: TimeInterval? = 600,
    isSeekable: Bool = true,
    failure: PlaybackFailure? = nil
  ) {
    continuation.yield(
      PlaybackEngineEvent(
        attemptID: activeAttempt,
        state: state,
        timeline: PlaybackTimeline(
          elapsed: elapsed,
          duration: duration,
          isSeekable: isSeekable
        ),
        failure: failure
      ))
  }
}
