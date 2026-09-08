import Domain
import Foundation

public enum CatalogStoreError: Error, Equatable, Sendable {
  case unavailable
  case invalidInput
  case invalidPage
  case busy
  case invalidTransaction
  case unsupportedSchema
  case corruptedStore
  case writeFailed
}

public struct CatalogFilter: Sendable {
  public let sourceID: SourceConfiguration.ID?
  public let kind: CatalogMediaKind?
  public let categoryID: String?

  public init(
    sourceID: SourceConfiguration.ID? = nil, kind: CatalogMediaKind? = nil,
    categoryID: String? = nil
  ) {
    self.sourceID = sourceID
    self.kind = kind
    self.categoryID = categoryID
  }
}

/// Offset pages are deterministic for an unchanged catalog. Restart paging after refresh.
public struct CatalogPage: Sendable {
  public static let maximumSize = 256
  public let limit: Int
  public let offset: Int

  public init(limit: Int = 64, offset: Int = 0) throws {
    guard (1...Self.maximumSize).contains(limit), offset >= 0 else {
      throw CatalogStoreError.invalidPage
    }
    self.limit = limit
    self.offset = offset
  }
}

public protocol CatalogQueryRepository: Sendable {
  func item(id: String) async throws -> CatalogItem?
  func items(matching filter: CatalogFilter, page: CatalogPage) async throws -> [CatalogItem]
  func categories(matching filter: CatalogFilter, page: CatalogPage) async throws
    -> [CatalogCategory]
  func itemCount(matching filter: CatalogFilter) async throws -> Int
  /// Number of committed source/origin/kind partitions, including explicitly empty catalogs.
  func sourceCatalogCount(sourceID: SourceConfiguration.ID?) async throws -> Int
}

/// Tokens prevent a failed concurrent begin/rollback from affecting another import.
public protocol CatalogImportRepository: Sendable {
  func beginReplacement(in scope: CatalogScope) async throws -> UUID
  func write(items: [CatalogItem], categories: [CatalogCategory], transaction: UUID) async throws
  func commit(transaction: UUID) async throws
  func rollback(transaction: UUID) async
  func deleteCatalog(sourceID: SourceConfiguration.ID) async throws
}
