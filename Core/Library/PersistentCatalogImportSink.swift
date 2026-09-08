import Domain
import Foundation
import Persistence

/// Construct a sink per import operation; the repository arbitrates concurrent replacements.
public actor PersistentCatalogImportSink: M3UImportSink, ProviderCatalogImportSink,
  ProviderCategoryImportSink
{
  private let repository: any CatalogImportRepository
  private var transaction: UUID?
  private var scope: CatalogScope?
  private var starting = false

  public init(repository: any CatalogImportRepository) { self.repository = repository }

  public func beginImport(for sourceID: SourceConfiguration.ID) async throws {
    try await begin(CatalogScope(sourceID: sourceID, origin: .m3u, kind: .unspecified))
  }

  public func beginImport(for sourceID: SourceConfiguration.ID, kind: ProviderMediaKind)
    async throws
  {
    try await begin(CatalogScope(sourceID: sourceID, origin: .xtream, kind: CatalogMediaKind(kind)))
  }

  private func begin(_ scope: CatalogScope) async throws {
    guard transaction == nil, !starting else { throw CatalogStoreError.busy }
    starting = true
    defer { starting = false }
    transaction = try await repository.beginReplacement(in: scope)
    self.scope = scope
  }

  public func write(_ items: [ImportedMediaItem]) async throws {
    let (transaction, scope) = try session()
    guard items.count <= CatalogPage.maximumSize else { throw CatalogStoreError.invalidInput }
    var categories: [String: CatalogCategory] = [:]
    let values = items.map { item in
      let categoryID = item.groupTitle.map { title in
        ImportedMediaItem.ID(
          sourceID: item.sourceID, stableKey: "m3u-group:\(title)", occurrence: 0
        ).rawValue
      }
      if let categoryID, let title = item.groupTitle {
        categories[categoryID] = CatalogCategory(id: categoryID, scope: scope, title: title)
      }
      return CatalogItem(
        id: item.id.rawValue,
        scope: CatalogScope(sourceID: item.sourceID, origin: .m3u, kind: .unspecified),
        title: item.title, categoryID: categoryID, artworkURL: item.artworkURL,
        mediaURL: item.mediaURL)
    }
    try await repository.write(
      items: values, categories: Array(categories.values), transaction: transaction)
  }

  public func write(_ items: [ProviderCatalogItem]) async throws {
    let (transaction, _) = try session()
    guard items.count <= CatalogPage.maximumSize else { throw CatalogStoreError.invalidInput }
    try await repository.write(
      items: items.map { item in
        CatalogItem(
          id: item.id.rawValue,
          scope: CatalogScope(
            sourceID: item.sourceID, origin: .xtream,
            kind: CatalogMediaKind(item.providerReference.kind)),
          title: item.title, categoryID: item.categoryID?.rawValue, artworkURL: item.artworkURL,
          providerReference: item.providerReference)
      }, categories: [], transaction: transaction)
  }

  public func writeCategories(_ categories: [ProviderCategory]) async throws {
    let (transaction, _) = try session()
    guard categories.count <= CatalogPage.maximumSize else { throw CatalogStoreError.invalidInput }
    try await repository.write(
      items: [],
      categories: categories.map { category in
        CatalogCategory(
          id: category.id.rawValue,
          scope: CatalogScope(
            sourceID: category.sourceID, origin: .xtream, kind: CatalogMediaKind(category.kind)),
          title: category.title)
      }, transaction: transaction)
  }

  public func commitImport() async throws {
    let (transaction, _) = try session()
    try await repository.commit(transaction: transaction)
    self.transaction = nil
    scope = nil
  }

  public func rollbackImport() async {
    guard let transaction else { return }
    await repository.rollback(transaction: transaction)
    self.transaction = nil
    scope = nil
  }

  private func session() throws -> (UUID, CatalogScope) {
    guard let transaction, let scope else { throw CatalogStoreError.invalidTransaction }
    return (transaction, scope)
  }
}
