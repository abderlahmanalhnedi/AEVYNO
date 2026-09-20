import Domain
import Foundation
import Persistence

/// Construct a sink per import operation; the repository arbitrates concurrent replacements.
public actor PersistentCatalogImportSink: M3UImportSink, ProviderCatalogImportSink,
  ProviderCategoryImportSink
{
  private let repository: any CatalogImportRepository
  private var stagingID: UUID?
  private var scope: CatalogScope?
  private var starting = false
  private let deferredScope: CatalogScope?
  private let deferredStagingID: UUID?

  public init(repository: any CatalogImportRepository) {
    self.repository = repository
    deferredScope = nil
    deferredStagingID = nil
  }

  /// A deferred sink stages into a refresh-wide session; its commit is finalized by the owner.
  public init(
    repository: any CatalogImportRepository,
    deferredStagingID: UUID,
    scope: CatalogScope
  ) {
    self.repository = repository
    self.deferredStagingID = deferredStagingID
    deferredScope = scope
  }

  public func beginImport(for sourceID: SourceConfiguration.ID) async throws {
    try await begin(CatalogScope(sourceID: sourceID, origin: .m3u, kind: .unspecified))
  }

  public func beginImport(for sourceID: SourceConfiguration.ID, kind: ProviderMediaKind)
    async throws
  {
    try await begin(CatalogScope(sourceID: sourceID, origin: .xtream, kind: CatalogMediaKind(kind)))
  }

  private func begin(_ scope: CatalogScope) async throws {
    guard stagingID == nil, !starting else { throw CatalogStoreError.busy }
    if let deferredScope, let deferredStagingID {
      guard scope == deferredScope else { throw CatalogStoreError.invalidInput }
      stagingID = deferredStagingID
      self.scope = scope
      return
    }
    starting = true
    defer { starting = false }
    stagingID = try await repository.beginStaging(in: scope)
    self.scope = scope
  }

  public func write(_ items: [ImportedMediaItem]) async throws {
    let (stagingID, scope) = try session()
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
        mediaURL: item.mediaURL,
        epgChannelID: item.tvgID.flatMap { EPGChannelIdentity(rawValue: $0) })
    }
    try await repository.stage(
      items: values, categories: Array(categories.values), in: stagingID)
  }

  public func write(_ items: [ProviderCatalogItem]) async throws {
    let (stagingID, _) = try session()
    guard items.count <= CatalogPage.maximumSize else { throw CatalogStoreError.invalidInput }
    try await repository.stage(
      items: items.map { item in
        CatalogItem(
          id: item.id.rawValue,
          scope: CatalogScope(
            sourceID: item.sourceID, origin: .xtream,
            kind: CatalogMediaKind(item.providerReference.kind)),
          title: item.title, categoryID: item.categoryID?.rawValue, artworkURL: item.artworkURL,
          providerReference: item.providerReference)
      }, categories: [], in: stagingID)
  }

  public func writeCategories(_ categories: [ProviderCategory]) async throws {
    let (stagingID, _) = try session()
    guard categories.count <= CatalogPage.maximumSize else { throw CatalogStoreError.invalidInput }
    try await repository.stage(
      items: [],
      categories: categories.map { category in
        CatalogCategory(
          id: category.id.rawValue,
          scope: CatalogScope(
            sourceID: category.sourceID, origin: .xtream, kind: CatalogMediaKind(category.kind)),
          title: category.title)
      }, in: stagingID)
  }

  public func commitImport() async throws {
    let (stagingID, _) = try session()
    if deferredStagingID == nil {
      try await repository.commitStagedReplacement(stagingID)
    }
    self.stagingID = nil
    scope = nil
  }

  public func rollbackImport() async {
    guard let stagingID else { return }
    await repository.discardStaging(stagingID)
    self.stagingID = nil
    scope = nil
  }

  private func session() throws -> (UUID, CatalogScope) {
    guard let stagingID, let scope else { throw CatalogStoreError.invalidTransaction }
    return (stagingID, scope)
  }
}
