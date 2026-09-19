import Domain
import Foundation
import Library

/// Deterministic synthetic favorites for tvOS automation; production keeps one repository boundary.
actor TVFavoritesFixture: FavoritesServing {
  private var values: [FavoriteItemPresentation]
  private let revisionsCenter = FavoritesRevisionCenter()
  init(arguments: [String]) {
    if arguments.contains("--ui-favorites-empty") {
      values = []
    } else if arguments.contains("--ui-favorites-single") {
      values = [Self.first]
    } else {
      values = [Self.first, Self.second]
    }
  }
  static func service(arguments: [String]) -> FavoritesViewModel.ServiceFactory {
    let fixture = TVFavoritesFixture(arguments: arguments)
    return { fixture }
  }
  func items() -> [FavoriteItemPresentation] { values }
  func isFavorite(mediaID: String) -> Bool { values.contains { $0.id == mediaID } }
  func toggle(mediaID: String, at _: Date) -> Bool {
    if let index = values.firstIndex(where: { $0.id == mediaID }) {
      values.remove(at: index)
      Task { await revisionsCenter.publish() }
      return false
    }
    if mediaID == Self.second.id {
      values.append(Self.second)
    } else {
      values.append(Self.first)
    }
    Task { await revisionsCenter.publish() }
    return true
  }
  func revisions() async -> AsyncStream<UInt64> { await revisionsCenter.stream() }
  private static let first = FavoriteItemPresentation(
    id: "movie-1", title: "Amber Coast", mediaKind: .vod,
    sourceID: SourceConfiguration.ID(
      rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1))),
    artworkURL: nil)
  private static let second = FavoriteItemPresentation(
    id: "movie-2", title: "Blue Orchard", mediaKind: .vod,
    sourceID: SourceConfiguration.ID(
      rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1))),
    artworkURL: nil)
}
