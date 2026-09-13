import Foundation

/// Durable user-authored playback state keyed only by stable catalog identity.
public struct WatchProgress: Codable, Equatable, Sendable {
  public let mediaID: String
  public let position: TimeInterval
  public let duration: TimeInterval
  public let updatedAt: Date
  public let isCompleted: Bool

  public init(
    mediaID: String,
    position: TimeInterval,
    duration: TimeInterval,
    updatedAt: Date,
    isCompleted: Bool
  ) {
    self.mediaID = mediaID
    self.position = position
    self.duration = duration
    self.updatedAt = updatedAt
    self.isCompleted = isCompleted
  }
}
