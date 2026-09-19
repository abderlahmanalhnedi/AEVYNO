import Domain
import Foundation

public struct FavoriteItemPresentation: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let mediaKind: CatalogMediaKind
  public let sourceID: SourceConfiguration.ID
  public let artworkURL: URL?

  public init(
    id: String,
    title: String,
    mediaKind: CatalogMediaKind,
    sourceID: SourceConfiguration.ID,
    artworkURL: URL?
  ) {
    self.id = id
    self.title = title
    self.mediaKind = mediaKind
    self.sourceID = sourceID
    self.artworkURL = artworkURL
  }
}

public protocol FavoritesServing: Sendable {
  func items() async throws -> [FavoriteItemPresentation]
  func isFavorite(mediaID: String) async throws -> Bool
  func toggle(mediaID: String, at: Date) async throws -> Bool
  func revisions() async -> AsyncStream<UInt64>
}

public actor FavoritesRevisionCenter {
  private var revision: UInt64 = 0
  private var continuations: [UUID: AsyncStream<UInt64>.Continuation] = [:]
  public init() {}
  public func publish() {
    revision &+= 1
    for continuation in continuations.values { continuation.yield(revision) }
  }
  public func stream() -> AsyncStream<UInt64> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<UInt64>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    continuations[id] = continuation
    continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
    return stream
  }
  private func remove(_ id: UUID) { continuations.removeValue(forKey: id) }
}

/// Bounded composition of durable favorite identities and current committed catalog metadata.
public actor ProductionFavoritesService: FavoritesServing {
  public static let defaultMaximumItems = 20
  private let catalog: any CatalogLibraryQuerying
  private let repository: any FavoriteRepository
  private let maximumItems: Int
  private let revisionsCenter: FavoritesRevisionCenter
  private let catalogRevisions: LibraryRevisionCenter

  public init(
    catalog: any CatalogLibraryQuerying, repository: any FavoriteRepository,
    maximumItems: Int = defaultMaximumItems,
    revisionsCenter: FavoritesRevisionCenter = FavoritesRevisionCenter(),
    catalogRevisions: LibraryRevisionCenter = LibraryRevisionCenter()
  ) {
    self.catalog = catalog
    self.repository = repository
    self.maximumItems = min(max(maximumItems, 1), Self.defaultMaximumItems)
    self.revisionsCenter = revisionsCenter
    self.catalogRevisions = catalogRevisions
  }

  public func items() async throws -> [FavoriteItemPresentation] {
    let favorites = try await repository.allFavorites().sorted {
      $0.updatedAt == $1.updatedAt ? $0.mediaID < $1.mediaID : $0.updatedAt > $1.updatedAt
    }
    var result: [FavoriteItemPresentation] = []
    for favorite in favorites where result.count < maximumItems {
      try Task.checkCancellation()
      guard let item = try? await catalog.item(id: favorite.mediaID) else { continue }
      guard !result.contains(where: { $0.id == item.id }) else { continue }
      result.append(
        .init(
          id: item.id,
          title: item.title,
          mediaKind: item.scope.kind,
          sourceID: item.scope.sourceID,
          artworkURL: item.artworkURL
        ))
    }
    return result
  }

  public func isFavorite(mediaID: String) async throws -> Bool {
    try await repository.favorite(for: mediaID) != nil
  }

  public func toggle(mediaID: String, at: Date = Date()) async throws -> Bool {
    if try await repository.favorite(for: mediaID) != nil {
      try await repository.remove(mediaID: mediaID)
      await revisionsCenter.publish()
      return false
    }
    try await repository.add(Favorite(mediaID: mediaID, updatedAt: at))
    await revisionsCenter.publish()
    return true
  }

  public func revisions() async -> AsyncStream<UInt64> {
    let favoriteRevisions = await revisionsCenter.stream()
    let committedCatalogRevisions = await catalogRevisions.stream()
    return AsyncStream { continuation in
      let favoriteTask = Task {
        for await revision in favoriteRevisions { continuation.yield(revision) }
      }
      let catalogTask = Task {
        for await revision in committedCatalogRevisions { continuation.yield(revision) }
      }
      continuation.onTermination = { _ in
        favoriteTask.cancel()
        catalogTask.cancel()
      }
    }
  }
}
