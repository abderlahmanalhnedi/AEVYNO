import Domain
import IPTVCore

public protocol ProviderCatalogImportSink: Sendable {
  func beginImport(
    for sourceID: SourceConfiguration.ID,
    kind: ProviderMediaKind
  ) async throws
  func write(_ items: [ProviderCatalogItem]) async throws
  func commitImport() async throws
  func rollbackImport() async
}

public struct ProviderCatalogImportReport: Equatable, Sendable {
  public let receivedCount: Int
  public let importedCount: Int
  public let skippedCount: Int

  public init(receivedCount: Int, importedCount: Int, skippedCount: Int) {
    self.receivedCount = receivedCount
    self.importedCount = importedCount
    self.skippedCount = skippedCount
  }
}

public struct ProviderCatalogImportService: Sendable {
  public static let defaultBatchSize = 256

  private let batchSize: Int

  public init(batchSize: Int = ProviderCatalogImportService.defaultBatchSize) {
    self.batchSize = max(1, batchSize)
  }

  public func importCatalog(
    for kind: ProviderMediaKind,
    from source: SourceConfiguration,
    using adapter: any ProviderAdapter,
    into sink: any ProviderCatalogImportSink
  ) async throws -> ProviderCatalogImportReport {
    try Task.checkCancellation()

    do {
      try await sink.beginImport(for: source.id, kind: kind)
      var batch: [ProviderCatalogItem] = []
      batch.reserveCapacity(batchSize)
      var importedCount = 0

      let catalogReport = try await adapter.fetchCatalog(for: kind, source: source) { item in
        try Task.checkCancellation()
        batch.append(item)
        if batch.count == batchSize {
          try await sink.write(batch)
          importedCount += batch.count
          batch.removeAll(keepingCapacity: true)
        }
      }

      try Task.checkCancellation()
      if !batch.isEmpty {
        try await sink.write(batch)
        importedCount += batch.count
      }
      try Task.checkCancellation()
      guard
        catalogReport.normalizedCount == importedCount,
        catalogReport.receivedCount == catalogReport.normalizedCount + catalogReport.skippedCount
      else {
        throw ProviderAdapterError.providerResponseInvalid
      }
      try await sink.commitImport()

      return ProviderCatalogImportReport(
        receivedCount: catalogReport.receivedCount,
        importedCount: importedCount,
        skippedCount: catalogReport.skippedCount
      )
    } catch {
      await sink.rollbackImport()
      throw error
    }
  }
}
