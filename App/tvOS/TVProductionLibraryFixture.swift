import Domain
import Foundation
import Library

actor TVProductionLibraryFixture: ProductionLibraryServing {
  private let scenario: Scenario
  private var hasPublishedRefresh = false
  private let sourceA = SourceConfiguration.ID(
    rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1)))
  private let sourceB = SourceConfiguration.ID(
    rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2)))

  enum Scenario {
    case noSources
    case noCatalog
    case catalog
    case pagination
    case refresh
    case failure
  }

  static func fixture(arguments: [String]) -> TVProductionLibraryFixture? {
    if arguments.contains("--ui-production-no-sources") {
      return TVProductionLibraryFixture(scenario: .noSources)
    }
    if arguments.contains("--ui-production-no-catalog") {
      return TVProductionLibraryFixture(scenario: .noCatalog)
    }
    if arguments.contains("--ui-production-error") {
      return TVProductionLibraryFixture(scenario: .failure)
    }
    if arguments.contains("--ui-production-catalog")
      || arguments.contains("--ui-production-search-results")
      || arguments.contains("--ui-production-search-empty")
      || arguments.contains("--ui-production-search-arabic")
    {
      return TVProductionLibraryFixture(scenario: .catalog)
    }
    if arguments.contains("--ui-production-pagination") {
      return TVProductionLibraryFixture(scenario: .pagination)
    }
    if arguments.contains("--ui-production-refresh") {
      return TVProductionLibraryFixture(scenario: .refresh)
    }
    return nil
  }

  static func initialQuery(arguments: [String]) -> LibraryQuery {
    if arguments.contains("--ui-production-search-results") {
      return LibraryQuery(scope: .search, searchText: "Quiet")
    }
    if arguments.contains("--ui-production-search-empty") {
      return LibraryQuery(scope: .search, searchText: "no-such-title")
    }
    if arguments.contains("--ui-production-search-arabic") {
      return LibraryQuery(scope: .search, searchText: "الندى")
    }
    return LibraryQuery()
  }

  init(scenario: Scenario) {
    self.scenario = scenario
  }

  func context() throws -> ProductionLibraryContext {
    if scenario == .failure { throw ProductionLibraryError.unavailable }
    if scenario == .noSources {
      return ProductionLibraryContext(sources: [], committedCatalogCount: 0, itemCount: 0)
    }
    return ProductionLibraryContext(
      sources: sources,
      committedCatalogCount: scenario == .noCatalog ? 0 : 4,
      itemCount: scenario == .noCatalog ? 0 : allItems.count
    )
  }

  func items(matching query: LibraryQuery, page: LibraryPageRequest) throws
    -> [LibraryItemPresentation]
  {
    if scenario == .failure { throw ProductionLibraryError.unavailable }
    var values = allItems
    if let sourceID = query.sourceID { values = values.filter { $0.sourceID == sourceID } }
    switch query.scope {
    case .movies: values = values.filter { $0.mediaKind == .vod }
    case .series: values = values.filter { $0.mediaKind == .series }
    case .liveTV: values = values.filter { $0.mediaKind == .live }
    case .playlist: values = values.filter { $0.mediaKind == .unspecified }
    case .search:
      let terms = query.searchText.lowercased().split(whereSeparator: \.isWhitespace)
      values = values.filter { item in
        terms.allSatisfy { item.title.lowercased().contains($0) }
      }
    case .library: break
    }
    if let category = query.category {
      values = values.filter {
        $0.sourceID == category.id.sourceID && $0.categoryID == category.id.rawValue
      }
    }
    values = values.map { item in
      LibraryItemPresentation(
        id: item.id,
        title: item.title,
        mediaKind: item.mediaKind,
        sourceID: item.sourceID,
        sourceName: item.sourceName,
        categoryID: item.categoryID,
        categoryTitle: query.category?.id.rawValue == item.categoryID
          ? query.category?.title : nil,
        artworkURL: item.artworkURL
      )
    }
    guard page.offset < values.count else { return [] }
    return Array(values[page.offset..<min(values.count, page.offset + page.limit)])
  }

  func categories(matching query: LibraryQuery, page _: LibraryPageRequest)
    -> [LibraryCategoryPresentation]
  {
    let values = categoryValues.filter { category in
      guard query.sourceID == nil || query.sourceID == category.id.sourceID else { return false }
      switch query.scope {
      case .movies: return category.id.kind == .vod
      case .series: return category.id.kind == .series
      case .liveTV: return category.id.kind == .live
      case .playlist: return category.id.kind == .unspecified
      case .library, .search: return true
      }
    }
    return values
  }

  func revisions() -> AsyncStream<UInt64> {
    guard scenario == .refresh else { return AsyncStream { $0.finish() } }
    return AsyncStream { continuation in
      let task = Task {
        do {
          try await Task.sleep(for: .seconds(1))
          hasPublishedRefresh = true
          continuation.yield(1)
          continuation.finish()
        } catch {
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private var sources: [LibrarySourcePresentation] {
    return [
      LibrarySourcePresentation(id: sourceA, name: "North Library", isEnabled: true),
      LibrarySourcePresentation(id: sourceB, name: "Family Playlist", isEnabled: false),
    ]
  }

  private var categoryValues: [LibraryCategoryPresentation] {
    if scenario == .pagination {
      return [
        category(
          id: "film", title: "Cinema", count: 130, source: sourceA, origin: .xtream,
          kind: .vod)
      ]
    }
    return [
      category(id: "film", title: "Cinema", count: 2, source: sourceA, origin: .xtream, kind: .vod),
      category(
        id: "series", title: "Drama", count: 2, source: sourceA, origin: .xtream, kind: .series),
      category(id: "live", title: "News", count: 1, source: sourceA, origin: .xtream, kind: .live),
      category(
        id: "m3u", title: "Mixed", count: 1, source: sourceB, origin: .m3u, kind: .unspecified),
    ]
  }

  private var allItems: [LibraryItemPresentation] {
    if scenario == .pagination {
      return (0..<130).map { index in
        item(
          String(format: "page-%03d", index),
          String(format: "Paged title %03d", index),
          .vod,
          sourceA,
          "North Library",
          "film",
          "Cinema"
        )
      }
    }
    if scenario == .refresh {
      var items = [
        item(
          "refresh-stable", "Stable Before and After Refresh", .vod, sourceA, "North Library",
          "film", "Cinema")
      ]
      if hasPublishedRefresh {
        items.append(
          item(
            "refresh-new", "Published by Refresh", .vod, sourceA, "North Library", "film",
            "Cinema"))
      }
      return items
    }
    return [
      item("movie-1", "Amber Coast", .vod, sourceA, "North Library", "film", "Cinema"),
      item("movie-2", "Blue Orchard", .vod, sourceA, "North Library", "film", "Cinema"),
      item("series-1", "Quiet District", .series, sourceA, "North Library", "series", "Drama"),
      item(
        "series-ar", "حي الندى AEVYNO ٢٠٢٦", .series, sourceA, "North Library", "series", "Drama"),
      item("live-1", "World Desk", .live, sourceA, "North Library", "live", "News"),
      item(
        "m3u-1", "Movie Night Live.m3u8", .unspecified, sourceB, "Family Playlist", "m3u", "Mixed"),
    ]
  }

  private func item(
    _ id: String,
    _ title: String,
    _ kind: CatalogMediaKind,
    _ sourceID: SourceConfiguration.ID,
    _ sourceName: String,
    _ categoryID: String,
    _ categoryTitle: String
  ) -> LibraryItemPresentation {
    LibraryItemPresentation(
      id: id,
      title: title,
      mediaKind: kind,
      sourceID: sourceID,
      sourceName: sourceName,
      categoryID: categoryID,
      categoryTitle: categoryTitle,
      artworkURL: nil
    )
  }

  private func category(
    id: String,
    title: String,
    count: Int,
    source: SourceConfiguration.ID,
    origin: CatalogOrigin,
    kind: CatalogMediaKind
  ) -> LibraryCategoryPresentation {
    let scope = CatalogScope(sourceID: source, origin: origin, kind: kind)
    return LibraryCategoryPresentation(
      id: LibraryCategoryID(rawValue: id, scope: scope), title: title, itemCount: count)
  }
}
