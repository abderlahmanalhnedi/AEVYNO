import Domain
import Foundation
import Persistence

/// Provider-neutral, UI-independent access to the committed local catalog.
public struct CatalogLibraryService: Sendable {
  private let repository: any CatalogQueryRepository

  public init(repository: any CatalogQueryRepository) {
    self.repository = repository
  }

  public func browseItems(
    matching filter: CatalogFilter = CatalogFilter(), page: CatalogPage
  ) async throws -> [CatalogItem] {
    try await repository.items(matching: filter, page: page)
  }

  public func searchItems(
    _ text: String, matching filter: CatalogFilter = CatalogFilter(), page: CatalogPage
  ) async throws -> [CatalogItem] {
    try await repository.searchItems(
      matching: filter, query: CatalogSearchQuery(text), page: page)
  }

  public func categories(
    matching filter: CatalogFilter = CatalogFilter(), page: CatalogPage
  ) async throws -> [CatalogCategorySummary] {
    try await repository.categorySummaries(matching: filter, page: page)
  }

  public func item(id: String) async throws -> CatalogItem? {
    try await repository.item(id: id)
  }

  public func itemCount(matching filter: CatalogFilter = CatalogFilter()) async throws -> Int {
    try await repository.itemCount(matching: filter)
  }

  public func sourceCatalogCount(sourceID: SourceConfiguration.ID? = nil) async throws -> Int {
    try await repository.sourceCatalogCount(sourceID: sourceID)
  }
}
