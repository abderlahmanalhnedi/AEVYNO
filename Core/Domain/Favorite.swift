import Foundation

/// Durable user-authored favorite state keyed only by stable catalog identity.
public struct Favorite: Codable, Equatable, Sendable, Identifiable {
  public let mediaID: String
  public let updatedAt: Date

  public var id: String { mediaID }

  public init(mediaID: String, updatedAt: Date) {
    self.mediaID = mediaID
    self.updatedAt = updatedAt
  }
}

public protocol FavoriteRepository: Sendable {
  func favorite(for mediaID: String) async throws -> Favorite?
  func allFavorites() async throws -> [Favorite]
  func add(_ favorite: Favorite) async throws
  func remove(mediaID: String) async throws
}
