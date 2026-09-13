import AVFoundation
import Foundation

#if os(iOS) || os(tvOS)
  import AVKit
#endif

@MainActor
public final class NativeAVPlayerEngine: PlaybackEngine {
  private let player = AVPlayer()
  private let stream: AsyncStream<PlaybackEngineEvent>
  private let continuation: AsyncStream<PlaybackEngineEvent>.Continuation
  private var attemptID = UUID()
  private var itemStatusObservation: NSKeyValueObservation?
  private var keepUpObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var periodicTimeObserver: Any?
  private var wantsToPlay = false
  private var terminalFailure: PlaybackFailure?

  public init() {
    (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    observeTimeControl()
  }

  public var events: AsyncStream<PlaybackEngineEvent> { stream }

  public func load(_ asset: PlaybackAsset, attemptID: UUID) {
    clearItemObservers()
    self.attemptID = attemptID
    wantsToPlay = false
    terminalFailure = nil
    emit(.loading)

    let item = AVPlayerItem(url: asset.mediaURL)
    player.replaceCurrentItem(with: item)
    observe(item)
  }

  public func play() {
    guard player.currentItem != nil, terminalFailure == nil else { return }
    wantsToPlay = true
    player.play()
  }

  public func pause() {
    guard player.currentItem != nil, terminalFailure == nil else { return }
    wantsToPlay = false
    player.pause()
    emit(.paused)
  }

  public func seek(to seconds: TimeInterval) async {
    guard seconds.isFinite, seconds >= 0, player.currentItem != nil else { return }
    let target = CMTime(seconds: seconds, preferredTimescale: 600)
    await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    emit(player.timeControlStatus == .playing ? .playing : .paused)
  }

  public func stop() {
    wantsToPlay = false
    terminalFailure = nil
    clearItemObservers()
    player.pause()
    player.replaceCurrentItem(with: nil)
    emit(.idle, timeline: PlaybackTimeline())
  }

  #if os(iOS) || os(tvOS)
    public func makePlayerViewController() -> AVPlayerViewController {
      let controller = AVPlayerViewController()
      controller.player = player
      controller.showsPlaybackControls = true
      return controller
    }
  #endif

  nonisolated public static func normalizedFailure(from error: (any Error)?) -> PlaybackFailure {
    guard let error else { return .unknown }
    let nsError = error as NSError
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? URLError {
      return normalizedURLFailure(underlying)
    }
    if let urlError = error as? URLError {
      return normalizedURLFailure(urlError)
    }
    if nsError.domain == NSURLErrorDomain {
      return normalizedURLFailure(URLError(URLError.Code(rawValue: nsError.code)))
    }
    if nsError.domain == AVFoundationErrorDomain {
      switch AVError.Code(rawValue: nsError.code) {
      case .fileFormatNotRecognized, .fileFailedToParse, .decoderNotFound,
        .decoderTemporarilyUnavailable:
        return .unsupportedFormat
      case .contentIsNotAuthorized:
        return .unauthorized
      default:
        return .mediaUnavailable
      }
    }
    return .unknown
  }

  nonisolated private static func normalizedURLFailure(_ error: URLError) -> PlaybackFailure {
    switch error.code {
    case .cancelled:
      return .unknown
    case .appTransportSecurityRequiresSecureConnection,
      .secureConnectionFailed,
      .serverCertificateHasBadDate,
      .serverCertificateHasUnknownRoot,
      .serverCertificateNotYetValid,
      .serverCertificateUntrusted:
      return .transportSecurity
    case .userAuthenticationRequired, .userCancelledAuthentication:
      return .unauthorized
    case .fileDoesNotExist, .resourceUnavailable:
      return .notFound
    case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
      .notConnectedToInternet, .timedOut:
      return .transport
    default:
      return .mediaUnavailable
    }
  }

  private func observe(_ item: AVPlayerItem) {
    itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
      [weak self] item, _ in
      Task { @MainActor [weak self] in self?.itemStatusChanged(item) }
    }
    keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
      [weak self] item, _ in
      Task { @MainActor [weak self] in
        guard let self, self.wantsToPlay, self.terminalFailure == nil else { return }
        self.emit(item.isPlaybackLikelyToKeepUp ? .playing : .buffering)
      }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.wantsToPlay = false
        self?.emit(.ended)
      }
    }
    periodicTimeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 2),
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.player.currentItem != nil, self.terminalFailure == nil else { return }
        let state: PlaybackState =
          self.player.timeControlStatus == .playing
          ? .playing : (self.wantsToPlay ? .buffering : .paused)
        self.emit(state)
      }
    }
  }

  private func observeTimeControl() {
    timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) {
      [weak self] player, _ in
      Task { @MainActor [weak self] in
        guard let self, player.currentItem != nil, self.terminalFailure == nil else { return }
        switch player.timeControlStatus {
        case .playing:
          self.emit(.playing)
        case .waitingToPlayAtSpecifiedRate where self.wantsToPlay:
          self.emit(.buffering)
        case .paused where !self.wantsToPlay:
          self.emit(.paused)
        default:
          break
        }
      }
    }
  }

  private func itemStatusChanged(_ item: AVPlayerItem) {
    switch item.status {
    case .readyToPlay:
      emit(.ready)
    case .failed:
      let failure = Self.normalizedFailure(
        from: item.error,
        statusCode: item.errorLog()?.events.last?.errorStatusCode
      )
      terminalFailure = failure
      wantsToPlay = false
      emit(.failed, failure: failure)
    case .unknown:
      break
    @unknown default:
      terminalFailure = .unknown
      emit(.failed, failure: .unknown)
    }
  }

  nonisolated public static func normalizedFailure(
    from error: (any Error)?,
    statusCode: Int?
  ) -> PlaybackFailure {
    switch statusCode {
    case 401: return .unauthorized
    case 403: return .forbidden
    case 404: return .notFound
    default: return normalizedFailure(from: error)
    }
  }

  private func emit(
    _ state: PlaybackState,
    timeline: PlaybackTimeline? = nil,
    failure: PlaybackFailure? = nil
  ) {
    continuation.yield(
      PlaybackEngineEvent(
        attemptID: attemptID,
        state: state,
        timeline: timeline ?? currentTimeline(),
        failure: failure
      )
    )
  }

  private func currentTimeline() -> PlaybackTimeline {
    guard let item = player.currentItem else { return PlaybackTimeline() }
    let elapsed = player.currentTime().seconds
    let duration = item.duration.seconds
    let finiteDuration = duration.isFinite && duration > 0 ? duration : nil
    return PlaybackTimeline(
      elapsed: elapsed.isFinite && elapsed >= 0 ? elapsed : 0,
      duration: finiteDuration,
      isSeekable: finiteDuration != nil && !item.seekableTimeRanges.isEmpty
    )
  }

  private func clearItemObservers() {
    itemStatusObservation?.invalidate()
    itemStatusObservation = nil
    keepUpObservation?.invalidate()
    keepUpObservation = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    if let periodicTimeObserver {
      player.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
    }
  }
}
