import Domain
import Foundation
import Library
import Testing

@Suite("M3U import performance", .serialized)
struct M3UImportPerformanceTests {
  @Test("Synthetic streaming import", arguments: [10_000, 50_000, 100_000])
  func syntheticStreamingImport(entryCount: Int) async throws {
    let sourceID = SourceConfiguration.ID(
      rawValue: try #require(UUID(uuidString: "70000000-0000-0000-0000-000000000007"))
    )
    let sink = CountingM3UImportSink()
    let clock = ContinuousClock()
    let start = clock.now

    let report = try await M3UImportService().importPlaylist(
      lines: SyntheticM3ULineSequence(entryCount: entryCount),
      sourceID: sourceID,
      sink: sink
    )
    let elapsed = start.duration(to: clock.now)

    #expect(report.parsedCount == entryCount)
    #expect(report.importedCount == entryCount)
    #expect(report.skippedCount == 0)
    #expect(report.duplicateCount == 0)
    #expect(await sink.committedCount == entryCount)
    #expect(await sink.maximumBatchCount <= M3UImportService.defaultBatchSize)
    print("M3U synthetic import entries=\(entryCount) elapsed=\(elapsed)")
  }
}

private actor CountingM3UImportSink: M3UImportSink {
  private(set) var committedCount = 0
  private(set) var maximumBatchCount = 0
  private var stagedCount = 0

  func beginImport(for sourceID: SourceConfiguration.ID) async throws {
    stagedCount = 0
    maximumBatchCount = 0
  }

  func write(_ items: [ImportedMediaItem]) async throws {
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
