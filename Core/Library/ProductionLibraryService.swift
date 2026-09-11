import Domain
import Foundation
import Persistence

public enum LibraryBrowseScope: String, CaseIterable, Hashable, Sendable {
  case library
  case movies
  case series
  case liveTV
  case playlist
  case search
}

public struct LibrarySourcePresentation: Identifiable, Equatable, Hashable, Sendable {
  public let id: SourceConfiguration.ID
  public let name: String
  public let isEnabled: Bool

  public init(id: SourceConfiguration.ID, name: String, isEnabled: Bool) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
  }
}

public struct LibraryCategoryID: Hashable, Sendable {
  public let rawValue: String
  public let sourceID: SourceConfiguration.ID
  public let origin: CatalogOrigin
  public let kind: CatalogMediaKind

  public init(rawValue: String, scope: CatalogScope) {
    self.rawValue = rawValue
    sourceID = scope.sourceID
    origin = scope.origin
    kind = scope.kind
  }

  public var scope: CatalogScope {
    CatalogScope(sourceID: sourceID, origin: origin, kind: kind)
  }
}

public struct LibraryCategoryPresentation: Identifiable, Equatable, Hashable, Sendable {
  public let id: LibraryCategoryID
  public let title: String
  public let itemCount: Int

  public init(id: LibraryCategoryID, title: String, itemCount: Int) {
    self.id = id
    self.title = title
    self.itemCount = itemCount
  }
}

/// Contains only committed catalog metadata that is safe and useful to present.
public struct LibraryItemPresentation: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let mediaKind: CatalogMediaKind
  public let sourceID: SourceConfiguration.ID
  public let sourceName: String
  public let categoryID: String?
  public let categoryTitle: String?
  public let artworkURL: URL?

  public init(
    id: String,
    title: String,
    mediaKind: CatalogMediaKind,
    sourceID: SourceConfiguration.ID,
    sourceName: String,
    categoryID: String?,
    categoryTitle: String?,
    artworkURL: URL?
  ) {
    self.id = id
    self.title = title
    self.mediaKind = mediaKind
    self.sourceID = sourceID
    self.sourceName = sourceName
    self.categoryID = categoryID
    self.categoryTitle = categoryTitle
    self.artworkURL = artworkURL
  }
}

public struct ProductionLibraryContext: Equatable, Sendable {
  public let sources: [LibrarySourcePresentation]
  public let committedCatalogCount: Int
  public let itemCount: Int

  public init(
    sources: [LibrarySourcePresentation], committedCatalogCount: Int, itemCount: Int
  ) {
    self.sources = sources
    self.committedCatalogCount = committedCatalogCount
    self.itemCount = itemCount
  }
}

public struct LibraryQuery: Equatable, Hashable, Sendable {
  public let scope: LibraryBrowseScope
  public let sourceID: SourceConfiguration.ID?
  public let category: LibraryCategoryPresentation?
  public let searchText: String

  public init(
    scope: LibraryBrowseScope = .library,
    sourceID: SourceConfiguration.ID? = nil,
    category: LibraryCategoryPresentation? = nil,
    searchText: String = ""
  ) {
    self.scope = scope
    self.sourceID = sourceID
    self.category = category
    self.searchText = searchText
  }
}

public enum ProductionLibraryError: Error, Equatable, Sendable {
  case unavailable
  case invalidRequest
}

public struct LibraryPageRequest: Equatable, Sendable {
  public static let maximumSize = CatalogPage.maximumSize
  public let limit: Int
  public let offset: Int

  public init(limit: Int = 64, offset: Int = 0) {
    self.limit = min(max(limit, 1), Self.maximumSize)
    self.offset = max(offset, 0)
  }

  fileprivate func catalogPage() throws -> CatalogPage {
    try CatalogPage(limit: limit, offset: offset)
  }
}

public protocol ProductionLibraryServing: Sendable {
  func context() async throws -> ProductionLibraryContext
  func items(matching query: LibraryQuery, page: LibraryPageRequest) async throws
    -> [LibraryItemPresentation]
  func categories(matching query: LibraryQuery, page: LibraryPageRequest) async throws
    -> [LibraryCategoryPresentation]
  func revisions() async -> AsyncStream<UInt64>
}

public actor LibraryRevisionCenter {
  private var revision: UInt64 = 0
  private var continuations: [UUID: AsyncStream<UInt64>.Continuation] = [:]

  public init() {}

  public func publish(sourceID _: SourceConfiguration.ID) {
    revision &+= 1
    for continuation in continuations.values { continuation.yield(revision) }
  }

  public func stream() -> AsyncStream<UInt64> {
    let identifier = UUID()
    let (stream, continuation) = AsyncStream<UInt64>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    continuations[identifier] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeContinuation(identifier) }
    }
    return stream
  }

  private func removeContinuation(_ identifier: UUID) {
    continuations.removeValue(forKey: identifier)
  }
}

/// Joins safe source display metadata to bounded committed-catalog queries.
public actor ProductionLibraryService: ProductionLibraryServing {
  private let catalog: any CatalogLibraryQuerying
  private let sourceService: any SourceManaging
  private let revisionCenter: LibraryRevisionCenter
  private var sourceNames: [SourceConfiguration.ID: String] = [:]

  public init(
    catalog: any CatalogLibraryQuerying,
    sourceService: any SourceManaging,
    revisionCenter: LibraryRevisionCenter = LibraryRevisionCenter()
  ) {
    self.catalog = catalog
    self.sourceService = sourceService
    self.revisionCenter = revisionCenter
  }

  public func context() async throws -> ProductionLibraryContext {
    do {
      async let managedSources = sourceService.listSources()
      async let catalogCount = catalog.sourceCatalogCount(sourceID: nil)
      async let itemCount = catalog.itemCount(matching: CatalogFilter())
      let (managed, committedCount, totalItems) = try await (
        managedSources, catalogCount, itemCount
      )
      let sources = managed.map {
        LibrarySourcePresentation(
          id: $0.id,
          name: $0.configuration.displayName,
          isEnabled: $0.configuration.isEnabled
        )
      }
      sourceNames = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
      return ProductionLibraryContext(
        sources: sources,
        committedCatalogCount: committedCount,
        itemCount: totalItems
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ProductionLibraryError.unavailable
    }
  }

  public func items(matching query: LibraryQuery, page: LibraryPageRequest) async throws
    -> [LibraryItemPresentation]
  {
    if query.scope == .search,
      query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return []
    }
    let filter = Self.filter(for: query)
    do {
      let catalogItems =
        if query.scope == .search {
          try await catalog.searchItems(
            query.searchText, matching: filter, page: page.catalogPage())
        } else {
          try await catalog.browseItems(matching: filter, page: page.catalogPage())
        }
      let names = try await resolvedSourceNames()
      return catalogItems.map { item in
        LibraryItemPresentation(
          id: item.id,
          title: item.title,
          mediaKind: item.scope.kind,
          sourceID: item.scope.sourceID,
          sourceName: names[item.scope.sourceID] ?? "",
          categoryID: item.categoryID,
          categoryTitle: query.category?.id.rawValue == item.categoryID
            ? query.category?.title : nil,
          artworkURL: item.artworkURL
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as CatalogStoreError where error == .invalidInput {
      throw ProductionLibraryError.invalidRequest
    } catch {
      throw ProductionLibraryError.unavailable
    }
  }

  public func categories(matching query: LibraryQuery, page: LibraryPageRequest) async throws
    -> [LibraryCategoryPresentation]
  {
    do {
      return try await catalog.categories(
        matching: Self.filter(for: query, includeCategory: false), page: page.catalogPage()
      )
      .map {
        LibraryCategoryPresentation(
          id: LibraryCategoryID(rawValue: $0.category.id, scope: $0.category.scope),
          title: $0.category.title,
          itemCount: $0.itemCount
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ProductionLibraryError.unavailable
    }
  }

  public func revisions() async -> AsyncStream<UInt64> {
    await revisionCenter.stream()
  }

  private func resolvedSourceNames() async throws -> [SourceConfiguration.ID: String] {
    if !sourceNames.isEmpty { return sourceNames }
    let sources = try await sourceService.listSources()
    let names = Dictionary(
      uniqueKeysWithValues: sources.map {
        ($0.id, $0.configuration.displayName)
      })
    sourceNames = names
    return names
  }

  private static func filter(for query: LibraryQuery, includeCategory: Bool = true) -> CatalogFilter
  {
    if includeCategory, let category = query.category {
      return CatalogFilter(
        sourceID: category.id.sourceID,
        origin: category.id.origin,
        kind: category.id.kind,
        categoryID: category.id.rawValue
      )
    }
    switch query.scope {
    case .library, .search:
      return CatalogFilter(sourceID: query.sourceID)
    case .movies:
      return CatalogFilter(sourceID: query.sourceID, origin: .xtream, kind: .vod)
    case .series:
      return CatalogFilter(sourceID: query.sourceID, origin: .xtream, kind: .series)
    case .liveTV:
      return CatalogFilter(sourceID: query.sourceID, origin: .xtream, kind: .live)
    case .playlist:
      return CatalogFilter(sourceID: query.sourceID, origin: .m3u, kind: .unspecified)
    }
  }
}

public struct LibraryPageSnapshot: Equatable, Sendable {
  public let query: LibraryQuery
  public let items: [LibraryItemPresentation]
  public let isLoading: Bool
  public let hasMore: Bool
  public let error: ProductionLibraryError?
  public let nextOffset: Int

  public init(
    query: LibraryQuery,
    items: [LibraryItemPresentation],
    isLoading: Bool,
    hasMore: Bool,
    error: ProductionLibraryError?,
    nextOffset: Int
  ) {
    self.query = query
    self.items = items
    self.isLoading = isLoading
    self.hasMore = hasMore
    self.error = error
    self.nextOffset = nextOffset
  }
}

/// A cancellation-safe, offset-paged state machine with a bounded presentation window.
public actor LibraryPagingController {
  public static let defaultPageSize = 64
  public static let defaultMaximumLoadedItems = 256

  private let service: any ProductionLibraryServing
  private let pageSize: Int
  private let maximumLoadedItems: Int
  private var generation: UInt64 = 0
  private var current: LibraryPageSnapshot
  private var activeRequest: Task<[LibraryItemPresentation], Error>?

  public init(
    service: any ProductionLibraryServing,
    pageSize: Int = defaultPageSize,
    maximumLoadedItems: Int = defaultMaximumLoadedItems
  ) {
    let safePageSize = min(max(pageSize, 1), LibraryPageRequest.maximumSize)
    self.service = service
    self.pageSize = safePageSize
    self.maximumLoadedItems = max(maximumLoadedItems, safePageSize)
    current = LibraryPageSnapshot(
      query: LibraryQuery(), items: [], isLoading: false, hasMore: true, error: nil,
      nextOffset: 0)
  }

  public func snapshot() -> LibraryPageSnapshot { current }

  public func restart(
    query: LibraryQuery,
    protecting itemID: LibraryItemPresentation.ID? = nil
  ) async -> LibraryPageSnapshot {
    activeRequest?.cancel()
    generation &+= 1
    let requestGeneration = generation
    current = LibraryPageSnapshot(
      query: query, items: [], isLoading: true, hasMore: true, error: nil, nextOffset: 0)
    return await requestPage(generation: requestGeneration, protecting: itemID)
  }

  public func loadNext(
    protecting itemID: LibraryItemPresentation.ID? = nil
  ) async -> LibraryPageSnapshot {
    guard !current.isLoading, current.hasMore else { return current }
    current = LibraryPageSnapshot(
      query: current.query,
      items: current.items,
      isLoading: true,
      hasMore: current.hasMore,
      error: nil,
      nextOffset: current.nextOffset
    )
    return await requestPage(generation: generation, protecting: itemID)
  }

  private func requestPage(
    generation requestGeneration: UInt64,
    protecting itemID: LibraryItemPresentation.ID?
  ) async -> LibraryPageSnapshot {
    let query = current.query
    let offset = current.nextOffset
    do {
      let page = LibraryPageRequest(limit: pageSize, offset: offset)
      let service = service
      let request = Task {
        try await service.items(matching: query, page: page)
      }
      activeRequest = request
      let received = try await withTaskCancellationHandler {
        try await request.value
      } onCancel: {
        request.cancel()
      }
      guard requestGeneration == generation, query == current.query else { return current }
      activeRequest = nil
      let existingIDs = Set(current.items.map(\.id))
      let unique = received.filter { !existingIDs.contains($0.id) }
      var loaded = current.items + unique
      if loaded.count > maximumLoadedItems {
        let removalCount = loaded.count - maximumLoadedItems
        let removalIndices = loaded.indices.filter { loaded[$0].id != itemID }.prefix(removalCount)
        for index in removalIndices.reversed() { loaded.remove(at: index) }
      }
      current = LibraryPageSnapshot(
        query: query,
        items: loaded,
        isLoading: false,
        hasMore: received.count == pageSize,
        error: nil,
        nextOffset: offset + received.count
      )
    } catch is CancellationError {
      if requestGeneration == generation {
        activeRequest = nil
        current = LibraryPageSnapshot(
          query: query,
          items: current.items,
          isLoading: false,
          hasMore: current.hasMore,
          error: nil,
          nextOffset: current.nextOffset
        )
      }
    } catch let error as ProductionLibraryError {
      if requestGeneration == generation {
        activeRequest = nil
        current = LibraryPageSnapshot(
          query: query,
          items: current.items,
          isLoading: false,
          hasMore: current.hasMore,
          error: error,
          nextOffset: current.nextOffset
        )
      }
    } catch {
      if requestGeneration == generation {
        activeRequest = nil
        current = LibraryPageSnapshot(
          query: query,
          items: current.items,
          isLoading: false,
          hasMore: current.hasMore,
          error: .unavailable,
          nextOffset: current.nextOffset
        )
      }
    }
    return current
  }
}
