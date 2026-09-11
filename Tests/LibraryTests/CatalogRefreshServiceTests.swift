import AEVYNOSecurity
import CryptoKit
import Domain
import Foundation
import IPTVCore
import Library
import Testing

@testable import Persistence

@Suite("Durable catalog refresh", .serialized)
struct CatalogRefreshServiceTests {
  @Test(
    "M3U refresh replaces atomically, preserves exact references, and retains last success on failure"
  )
  func m3uEndToEndAndMetadata() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try m3uSource(id: fixture.sourceID)
    let firstURL = "https://example.invalid/live/one.ts?token=synthetic-one"
    let secondURL = "https://example.invalid/live/two.ts?token=synthetic-two"
    let first = Data(
      "#EXTM3U\n#EXTINF:-1 tvg-id=\"stable\" group-title=\"News\",First\n\(firstURL)\n".utf8)
    let second = Data(
      "#EXTM3U\n#EXTINF:-1 tvg-id=\"stable\" group-title=\"Sports\",Second\n\(secondURL)\n".utf8)
    let clock = SequenceRefreshClock([
      Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 11),
      Date(timeIntervalSince1970: 12), Date(timeIntervalSince1970: 20),
      Date(timeIntervalSince1970: 21), Date(timeIntervalSince1970: 30),
    ])

    let stages = RefreshStageRecorder()
    let firstReport = try await makeM3URefreshService(
      store: store, body: first, clock: clock
    ).refresh(source) { stage in
      await stages.record(stage)
    }
    #expect(firstReport.committedItemCount == 1)
    #expect(
      await stages.values == [
        .validating, .acquiring, .parsingOrDecoding, .staging, .committing, .completed,
      ])
    var items = try await store.items(matching: CatalogFilter(), page: CatalogPage())
    #expect(items.map(\.title) == ["First"])
    #expect(items.first?.mediaURL?.absoluteString == firstURL)
    #expect(
      try await store.categories(matching: CatalogFilter(), page: CatalogPage()).map(\.title)
        == ["News"])

    _ = try await makeM3URefreshService(store: store, body: second, clock: clock).refresh(source)
    items = try await store.items(matching: CatalogFilter(), page: CatalogPage())
    #expect(items.map(\.title) == ["Second"])
    #expect(items.first?.mediaURL?.absoluteString == secondURL)
    #expect(
      try await store.categories(matching: CatalogFilter(), page: CatalogPage()).map(\.title)
        == ["Sports"])
    let successfulMetadata = try #require(try await store.refreshMetadata(for: source.id))
    #expect(successfulMetadata.lastAttemptedAt == Date(timeIntervalSince1970: 20))
    #expect(successfulMetadata.lastSuccessfulAt == Date(timeIntervalSince1970: 21))
    #expect(successfulMetadata.lastCommittedItemCount == 1)
    #expect(successfulMetadata.lastResult == .success)

    let malformed = Data("#EXTM3U\nnot-a-playable-url\n".utf8)
    await #expect(throws: CatalogRefreshError.malformedSource) {
      try await makeM3URefreshService(store: store, body: malformed, clock: clock).refresh(source)
    }
    #expect(
      try await store.items(matching: CatalogFilter(), page: CatalogPage()).map(\.title)
        == ["Second"])
    let failedMetadata = try #require(try await store.refreshMetadata(for: source.id))
    #expect(failedMetadata.lastAttemptedAt == Date(timeIntervalSince1970: 30))
    #expect(failedMetadata.lastSuccessfulAt == successfulMetadata.lastSuccessfulAt)
    #expect(failedMetadata.lastCommittedItemCount == 1)
    #expect(failedMetadata.lastResult == .malformedSource)
    await store.close()
  }

  @Test("M3U network failure and cancellation preserve the last-known-good catalog")
  func m3uFailureAndCancellation() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try m3uSource(id: fixture.sourceID)
    let valid = Data("#EXTM3U\n#EXTINF:-1,Known Good\nhttps://example.invalid/good.ts\n".utf8)
    _ = try await makeM3URefreshService(store: store, body: valid).refresh(source)

    let failureService = makeRefreshService(
      store: store,
      m3uTransport: SyntheticM3UTransport(
        behavior: .failure(URLError(.cannotConnectToHost))))
    await #expect(throws: CatalogRefreshError.networkFailure) {
      try await failureService.refresh(source)
    }
    #expect(try await store.itemCount(matching: CatalogFilter()) == 1)

    let suspendingTransport = SyntheticM3UTransport(behavior: .suspend)
    let cancellationService = makeRefreshService(store: store, m3uTransport: suspendingTransport)
    let task = Task { try await cancellationService.refresh(source) }
    await suspendingTransport.waitUntilRequestStarts()
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await store.itemCount(matching: CatalogFilter()) == 1)
    #expect(try await store.refreshMetadata(for: source.id)?.lastResult == .cancelled)
    await store.close()
  }

  @Test("Refresh invalidation publishes after success but not failure or cancellation")
  func commitInvalidationBoundary() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try m3uSource(id: fixture.sourceID)
    let recorder = RefreshCommitRecorder()
    let onCommit: CatalogRefreshCommitHandler = { sourceID in
      await recorder.record(sourceID)
    }
    let valid = Data(
      "#EXTM3U\n#EXTINF:-1,Committed\nhttps://example.invalid/committed.ts\n".utf8)

    _ = try await makeM3URefreshService(
      store: store, body: valid, onCommit: onCommit
    ).refresh(source)
    #expect(await recorder.values == [source.id])

    let failure = makeRefreshService(
      store: store,
      m3uTransport: SyntheticM3UTransport(
        behavior: .failure(URLError(.cannotConnectToHost))),
      onCommit: onCommit
    )
    await #expect(throws: CatalogRefreshError.networkFailure) {
      try await failure.refresh(source)
    }

    let suspending = SyntheticM3UTransport(behavior: .suspend)
    let cancellation = makeRefreshService(
      store: store, m3uTransport: suspending, onCommit: onCommit)
    let task = Task { try await cancellation.refresh(source) }
    await suspending.waitUntilRequestStarts()
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }

    #expect(await recorder.values == [source.id])
    await store.close()
  }

  @Test("Xtream live, VOD, and series commit together and every failure preserves all prior kinds")
  func xtreamEndToEndAndFailures() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try makeXtreamSource(id: fixture.sourceID)
    let successTransport = XtreamFixtureTransport(responses: try completeXtreamResponses())
    let successService = CatalogRefreshService(
      repository: store,
      m3uAcquisition: M3UAcquisitionService(
        transport: SyntheticM3UTransport(behavior: .response(status: 200, data: Data("x".utf8)))),
      providerAdapter: XtreamProviderAdapter(
        credentialStore: try SyntheticXtreamCredentialStore(), transport: successTransport)
    )
    let report = try await successService.refresh(source)
    #expect(report.committedItemCount > 0)
    for kind in CatalogMediaKind.allProviderKinds {
      #expect(
        try await store.itemCount(matching: CatalogFilter(sourceID: source.id, kind: kind)) > 0)
    }
    let committedTitles = try await allTitles(store, sourceID: source.id)

    let failedAdapters: [(any ProviderAdapter, CatalogRefreshError)] = [
      (
        XtreamProviderAdapter(
          credentialStore: MissingCredentialStore(),
          transport: XtreamFixtureTransport(responses: [:])),
        .credentialUnavailable
      ),
      (
        XtreamProviderAdapter(
          credentialStore: try SyntheticXtreamCredentialStore(),
          transport: XtreamFixtureTransport(responses: [
            "authentication": try xtreamFixture(named: "auth-rejected")
          ])),
        .authenticationRejected
      ),
      (
        XtreamProviderAdapter(
          credentialStore: try SyntheticXtreamCredentialStore(),
          transport: XtreamFixtureTransport(responses: [
            "authentication": try xtreamFixture(named: "malformed-response")
          ])),
        .malformedSource
      ),
      (
        XtreamProviderAdapter(
          credentialStore: try SyntheticXtreamCredentialStore(),
          transport: XtreamFixtureTransport(responses: [:], behavior: .unavailable)),
        .networkFailure
      ),
      (InvalidCategoryProviderAdapter(), .persistenceFailure),
    ]
    for (adapter, expectedError) in failedAdapters {
      let service = CatalogRefreshService(
        repository: store,
        m3uAcquisition: M3UAcquisitionService(
          transport: SyntheticM3UTransport(
            behavior: .response(status: 200, data: Data("x".utf8)))),
        providerAdapter: adapter
      )
      await #expect(throws: expectedError) { try await service.refresh(source) }
      #expect(try await allTitles(store, sourceID: source.id) == committedTitles)
    }

    let suspending = XtreamFixtureTransport(responses: [:], behavior: .suspend)
    let cancellationService = CatalogRefreshService(
      repository: store,
      m3uAcquisition: M3UAcquisitionService(
        transport: SyntheticM3UTransport(behavior: .response(status: 200, data: Data("x".utf8)))),
      providerAdapter: XtreamProviderAdapter(
        credentialStore: try SyntheticXtreamCredentialStore(), transport: suspending)
    )
    let task = Task { try await cancellationService.refresh(source) }
    await suspending.waitUntilRequestStarts()
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await allTitles(store, sourceID: source.id) == committedTitles)
    await store.close()
  }

  @Test("Refresh reports and metadata count distinct committed items")
  func duplicateProviderIDsCountOnce() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try makeXtreamSource(id: fixture.sourceID)
    let service = CatalogRefreshService(
      repository: store,
      m3uAcquisition: M3UAcquisitionService(
        transport: SyntheticM3UTransport(
          behavior: .response(status: 200, data: Data("unused".utf8)))),
      providerAdapter: DuplicateProviderIDAdapter()
    )

    let report = try await service.refresh(source)

    #expect(report.committedItemCount == 1)
    #expect(try await store.itemCount(matching: CatalogFilter(sourceID: source.id)) == 1)
    #expect(try await store.refreshMetadata(for: source.id)?.lastCommittedItemCount == 1)
    await store.close()
  }

  @Test("Catalog publication and successful metadata are one atomic commit")
  func metadataCommitFailurePreservesCatalog() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try m3uSource(id: fixture.sourceID)
    let old = Data("#EXTM3U\n#EXTINF:-1,Old\nhttps://example.invalid/old.ts\n".utf8)
    let new = Data("#EXTM3U\n#EXTINF:-1,New\nhttps://example.invalid/new.ts\n".utf8)
    _ = try await makeM3URefreshService(store: store, body: old).refresh(source)
    let database = try CatalogDatabase(url: fixture.url)
    try database.execute(
      """
      CREATE TRIGGER fail_success_metadata BEFORE UPDATE ON refresh_metadata
      WHEN NEW.last_result='success' BEGIN SELECT RAISE(FAIL,'synthetic'); END
      """)

    await #expect(throws: CatalogRefreshError.persistenceFailure) {
      try await makeM3URefreshService(store: store, body: new).refresh(source)
    }
    #expect(
      try await store.items(matching: CatalogFilter(), page: CatalogPage()).map(\.title) == ["Old"])
    let metadata = try #require(try await store.refreshMetadata(for: source.id))
    #expect(metadata.lastSuccessfulAt != nil)
    #expect(metadata.lastCommittedItemCount == 1)
    #expect(metadata.lastResult == .persistenceFailure)
    await store.close()
  }

  @Test(
    "A delayed acquisition holds no live transaction; same-source is busy and another source proceeds"
  )
  func slowNetworkAndConcurrency() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let slowSource = try m3uSource(
      id: fixture.sourceID, endpoint: "https://example.invalid/slow/list.m3u")
    let otherSource = try m3uSource(
      id: SourceConfiguration.ID(), endpoint: "https://example.invalid/fast/list.m3u")
    let old = Data("#EXTM3U\n#EXTINF:-1,Old\nhttps://example.invalid/old.ts\n".utf8)
    _ = try await makeM3URefreshService(store: store, body: old).refresh(slowSource)

    let transport = RoutingDelayedM3UTransport()
    let service = makeRefreshService(store: store, m3uTransport: transport)
    let slowTask = Task { try await service.refresh(slowSource) }
    await transport.waitUntilSlowRequestStarts()

    let queryStart = ContinuousClock.now
    #expect(
      try await store.items(
        matching: CatalogFilter(sourceID: slowSource.id), page: CatalogPage()
      ).map(\.title) == ["Old"])
    #expect(queryStart.duration(to: .now) < .milliseconds(250))
    let inspection = try CatalogDatabase(url: fixture.url)
    #expect(try inspection.scalar("SELECT count(*) FROM staged_catalogs") == 0)
    try inspection.execute("BEGIN IMMEDIATE")
    try inspection.rollback()

    await #expect(throws: CatalogRefreshError.inProgress) { try await service.refresh(slowSource) }
    let otherReport = try await service.refresh(otherSource)
    #expect(otherReport.committedItemCount == 1)
    #expect(try await slowTask.value.committedItemCount == 1)
    #expect(
      try await store.items(
        matching: CatalogFilter(sourceID: slowSource.id), page: CatalogPage()
      ).map(\.title) == ["Slow New"])
    await store.close()
  }

  @Test("Invalid and disabled sources do not acquire data")
  func invalidSources() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let transport = SyntheticM3UTransport(
      behavior: .response(status: 200, data: Data("#EXTM3U".utf8)))
    let service = makeRefreshService(store: store, m3uTransport: transport)
    await #expect(throws: CatalogRefreshError.invalidSource) {
      try await service.refresh(m3uSource(isEnabled: false))
    }
    #expect(await transport.requests.isEmpty)
    await store.close()
  }
}

extension CatalogMediaKind {
  fileprivate static let allProviderKinds: [CatalogMediaKind] = [.live, .vod, .series]
}

private func completeXtreamResponses() throws -> [String: Data] {
  [
    "authentication": try xtreamFixture(named: "auth-valid"),
    "get_live_categories": try xtreamFixture(named: "live-categories"),
    "get_live_streams": try xtreamFixture(named: "live-streams"),
    "get_vod_categories": try xtreamFixture(named: "vod-categories"),
    "get_vod_streams": try xtreamFixture(named: "vod-streams"),
    "get_series_categories": try xtreamFixture(named: "series-categories"),
    "get_series": try xtreamFixture(named: "series-list"),
  ]
}

private func allTitles(
  _ store: SQLiteCatalogStore,
  sourceID: SourceConfiguration.ID
) async throws -> [String] {
  try await store.items(
    matching: CatalogFilter(sourceID: sourceID), page: CatalogPage(limit: 256)
  ).map(\.title)
}

private func makeM3URefreshService(
  store: SQLiteCatalogStore,
  body: Data,
  clock: any CatalogRefreshClock = SystemCatalogRefreshClock(),
  onCommit: CatalogRefreshCommitHandler? = nil
) -> CatalogRefreshService {
  makeRefreshService(
    store: store,
    m3uTransport: SyntheticM3UTransport(behavior: .response(status: 200, data: body)),
    clock: clock,
    onCommit: onCommit
  )
}

private func makeRefreshService(
  store: SQLiteCatalogStore,
  m3uTransport: any M3UAcquisitionTransport,
  clock: any CatalogRefreshClock = SystemCatalogRefreshClock(),
  onCommit: CatalogRefreshCommitHandler? = nil
) -> CatalogRefreshService {
  CatalogRefreshService(
    repository: store,
    m3uAcquisition: M3UAcquisitionService(transport: m3uTransport),
    providerAdapter: UnusedProviderAdapter(),
    clock: clock,
    onCommit: onCommit
  )
}

private struct UnusedProviderAdapter: ProviderAdapter {
  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    throw ProviderAdapterError.invalidSourceConfiguration
  }

  func categories(for kind: ProviderMediaKind, source: SourceConfiguration) async throws
    -> ProviderCategoryResult
  {
    throw ProviderAdapterError.invalidSourceConfiguration
  }

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    throw ProviderAdapterError.invalidSourceConfiguration
  }
}

private struct InvalidCategoryProviderAdapter: ProviderAdapter {
  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    ProviderAccountSnapshot()
  }

  func categories(for kind: ProviderMediaKind, source: SourceConfiguration) async throws
    -> ProviderCategoryResult
  {
    ProviderCategoryResult(categories: [], receivedCount: 0, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    guard kind == .live else {
      return ProviderCatalogReport(receivedCount: 0, normalizedCount: 0, skippedCount: 0)
    }
    let reference = ProviderItemReference(kind: .live, providerID: "orphan")
    try await onItem(
      ProviderCatalogItem(
        id: .init(sourceID: source.id, reference: reference),
        sourceID: source.id,
        providerReference: reference,
        title: "Orphan",
        categoryID: .init(sourceID: source.id, kind: .live, providerID: "missing")
      ))
    return ProviderCatalogReport(receivedCount: 1, normalizedCount: 1, skippedCount: 0)
  }
}

private struct DuplicateProviderIDAdapter: ProviderAdapter {
  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    ProviderAccountSnapshot()
  }

  func categories(for kind: ProviderMediaKind, source: SourceConfiguration) async throws
    -> ProviderCategoryResult
  {
    ProviderCategoryResult(categories: [], receivedCount: 0, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    guard kind == .live else {
      return ProviderCatalogReport(receivedCount: 0, normalizedCount: 0, skippedCount: 0)
    }
    let reference = ProviderItemReference(kind: kind, providerID: "duplicate")
    for title in ["First", "Replacement"] {
      try await onItem(
        ProviderCatalogItem(
          id: .init(sourceID: source.id, reference: reference),
          sourceID: source.id,
          providerReference: reference,
          title: title
        ))
    }
    return ProviderCatalogReport(receivedCount: 2, normalizedCount: 2, skippedCount: 0)
  }
}

private actor MissingCredentialStore: CredentialStore {
  func store(_ credential: SourceCredential, for reference: CredentialReference) {}
  func credential(for reference: CredentialReference) -> SourceCredential? { nil }
  func update(_ credential: SourceCredential, for reference: CredentialReference) {}
  func deleteCredential(for reference: CredentialReference) {}
}

private actor RefreshStageRecorder {
  private(set) var values: [CatalogRefreshStage] = []
  func record(_ stage: CatalogRefreshStage) { values.append(stage) }
}

private actor RefreshCommitRecorder {
  private(set) var values: [SourceConfiguration.ID] = []
  func record(_ sourceID: SourceConfiguration.ID) { values.append(sourceID) }
}

private actor SequenceRefreshClock: CatalogRefreshClock {
  private var dates: [Date]
  private var index = 0

  init(_ dates: [Date]) { self.dates = dates }

  func now() -> Date {
    guard !dates.isEmpty else { return Date(timeIntervalSince1970: 0) }
    let date = dates[min(index, dates.count - 1)]
    index += 1
    return date
  }
}

private actor RoutingDelayedM3UTransport: M3UAcquisitionTransport {
  private var slowStarted = false

  func data(for request: URLRequest, maximumByteCount: Int) async throws
    -> (Data, HTTPURLResponse)
  {
    let url = try #require(request.url)
    let data: Data
    if url.path.contains("slow") {
      slowStarted = true
      try await Task.sleep(for: .seconds(1))
      data = Data(
        "#EXTM3U\n#EXTINF:-1,Slow New\nhttps://example.invalid/slow-new.ts\n".utf8)
    } else {
      data = Data("#EXTM3U\n#EXTINF:-1,Fast\nhttps://example.invalid/fast.ts\n".utf8)
    }
    let response = try #require(
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
    return (data, response)
  }

  func waitUntilSlowRequestStarts() async {
    while !slowStarted { await Task.yield() }
  }
}
