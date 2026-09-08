import CryptoKit
import Domain
import Foundation
import IPTVCore
import Library
import Persistence
import Testing

@Suite("Phase 2E refresh performance", .serialized)
struct CatalogRefreshPerformanceTests {
  @Test("M3U acquisition through atomic refresh", arguments: [10_000, 50_000, 100_000])
  func m3u(entryCount: Int) async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let repository = TimedRefreshRepository(store: store)
    let transport = PreparedM3UTransport(data: m3uData(entryCount: entryCount))
    let service = CatalogRefreshService(
      repository: repository,
      m3uAcquisition: M3UAcquisitionService(transport: transport),
      providerAdapter: PerformanceProviderAdapter(totalItemCount: 0)
    )
    let clock = ContinuousClock()
    let start = clock.now
    let report = try await service.refresh(try m3uSource(id: fixture.sourceID))
    let total = start.duration(to: clock.now)
    let timing = await repository.timing
    let acquisition = await transport.elapsed
    let parseAndNormalize = total - acquisition - timing.staging - timing.commit
    #expect(report.committedItemCount == entryCount)
    #expect(try await store.itemCount(matching: CatalogFilter()) == entryCount)
    print(
      "REFRESH-M3U rows=\(entryCount) acquisition=\(acquisition) parse-normalize-orchestration=\(parseAndNormalize) staging=\(timing.staging) final-transaction=\(timing.commit) total=\(total)"
    )
    await store.close()
  }

  @Test(
    "Normalized provider catalogs through atomic refresh", arguments: [10_000, 50_000, 100_000])
  func provider(entryCount: Int) async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let repository = TimedRefreshRepository(store: store)
    let service = CatalogRefreshService(
      repository: repository,
      m3uAcquisition: M3UAcquisitionService(
        transport: PreparedM3UTransport(data: Data("unused".utf8))),
      providerAdapter: PerformanceProviderAdapter(totalItemCount: entryCount)
    )
    let clock = ContinuousClock()
    let start = clock.now
    let report = try await service.refresh(try makeXtreamSource(id: fixture.sourceID))
    let total = start.duration(to: clock.now)
    let timing = await repository.timing
    let normalizeAndOrchestrate = total - timing.staging - timing.commit
    #expect(report.committedItemCount == entryCount)
    #expect(try await store.itemCount(matching: CatalogFilter()) == entryCount)
    print(
      "REFRESH-PROVIDER rows=\(entryCount) acquire-normalize-orchestration=\(normalizeAndOrchestrate) staging=\(timing.staging) final-transaction=\(timing.commit) total=\(total)"
    )
    await store.close()
  }
}

private actor TimedRefreshRepository: CatalogRefreshRepository {
  struct Timing: Sendable {
    var staging = Duration.zero
    var commit = Duration.zero
  }

  private let store: SQLiteCatalogStore
  private(set) var timing = Timing()

  init(store: SQLiteCatalogStore) { self.store = store }

  func beginStaging(in scope: CatalogScope) async throws -> UUID {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try await store.beginStaging(in: scope)
    timing.staging += start.duration(to: clock.now)
    return result
  }

  func beginStaging(in scopes: [CatalogScope]) async throws -> UUID {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try await store.beginStaging(in: scopes)
    timing.staging += start.duration(to: clock.now)
    return result
  }

  func stage(items: [CatalogItem], categories: [CatalogCategory], in stagingID: UUID) async throws {
    let clock = ContinuousClock()
    let start = clock.now
    try await store.stage(items: items, categories: categories, in: stagingID)
    timing.staging += start.duration(to: clock.now)
  }

  func commitStagedReplacement(_ stagingID: UUID) async throws {
    let clock = ContinuousClock()
    let start = clock.now
    try await store.commitStagedReplacement(stagingID)
    timing.commit += start.duration(to: clock.now)
  }

  func commitStagedReplacement(
    _ stagingID: UUID,
    successfulRefresh metadata: CatalogRefreshMetadata
  ) async throws -> Int {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try await store.commitStagedReplacement(stagingID, successfulRefresh: metadata)
    timing.commit += start.duration(to: clock.now)
    return result
  }

  func discardStaging(_ stagingID: UUID) async { await store.discardStaging(stagingID) }

  func deleteCatalog(sourceID: SourceConfiguration.ID) async throws {
    try await store.deleteCatalog(sourceID: sourceID)
  }

  func recordRefreshAttempt(
    sourceID: SourceConfiguration.ID,
    attemptedAt: Date,
    result: CatalogRefreshResultCategory
  ) async throws {
    try await store.recordRefreshAttempt(
      sourceID: sourceID, attemptedAt: attemptedAt, result: result)
  }

  func refreshMetadata(for sourceID: SourceConfiguration.ID) async throws
    -> CatalogRefreshMetadata?
  {
    try await store.refreshMetadata(for: sourceID)
  }
}

private actor PreparedM3UTransport: M3UAcquisitionTransport {
  let data: Data
  private(set) var elapsed = Duration.zero

  init(data: Data) { self.data = data }

  func data(for request: URLRequest, maximumByteCount: Int) async throws
    -> (Data, HTTPURLResponse)
  {
    let clock = ContinuousClock()
    let start = clock.now
    try Task.checkCancellation()
    let url = try #require(request.url)
    let response = try #require(
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Length": String(data.count)]))
    elapsed += start.duration(to: clock.now)
    return (data, response)
  }
}

private struct PerformanceProviderAdapter: ProviderAdapter {
  let totalItemCount: Int

  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    ProviderAccountSnapshot(status: "Active")
  }

  func categories(for kind: ProviderMediaKind, source: SourceConfiguration) async throws
    -> ProviderCategoryResult
  {
    let categories = (0..<100).map { index in
      ProviderCategory(
        id: .init(sourceID: source.id, kind: kind, providerID: String(index)),
        sourceID: source.id,
        kind: kind,
        providerID: String(index),
        title: "Synthetic category \(index)"
      )
    }
    return ProviderCategoryResult(
      categories: categories, receivedCount: categories.count, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    let count = itemCount(for: kind)
    for index in 0..<count {
      try Task.checkCancellation()
      let providerID = "\(kind.rawValue)-\(index)"
      let reference = ProviderItemReference(kind: kind, providerID: providerID)
      try await onItem(
        ProviderCatalogItem(
          id: .init(sourceID: source.id, reference: reference),
          sourceID: source.id,
          providerReference: reference,
          title: "Synthetic \(kind.rawValue) \(index)",
          categoryID: .init(
            sourceID: source.id, kind: kind, providerID: String(index % 100))
        ))
    }
    return ProviderCatalogReport(receivedCount: count, normalizedCount: count, skippedCount: 0)
  }

  private func itemCount(for kind: ProviderMediaKind) -> Int {
    let base = totalItemCount / ProviderMediaKind.allCases.count
    return kind == .live ? base + totalItemCount % ProviderMediaKind.allCases.count : base
  }
}

private func m3uData(entryCount: Int) -> Data {
  var data = Data("#EXTM3U\n".utf8)
  for index in 0..<entryCount {
    data.append(
      contentsOf:
        "#EXTINF:-1 tvg-id=\"channel-\(index)\" group-title=\"Group \(index % 100)\",Channel \(index)\nhttps://example.invalid/live/\(index).m3u8?token=synthetic-\(index)\n"
        .utf8)
  }
  return data
}
