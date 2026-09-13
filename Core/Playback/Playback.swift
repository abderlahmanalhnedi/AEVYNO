import AVFoundation
import Domain
import Foundation

#if os(iOS) || os(tvOS)
  import AVKit
#endif

public enum PlaybackState: String, Codable, Equatable, Sendable {
  case idle
  case loading
  case ready
  case playing
  case paused
  case buffering
  case ended
  case failed
}

public enum PlaybackFailure: String, Codable, Error, Equatable, Sendable,
  CustomStringConvertible
{
  case sourceUnavailable
  case itemUnavailable
  case unsupported
  case transport
  case unauthorized
  case forbidden
  case notFound
  case mediaUnavailable
  case unsupportedFormat
  case transportSecurity
  case unknown

  public var description: String { "PlaybackFailure(\(rawValue))" }
}

public enum PlaybackAvailability: Equatable, Sendable {
  case playable
  case unavailable(PlaybackFailure)
}

/// A short-lived resolved asset. Its URL is package-only so application UI cannot read it.
public struct PlaybackAsset: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let mediaID: String
  public let title: String
  public let catalogKind: CatalogMediaKind
  package let mediaURL: URL

  public init(
    mediaID: String,
    title: String,
    catalogKind: CatalogMediaKind,
    mediaURL: URL
  ) {
    self.mediaID = mediaID
    self.title = title
    self.catalogKind = catalogKind
    self.mediaURL = mediaURL
  }

  public var description: String {
    "PlaybackAsset(mediaID: \(mediaID), kind: \(catalogKind.rawValue), url: <redacted>)"
  }

  public var debugDescription: String { description }
}

public protocol PlaybackAssetResolving: Sendable {
  func availability(for mediaID: String) async -> PlaybackAvailability
  func resolve(mediaID: String) async throws -> PlaybackAsset
}

public struct PlaybackTimeline: Equatable, Sendable {
  public let elapsed: TimeInterval
  public let duration: TimeInterval?
  public let isSeekable: Bool

  public init(elapsed: TimeInterval = 0, duration: TimeInterval? = nil, isSeekable: Bool = false) {
    self.elapsed = elapsed
    self.duration = duration
    self.isSeekable = isSeekable
  }
}

public struct PlaybackEngineEvent: Equatable, Sendable {
  public let attemptID: UUID
  public let state: PlaybackState
  public let timeline: PlaybackTimeline
  public let failure: PlaybackFailure?

  public init(
    attemptID: UUID,
    state: PlaybackState,
    timeline: PlaybackTimeline = PlaybackTimeline(),
    failure: PlaybackFailure? = nil
  ) {
    self.attemptID = attemptID
    self.state = state
    self.timeline = timeline
    self.failure = failure
  }
}

@MainActor
public protocol PlaybackEngine: AnyObject {
  var events: AsyncStream<PlaybackEngineEvent> { get }
  func load(_ asset: PlaybackAsset, attemptID: UUID)
  func play()
  func pause()
  func seek(to seconds: TimeInterval) async
  func stop()
  #if os(iOS) || os(tvOS)
    func makePlayerViewController() -> AVPlayerViewController
  #endif
}

public enum PlaybackCompletionPolicy {
  public static let threshold = 0.95

  public static func isCompleted(position: TimeInterval, duration: TimeInterval) -> Bool {
    guard position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return false }
    return position / duration >= threshold
  }

  public static func clampedResumePosition(
    _ position: TimeInterval,
    duration: TimeInterval
  ) -> TimeInterval? {
    guard
      position.isFinite,
      duration.isFinite,
      position > 0,
      duration > 0,
      !isCompleted(position: position, duration: duration)
    else { return nil }
    return min(position, duration)
  }
}
