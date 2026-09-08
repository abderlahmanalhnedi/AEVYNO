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

/// Staging is invisible to queries and does not hold the live catalog writer transaction open.
public protocol CatalogImportRepository: Sendable {
  func beginStaging(in scope: CatalogScope) async throws -> UUID
  func beginStaging(in scopes: [CatalogScope]) async throws -> UUID
  func stage(items: [CatalogItem], categories: [CatalogCategory], in stagingID: UUID) async throws
  func commitStagedReplacement(_ stagingID: UUID) async throws
  func commitStagedReplacement(
    _ stagingID: UUID, successfulRefresh metadata: CatalogRefreshMetadata
  ) async throws -> Int
  func discardStaging(_ stagingID: UUID) async
  func deleteCatalog(sourceID: SourceConfiguration.ID) async throws
}

public protocol CatalogRefreshMetadataRepository: Sendable {
  func recordRefreshAttempt(
    sourceID: SourceConfiguration.ID,
    attemptedAt: Date,
    result: CatalogRefreshResultCategory
  ) async throws
  func refreshMetadata(for sourceID: SourceConfiguration.ID) async throws
    -> CatalogRefreshMetadata?
}

public typealias CatalogRefreshRepository = CatalogImportRepository
  & CatalogRefreshMetadataRepository
