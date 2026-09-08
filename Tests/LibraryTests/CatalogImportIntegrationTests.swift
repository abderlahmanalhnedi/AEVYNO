import Domain
import Foundation
import IPTVCore
import Library
import Testing

@testable import Persistence

struct CatalogImportIntegrationTests {
  @Test("Network acquisition waits with no live SQLite writer transaction")
  func acquisitionDoesNotHoldWriterTransaction() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let source = try makeXtreamSource(id: fixture.sourceID)
    let adapter = SuspendingAcquisitionAdapter()
    let task = Task {
      try await ProviderCatalogImportService(batchSize: 1).importCatalog(
        for: .live, from: source, using: adapter,
        into: PersistentCatalogImportSink(repository: store))
    }

    await adapter.waitUntilItemIsStaged()
    let independentWriter = try CatalogDatabase(url: fixture.url)
    try independentWriter.execute("BEGIN IMMEDIATE")
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    try independentWriter.rollback()

    await adapter.finishAcquisition()
    #expect(try await task.value.importedCount == 1)
    #expect(try await store.item(id: fixture.item(0).id) == nil)
    await store.close()
  }

  @Test("Xtream adapter categories and items commit together into production persistence")
  func xtreamIntegration() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try makeXtreamSource(id: fixture.sourceID)
    let transport = XtreamFixtureTransport(responses: [
      "get_live_categories": try xtreamFixture(named: "live-categories"),
      "get_live_streams": try xtreamFixture(named: "live-streams"),
    ])
    let adapter = XtreamProviderAdapter(
      credentialStore: try SyntheticXtreamCredentialStore(), transport: transport)
    let report = try await ProviderCatalogImportService().importCatalog(
      for: .live, from: source, using: adapter, into: PersistentCatalogImportSink(repository: store)
    )
    #expect(report.importedCount > 0)
    #expect(try await store.itemCount(matching: CatalogFilter()) == report.importedCount)
    let categories = try await store.categories(matching: CatalogFilter(), page: CatalogPage())
    #expect(!categories.isEmpty)
    let items = try await store.items(matching: CatalogFilter(), page: CatalogPage())
    for item in items {
      #expect(item.mediaURL == nil)
      #expect(item.providerReference != nil)
      if let category = item.categoryID { #expect(categories.contains { $0.id == category }) }
    }
    await store.close()
  }

  @Test("Parser and transport failure after a persisted batch preserve the previous catalog")
  func serviceFailureAfterBatch() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let source = try makeXtreamSource(id: fixture.sourceID)
    await #expect(throws: ProviderAdapterError.transportUnavailable) {
      try await ProviderCatalogImportService(batchSize: 1).importCatalog(
        for: .live, from: source, using: FailingCatalogAdapter(),
        into: PersistentCatalogImportSink(repository: store))
    }
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    let valid = Data(
      "#EXTM3U\n#EXTINF:-1 tvg-id=\"old\",Old M3U\nhttps://example.invalid/old\n".utf8)
    _ = try await M3UImportService(batchSize: 1).importPlaylist(
      lines: M3UDataLineSequence(data: valid), sourceID: fixture.sourceID,
      sink: PersistentCatalogImportSink(repository: store))
    var invalid = Data("#EXTM3U\n#EXTINF:-1,New M3U\nhttps://example.invalid/new\n".utf8)
    invalid.append(contentsOf: [0xFF, 0x0A])
    await #expect(throws: M3UParserError.self) {
      try await M3UImportService(batchSize: 1).importPlaylist(
        lines: M3UDataLineSequence(data: invalid), sourceID: fixture.sourceID,
        sink: PersistentCatalogImportSink(repository: store))
    }
    let m3u = try await store.items(
      matching: CatalogFilter(kind: .unspecified), page: CatalogPage())
    #expect(m3u.map(\.title) == ["Old M3U"])
    await store.close()
  }

  @Test("Provider cancellation after a database batch rolls back via the service")
  func serviceCancellation() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let source = try makeXtreamSource(id: fixture.sourceID)
    let adapter = FailingCatalogAdapter(cancelAfterItem: true)
    let task = Task {
      try await ProviderCatalogImportService(batchSize: 1).importCatalog(
        for: .live, from: source, using: adapter,
        into: PersistentCatalogImportSink(repository: store))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    await store.close()
  }
}

private struct FailingCatalogAdapter: ProviderAdapter {
  var cancelAfterItem = false

  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    ProviderAccountSnapshot()
  }

  func categories(for kind: ProviderMediaKind, source: SourceConfiguration) async throws
    -> ProviderCategoryResult
  {
    ProviderCategoryResult(categories: [], receivedCount: 0, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind, source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    let reference = ProviderItemReference(kind: kind, providerID: "new")
    try await onItem(
      ProviderCatalogItem(
        id: .init(sourceID: source.id, reference: reference), sourceID: source.id,
        providerReference: reference, title: "New catalog"))
    if cancelAfterItem {
      withUnsafeCurrentTask { $0?.cancel() }
      try Task.checkCancellation()
    }
    throw ProviderAdapterError.transportUnavailable
  }
}

private struct SuspendingAcquisitionAdapter: ProviderAdapter {
  private let state = SuspendingAcquisitionState()

  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    ProviderAccountSnapshot()
  }

  func categories(for kind: ProviderMediaKind, source: SourceConfiguration) async throws
    -> ProviderCategoryResult
  {
    ProviderCategoryResult(categories: [], receivedCount: 0, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind, source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    let reference = ProviderItemReference(kind: kind, providerID: "staged")
    try await onItem(
      ProviderCatalogItem(
        id: .init(sourceID: source.id, reference: reference), sourceID: source.id,
        providerReference: reference, title: "Staged while network waits"))
    await state.markItemStaged()
    await state.waitUntilMayFinish()
    return ProviderCatalogReport(receivedCount: 1, normalizedCount: 1, skippedCount: 0)
  }

  func waitUntilItemIsStaged() async {
    await state.waitUntilItemIsStaged()
  }

  func finishAcquisition() async { await state.finishAcquisition() }
}

private actor SuspendingAcquisitionState {
  private var itemIsStaged = false
  private var mayFinish = false

  func markItemStaged() { itemIsStaged = true }

  func waitUntilItemIsStaged() async {
    while !itemIsStaged { await Task.yield() }
  }

  func waitUntilMayFinish() async {
    while !mayFinish { await Task.yield() }
  }

  func finishAcquisition() { mayFinish = true }
}
