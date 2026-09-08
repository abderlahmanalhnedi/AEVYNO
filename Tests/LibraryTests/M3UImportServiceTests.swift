import Domain
import Foundation
import IPTVCore
import Library
import Testing

@Test("Repeated imports produce stable source-scoped identities")
func repeatedImportsProduceStableIdentities() async throws {
  let sourceID = SourceConfiguration.ID(
    rawValue: try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000004"))
  )
  let otherSourceID = SourceConfiguration.ID(
    rawValue: try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000005"))
  )
  let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-id="stable-channel",Stable Channel
    https://example.invalid/live/session-one.ts?signature=synthetic-one
    """

  let firstSink = RecordingM3UImportSink()
  let secondSink = RecordingM3UImportSink()
  let otherSourceSink = RecordingM3UImportSink()
  let service = M3UImportService()

  _ = try await service.importPlaylist(
    lines: dataLines(playlist),
    sourceID: sourceID,
    sink: firstSink
  )
  _ = try await service.importPlaylist(
    lines: dataLines(playlist),
    sourceID: sourceID,
    sink: secondSink
  )
  _ = try await service.importPlaylist(
    lines: dataLines(playlist),
    sourceID: otherSourceID,
    sink: otherSourceSink
  )

  let firstItems = await firstSink.committedItems
  let secondItems = await secondSink.committedItems
  let otherSourceItems = await otherSourceSink.committedItems
  #expect(firstItems.map(\.id) == secondItems.map(\.id))
  #expect(firstItems.map(\.id) != otherSourceItems.map(\.id))
  #expect(!firstItems[0].description.contains("signature"))
  #expect(!firstItems[0].description.contains("synthetic-one"))
}

@Test("Duplicate entries are preserved with unique deterministic occurrence identities")
func duplicateEntriesArePreserved() async throws {
  let sourceID = SourceConfiguration.ID(
    rawValue: try #require(UUID(uuidString: "60000000-0000-0000-0000-000000000006"))
  )
  let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-id="duplicate",Duplicate
    https://example.invalid/live/duplicate.ts
    #EXTINF:-1 tvg-id="duplicate",Duplicate
    https://example.invalid/live/duplicate.ts
    """
  let firstSink = RecordingM3UImportSink()
  let secondSink = RecordingM3UImportSink()

  let firstReport = try await M3UImportService(batchSize: 1).importPlaylist(
    lines: dataLines(playlist),
    sourceID: sourceID,
    sink: firstSink
  )
  let secondReport = try await M3UImportService(batchSize: 1).importPlaylist(
    lines: dataLines(playlist),
    sourceID: sourceID,
    sink: secondSink
  )

  let firstIDs = await firstSink.committedItems.map(\.id)
  let secondIDs = await secondSink.committedItems.map(\.id)
  #expect(firstIDs.count == 2)
  #expect(Set(firstIDs).count == 2)
  #expect(firstIDs == secondIDs)
  #expect(firstReport.duplicateCount == 1)
  #expect(secondReport.duplicateCount == 1)
}

@Test("Import writes bounded batches and commits only after parsing")
func importUsesBoundedBatches() async throws {
  let sink = RecordingM3UImportSink()
  let report = try await M3UImportService(batchSize: 2).importPlaylist(
    lines: SyntheticM3ULineSequence(entryCount: 5),
    sourceID: SourceConfiguration.ID(),
    sink: sink
  )

  #expect(report.importedCount == 5)
  #expect(await sink.committedItems.count == 5)
  #expect(await sink.writtenBatchSizes == [2, 2, 1])
  #expect(await sink.didCommit)
  #expect(!(await sink.didRollback))
}

@Test("Cancellation rolls back staged work and never returns partial success")
func cancelledImportRollsBack() async throws {
  let sink = SuspendingM3UImportSink()
  let service = M3UImportService(batchSize: 1)
  let task = Task {
    try await service.importPlaylist(
      lines: SyntheticM3ULineSequence(entryCount: 10),
      sourceID: SourceConfiguration.ID(),
      sink: sink
    )
  }

  await sink.waitUntilWriteStarts()
  task.cancel()

  await #expect(throws: CancellationError.self) {
    try await task.value
  }
  #expect(await sink.stagedCount == 0)
  #expect(await sink.didRollback)
  #expect(!(await sink.didCommit))
}

@Test("Sink failures roll back the import")
func sinkFailureRollsBack() async {
  let sink = FailingM3UImportSink()

  await #expect(throws: SyntheticSinkError.self) {
    try await M3UImportService(batchSize: 1).importPlaylist(
      lines: SyntheticM3ULineSequence(entryCount: 2),
      sourceID: SourceConfiguration.ID(),
      sink: sink
    )
  }
  #expect(await sink.didRollback)
  #expect(!(await sink.didCommit))
}

private func dataLines(_ playlist: String) -> M3UDataLineSequence {
  M3UDataLineSequence(data: Data(playlist.utf8))
}

private actor RecordingM3UImportSink: M3UImportSink {
  private(set) var committedItems: [ImportedMediaItem] = []
  private(set) var writtenBatchSizes: [Int] = []
  private(set) var didCommit = false
  private(set) var didRollback = false
  private var stagedItems: [ImportedMediaItem] = []

  func beginImport(for sourceID: SourceConfiguration.ID) async throws {
    stagedItems = []
    writtenBatchSizes = []
    didCommit = false
    didRollback = false
  }

  func write(_ items: [ImportedMediaItem]) async throws {
    writtenBatchSizes.append(items.count)
    stagedItems.append(contentsOf: items)
  }

  func commitImport() async throws {
    committedItems = stagedItems
    stagedItems = []
    didCommit = true
  }

  func rollbackImport() async {
    stagedItems = []
    didRollback = true
  }
}

private actor SuspendingM3UImportSink: M3UImportSink {
  private(set) var stagedCount = 0
  private(set) var didCommit = false
  private(set) var didRollback = false
  private var didStartWrite = false

  func beginImport(for sourceID: SourceConfiguration.ID) async throws {}

  func write(_ items: [ImportedMediaItem]) async throws {
    stagedCount += items.count
    didStartWrite = true
    try await Task.sleep(for: .seconds(30))
  }

  func commitImport() async throws {
    didCommit = true
  }

  func rollbackImport() async {
    stagedCount = 0
    didRollback = true
  }

  func waitUntilWriteStarts() async {
    while !didStartWrite {
      await Task.yield()
    }
  }
}

private struct SyntheticSinkError: Error {}

private actor FailingM3UImportSink: M3UImportSink {
  private(set) var didCommit = false
  private(set) var didRollback = false

  func beginImport(for sourceID: SourceConfiguration.ID) async throws {}

  func write(_ items: [ImportedMediaItem]) async throws {
    throw SyntheticSinkError()
  }

  func commitImport() async throws {
    didCommit = true
  }

  func rollbackImport() async {
    didRollback = true
  }
}

struct SyntheticM3ULineSequence: AsyncSequence, Sendable {
  typealias Element = String

  let entryCount: Int

  func makeAsyncIterator() -> Iterator {
    Iterator(entryCount: entryCount)
  }

  struct Iterator: AsyncIteratorProtocol, Sendable {
    let entryCount: Int
    var lineIndex = 0

    mutating func next() async throws -> String? {
      try Task.checkCancellation()
      guard lineIndex <= entryCount * 2 else {
        return nil
      }
      defer { lineIndex += 1 }

      if lineIndex == 0 {
        return "#EXTM3U"
      }
      let entryIndex = (lineIndex - 1) / 2
      if lineIndex.isMultiple(of: 2) {
        return "https://example.invalid/live/\(entryIndex).m3u8"
      }
      return
        "#EXTINF:-1 tvg-id=\"channel-\(entryIndex)\" group-title=\"Synthetic\",Channel \(entryIndex)"
    }
  }
}
