import Domain
import Foundation
import IPTVCore
import Library
import Testing

@Suite("Xtream provider normalization performance", .serialized)
struct XtreamProviderPerformanceTests {
  @Test("Synthetic catalog normalization and bounded import", arguments: [10_000, 50_000, 100_000])
  func syntheticCatalogNormalization(entryCount: Int) async throws {
    let source = try makeXtreamSource()
    let responseData = syntheticXtreamCatalogData(entryCount: entryCount)
    let transport = XtreamFixtureTransport(responses: ["get_live_streams": responseData])
    let adapter = try XtreamProviderAdapter(
      credentialStore: SyntheticXtreamCredentialStore(),
      transport: transport
    )
    let sink = CountingProviderCatalogSink()
    let clock = ContinuousClock()

    let start = clock.now
    let report = try await ProviderCatalogImportService().importCatalog(
      for: .live,
      from: source,
      using: adapter,
      into: sink
    )
    let elapsed = start.duration(to: clock.now)

    #expect(report.receivedCount == entryCount)
    #expect(report.importedCount == entryCount)
    #expect(report.skippedCount == 0)
    #expect(await sink.committedCount == entryCount)
    #expect(
      await sink.maximumBatchCount <= ProviderCatalogImportService.defaultBatchSize
    )
    print("Xtream synthetic normalization entries=\(entryCount) elapsed=\(elapsed)")
  }
}

private actor CountingProviderCatalogSink: ProviderCatalogImportSink {
  private(set) var committedCount = 0
  private(set) var maximumBatchCount = 0
  private var stagedCount = 0

  func beginImport(for sourceID: SourceConfiguration.ID, kind: ProviderMediaKind) async throws {
    stagedCount = 0
    maximumBatchCount = 0
  }

  func write(_ items: [ProviderCatalogItem]) async throws {
    stagedCount += items.count
    maximumBatchCount = max(maximumBatchCount, items.count)
  }

  func commitImport() async throws {
    committedCount = stagedCount
    stagedCount = 0
  }

  func rollbackImport() async {
    stagedCount = 0
  }
}

private func syntheticXtreamCatalogData(entryCount: Int) -> Data {
  var data = Data()
  data.reserveCapacity(entryCount * 90)
  data.append(contentsOf: "[".utf8)
  for index in 0..<entryCount {
    if index > 0 {
      data.append(contentsOf: ",".utf8)
    }
    data.append(
      contentsOf:
        "{\"stream_id\":\(index),\"name\":\"Synthetic \(index)\",\"category_id\":\"1\"}".utf8
    )
  }
  data.append(contentsOf: "]".utf8)
  return data
}
