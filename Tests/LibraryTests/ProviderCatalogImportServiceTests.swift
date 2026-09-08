import Domain
import Foundation
import IPTVCore
import Library
import Testing

@Test("Provider catalog import writes bounded batches and commits normalized items")
func providerCatalogImportUsesBoundedBatches() async throws {
  let source = try makeXtreamSource()
  let items = syntheticProviderItems(count: 5, sourceID: source.id)
  let sink = RecordingProviderCatalogSink()

  let report = try await ProviderCatalogImportService(batchSize: 2).importCatalog(
    for: .live,
    from: source,
    using: StubProviderAdapter(items: items),
    into: sink
  )

  #expect(
    report == ProviderCatalogImportReport(receivedCount: 5, importedCount: 5, skippedCount: 0))
  #expect(await sink.writtenBatchSizes == [2, 2, 1])
  #expect(await sink.committedItems == items)
  #expect(await sink.didCommit)
  #expect(!(await sink.didRollback))
}

@Test("Provider adapter failure rolls back staged catalog work")
func providerCatalogAdapterFailureRollsBack() async throws {
  let source = try makeXtreamSource()
  let sink = RecordingProviderCatalogSink()

  await #expect(throws: ProviderAdapterError.transportUnavailable) {
    try await ProviderCatalogImportService().importCatalog(
      for: .vod,
      from: source,
      using: StubProviderAdapter(items: [], failure: .transportUnavailable),
      into: sink
    )
  }
  #expect(await sink.didRollback)
  #expect(!(await sink.didCommit))
}

@Test("Provider catalog cancellation rolls back and remains CancellationError")
func providerCatalogCancellationRollsBack() async throws {
  let source = try makeXtreamSource()
  let items = syntheticProviderItems(count: 3, sourceID: source.id)
  let sink = SuspendingProviderCatalogSink()
  let task = Task {
    try await ProviderCatalogImportService(batchSize: 1).importCatalog(
      for: .series,
      from: source,
      using: StubProviderAdapter(items: items),
      into: sink
    )
  }

  await sink.waitUntilWriteStarts()
  task.cancel()

  await #expect(throws: CancellationError.self) {
    try await task.value
  }
  #expect(await sink.didRollback)
  #expect(!(await sink.didCommit))
  #expect(await sink.stagedCount == 0)
}

private struct StubProviderAdapter: ProviderAdapter, Sendable {
  let items: [ProviderCatalogItem]
  let failure: ProviderAdapterError?

  init(items: [ProviderCatalogItem], failure: ProviderAdapterError? = nil) {
    self.items = items
    self.failure = failure
  }

  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    ProviderAccountSnapshot()
  }

  func categories(
    for kind: ProviderMediaKind,
    source: SourceConfiguration
  ) async throws -> ProviderCategoryResult {
    ProviderCategoryResult(categories: [], receivedCount: 0, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    if let failure {
      throw failure
    }
    for item in items {
      try Task.checkCancellation()
      try await onItem(item)
    }
    return ProviderCatalogReport(
      receivedCount: items.count,
      normalizedCount: items.count,
      skippedCount: 0
    )
  }
}

private actor RecordingProviderCatalogSink: ProviderCatalogImportSink {
  private(set) var committedItems: [ProviderCatalogItem] = []
  private(set) var writtenBatchSizes: [Int] = []
  private(set) var didCommit = false
  private(set) var didRollback = false
  private var stagedItems: [ProviderCatalogItem] = []

  func beginImport(for sourceID: SourceConfiguration.ID, kind: ProviderMediaKind) async throws {
    stagedItems = []
  }

  func write(_ items: [ProviderCatalogItem]) async throws {
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

private actor SuspendingProviderCatalogSink: ProviderCatalogImportSink {
  private(set) var stagedCount = 0
  private(set) var didCommit = false
  private(set) var didRollback = false
  private var didStartWrite = false

  func beginImport(for sourceID: SourceConfiguration.ID, kind: ProviderMediaKind) async throws {}

  func write(_ items: [ProviderCatalogItem]) async throws {
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

private func syntheticProviderItems(
  count: Int,
  sourceID: SourceConfiguration.ID
) -> [ProviderCatalogItem] {
  (0..<count).map { index in
    let reference = ProviderItemReference(kind: .live, providerID: String(index))
    return ProviderCatalogItem(
      id: ProviderCatalogItem.ID(sourceID: sourceID, reference: reference),
      sourceID: sourceID,
      providerReference: reference,
      title: "Synthetic item \(index)"
    )
  }
}
