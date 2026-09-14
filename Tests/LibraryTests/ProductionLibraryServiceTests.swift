import Domain
import Foundation
import Library
import Persistence
import Playback
import Testing

@Suite("Production library presentation", .serialized)
struct ProductionLibraryServiceTests {
  @Test("Presentation maps only real catalog metadata and keeps M3U unspecified")
  func safePresentationMapping() async throws {
    let sourceID = fixedSourceID(1)
    let scope = CatalogScope(sourceID: sourceID, origin: .m3u, kind: .unspecified)
    let catalog = PresentationCatalogStub(
      items: [
        CatalogItem(
          id: "m3u-item",
          scope: scope,
          title: "Movie Live 2028.m3u8",
          categoryID: "mixed",
          artworkURL: URL(string: "https://images.example.invalid/poster.jpg?opaque=value"),
          mediaURL: URL(string: "https://media.example.invalid/private.m3u8?token=secret")
        )
      ],
      categories: [
        CatalogCategorySummary(
          category: CatalogCategory(id: "mixed", scope: scope, title: "Mixed"),
          itemCount: 1
        )
      ]
    )
    let sources = SourceManagingStub(sources: [
      managedSource(sourceID, name: "Disabled M3U", enabled: false)
    ])
    let service = ProductionLibraryService(catalog: catalog, sourceService: sources)

    let context = try await service.context()
    #expect(
      context.sources == [
        LibrarySourcePresentation(id: sourceID, name: "Disabled M3U", isEnabled: false)
      ])

    let category = try #require(
      try await service.categories(
        matching: LibraryQuery(scope: .playlist), page: LibraryPageRequest()
      ).first
    )
    let item = try #require(
      try await service.items(
        matching: LibraryQuery(scope: .playlist, category: category), page: LibraryPageRequest()
      ).first
    )
    #expect(item.id == "m3u-item")
    #expect(item.title == "Movie Live 2028.m3u8")
    #expect(item.mediaKind == .unspecified)
    #expect(item.sourceName == "Disabled M3U")
    #expect(item.categoryTitle == "Mixed")
    #expect(item.artworkURL?.host == "images.example.invalid")

    let propertyNames = Set(Mirror(reflecting: item).children.compactMap(\.label))
    #expect(!propertyNames.contains("mediaURL"))
    #expect(!propertyNames.contains("providerReference"))
    #expect(!propertyNames.contains("synopsis"))
    #expect(!propertyNames.contains("progress"))
    #expect(!propertyNames.contains("rating"))
    #expect(!propertyNames.contains("year"))
    #expect(!propertyNames.contains("genre"))
    #expect(!propertyNames.contains("isFavorite"))
    #expect(!propertyNames.contains("continueWatching"))
    #expect(!propertyNames.contains("episode"))
  }

  @Test("Stable catalog IDs and source display names survive repeated presentation mapping")
  func stableIdentityAndSourceNames() async throws {
    let firstSource = fixedSourceID(10)
    let secondSource = fixedSourceID(11)
    let firstScope = CatalogScope(sourceID: firstSource, origin: .xtream, kind: .vod)
    let secondScope = CatalogScope(sourceID: secondSource, origin: .m3u, kind: .unspecified)
    let catalog = PresentationCatalogStub(
      items: [
        CatalogItem(id: "stable-a", scope: firstScope, title: "A"),
        CatalogItem(id: "stable-b", scope: secondScope, title: "B"),
      ],
      categories: []
    )
    let sources = SourceManagingStub(sources: [
      managedSource(firstSource, name: "Cinema Source", enabled: true),
      managedSource(secondSource, name: "Disabled Playlist", enabled: false),
    ])
    let service = ProductionLibraryService(catalog: catalog, sourceService: sources)

    let first = try await service.items(matching: LibraryQuery(), page: LibraryPageRequest())
    let second = try await service.items(matching: LibraryQuery(), page: LibraryPageRequest())

    #expect(first.map(\.id) == ["stable-a", "stable-b"])
    #expect(second.map(\.id) == first.map(\.id))
    #expect(first.map(\.sourceName) == ["Cinema Source", "Disabled Playlist"])
    #expect(first.last?.mediaKind == .unspecified)
  }

  @Test("Scopes and source filters delegate to the production query boundary")
  func queryFilters() async throws {
    let sourceID = fixedSourceID(2)
    let catalog = PresentationCatalogStub(items: [], categories: [])
    let source = SourceManagingStub(sources: [managedSource(sourceID, name: "Main", enabled: true)])
    let service = ProductionLibraryService(catalog: catalog, sourceService: source)
    _ = try await service.context()

    for (scope, origin, kind) in [
      (LibraryBrowseScope.movies, CatalogOrigin.xtream, CatalogMediaKind.vod),
      (.series, .xtream, .series),
      (.liveTV, .xtream, .live),
      (.playlist, .m3u, .unspecified),
    ] {
      _ = try await service.items(
        matching: LibraryQuery(scope: scope, sourceID: sourceID), page: LibraryPageRequest())
      let filter = await catalog.lastFilter
      #expect(filter?.sourceID == sourceID)
      #expect(filter?.origin == origin)
      #expect(filter?.kind == kind)
    }

    let before = await catalog.requestCount
    let empty = try await service.items(
      matching: LibraryQuery(scope: .search, searchText: "  \n "), page: LibraryPageRequest())
    #expect(empty.isEmpty)
    #expect(await catalog.requestCount == before)
  }

  @Test("Category identity preserves source and scope")
  func categoryIdentity() async throws {
    let first = fixedSourceID(3)
    let second = fixedSourceID(4)
    let categories = [
      categorySummary("same", "News", source: first, kind: .live),
      categorySummary("same", "News", source: second, kind: .live),
    ]
    let catalog = PresentationCatalogStub(items: [], categories: categories)
    let sources = SourceManagingStub(sources: [
      managedSource(first, name: "A", enabled: true),
      managedSource(second, name: "B", enabled: true),
    ])
    let service = ProductionLibraryService(catalog: catalog, sourceService: sources)
    let mapped = try await service.categories(matching: LibraryQuery(), page: LibraryPageRequest())
    #expect(mapped.count == 2)
    #expect(mapped[0].id != mapped[1].id)
    #expect(mapped.map(\.itemCount) == [1, 1])

    let selected = try #require(mapped.last)
    _ = try await service.items(
      matching: LibraryQuery(
        scope: .movies,
        sourceID: first,
        category: selected
      ),
      page: LibraryPageRequest()
    )
    let selectedFilter = await catalog.lastFilter
    #expect(selectedFilter?.sourceID == second)
    #expect(selectedFilter?.origin == .xtream)
    #expect(selectedFilter?.kind == .live)
    #expect(selectedFilter?.categoryID == "same")
  }

  @Test(
    "Continue Watching joins only resumable current catalog items in deterministic bounded order")
  func continueWatchingEligibilityOrderingAndSafety() async throws {
    let source = fixedSourceID(42)
    let vod = CatalogScope(sourceID: source, origin: .xtream, kind: .vod)
    let live = CatalogScope(sourceID: source, origin: .xtream, kind: .live)
    let catalog = PresentationCatalogStub(
      items: [
        CatalogItem(
          id: "new", scope: vod, title: "Newest",
          artworkURL: URL(string: "https://image.invalid/new")),
        CatalogItem(id: "old", scope: vod, title: "Older"),
        CatalogItem(id: "live", scope: live, title: "Live"),
      ], categories: [])
    let progress = ContinueWatchingProgressStub(records: [
      WatchProgress(
        mediaID: "old", position: 20, duration: 100, updatedAt: Date(timeIntervalSince1970: 10),
        isCompleted: false),
      WatchProgress(
        mediaID: "new", position: 10, duration: 100, updatedAt: Date(timeIntervalSince1970: 20),
        isCompleted: false),
      WatchProgress(
        mediaID: "live", position: 10, duration: 100, updatedAt: Date(timeIntervalSince1970: 30),
        isCompleted: false),
      WatchProgress(
        mediaID: "complete", position: 100, duration: 100,
        updatedAt: Date(timeIntervalSince1970: 40), isCompleted: true),
      WatchProgress(
        mediaID: "orphan", position: 10, duration: 100, updatedAt: Date(timeIntervalSince1970: 50),
        isCompleted: false),
    ])
    let service = ProductionContinueWatchingService(
      catalog: catalog, progressRepository: progress, maximumItems: 1)
    let items = try await service.items()
    #expect(items.map(\.id) == ["new"])
    #expect(items.first?.progressFraction == 0.1)
    let names = Set(Mirror(reflecting: try #require(items.first)).children.compactMap(\.label))
    #expect(!names.contains("mediaURL"))
    #expect(!names.contains("providerReference"))
    #expect(!names.contains("sourceID"))
  }

  @Test("Paging suppresses duplicate requests and rejects stale results")
  func pagingConcurrency() async throws {
    let service = PagingServiceStub()
    let pager = LibraryPagingController(service: service, pageSize: 2, maximumLoadedItems: 4)
    _ = await pager.restart(query: LibraryQuery(scope: .library))

    async let first = pager.loadNext()
    async let duplicate = pager.loadNext()
    _ = await (first, duplicate)
    #expect(await service.requestCount == 2)

    let slow = Task { await pager.restart(query: LibraryQuery(scope: .search, searchText: "slow")) }
    try await Task.sleep(for: .milliseconds(10))
    let fast = await pager.restart(query: LibraryQuery(scope: .search, searchText: "fast"))
    _ = await slow.value
    #expect(fast.query.searchText == "fast")
    #expect(fast.items.allSatisfy { $0.title.contains("fast") })
    #expect(await pager.snapshot().query.searchText == "fast")
  }

  @Test("Restart cancels the stale service request")
  func pagingCancellation() async throws {
    let service = CancellablePagingServiceStub()
    let pager = LibraryPagingController(service: service, pageSize: 2, maximumLoadedItems: 4)

    let stale = Task {
      await pager.restart(query: LibraryQuery(scope: .search, searchText: "blocked"))
    }
    while await service.startedRequestCount == 0 {
      try await Task.sleep(for: .milliseconds(1))
    }

    let current = await pager.restart(
      query: LibraryQuery(scope: .search, searchText: "current"))
    _ = await stale.value

    #expect(await service.cancelledRequestCount == 1)
    #expect(current.query.searchText == "current")
    #expect(current.items.map(\.id) == ["current-item"])
    #expect(await pager.snapshot() == current)
  }

  @Test("A new query and cleared filters restart pagination from zero")
  func queryAndFilterReset() async {
    let service = PagingServiceStub(totalCount: 8)
    let pager = LibraryPagingController(service: service, pageSize: 2, maximumLoadedItems: 4)
    _ = await pager.restart(
      query: LibraryQuery(scope: .movies, sourceID: fixedSourceID(12)))
    _ = await pager.loadNext()

    let resetQuery = LibraryQuery(scope: .library, sourceID: nil, category: nil, searchText: "")
    let reset = await pager.restart(query: resetQuery)
    let requests = await service.requests

    #expect(reset.query == resetQuery)
    #expect(reset.nextOffset == 2)
    #expect(reset.items.map(\.id) == ["-item-0", "-item-1"])
    #expect(requests.map(\.page.offset) == [0, 2, 0])
    #expect(requests.last?.query.sourceID == nil)
    #expect(requests.last?.query.category == nil)
  }

  @Test("Paging defensively deduplicates and keeps a bounded focus-safe window")
  func boundedWindow() async {
    let service = PagingServiceStub(totalCount: 420, duplicateAtPageBoundary: true)
    let pager = LibraryPagingController(service: service, pageSize: 64, maximumLoadedItems: 256)
    var snapshot = await pager.restart(query: LibraryQuery())
    let protectedID = snapshot.items.first?.id
    while snapshot.hasMore {
      snapshot = await pager.loadNext(protecting: protectedID)
    }
    #expect(snapshot.items.count <= 256)
    #expect(Set(snapshot.items.map(\.id)).count == snapshot.items.count)
    #expect(protectedID == nil || snapshot.items.contains(where: { $0.id == protectedID }))
    #expect(snapshot.nextOffset == 420)
  }

  @Test("Refresh revisions are emitted only when explicitly published")
  func refreshInvalidation() async {
    let center = LibraryRevisionCenter()
    let stream = await center.stream()
    let revision = Task { () -> UInt64? in
      for await value in stream { return value }
      return nil
    }

    await center.publish(sourceID: fixedSourceID(13))

    #expect(await revision.value == 1)
  }

  @Test("Query errors are normalized without retaining implementation errors")
  func errorNormalization() async throws {
    let sourceID = fixedSourceID(5)
    let catalog = PresentationCatalogStub(
      items: [], categories: [], failure: CatalogStoreError.corruptedStore)
    let sources = SourceManagingStub(sources: [managedSource(sourceID, name: "A", enabled: true)])
    let service = ProductionLibraryService(catalog: catalog, sourceService: sources)
    await #expect(throws: ProductionLibraryError.unavailable) { try await service.context() }

    let invalidCatalog = PresentationCatalogStub(
      items: [], categories: [], failure: CatalogStoreError.invalidInput)
    let invalidService = ProductionLibraryService(
      catalog: invalidCatalog, sourceService: sources)
    await #expect(throws: ProductionLibraryError.invalidRequest) {
      try await invalidService.items(matching: LibraryQuery(), page: LibraryPageRequest())
    }
  }

  @Test("Page requests enforce the repository bounds")
  func pageRequestBounds() {
    let lower = LibraryPageRequest(limit: 0, offset: -4)
    let upper = LibraryPageRequest(limit: 10_000, offset: 8)
    #expect(lower.limit == 1)
    #expect(lower.offset == 0)
    #expect(upper.limit == CatalogPage.maximumSize)
    #expect(upper.offset == 8)
  }

  @Test(
    "Application composition remains bounded for large catalog scales",
    arguments: [10_000, 50_000, 100_000]
  )
  func largeCatalogComposition(entryCount: Int) async {
    let service = PagingServiceStub(totalCount: entryCount)
    let pager = LibraryPagingController(service: service)
    let clock = ContinuousClock()
    let start = clock.now
    var snapshot = await pager.restart(query: LibraryQuery())
    for _ in 0..<5 where snapshot.hasMore {
      snapshot = await pager.loadNext()
    }
    let elapsed = start.duration(to: clock.now)
    #expect(snapshot.items.count == LibraryPagingController.defaultMaximumLoadedItems)
    #expect(snapshot.nextOffset == 384)
    print(
      "PRODUCTION-LIBRARY rows=\(entryCount) mapped=\(snapshot.nextOffset) window=\(snapshot.items.count) elapsed=\(elapsed)"
    )
  }
}

private actor PresentationCatalogStub: CatalogLibraryQuerying {
  let storedItems: [CatalogItem]
  let storedCategories: [CatalogCategorySummary]
  let failure: (any Error)?
  private(set) var lastFilter: CatalogFilter?
  private(set) var requestCount = 0

  init(
    items: [CatalogItem],
    categories: [CatalogCategorySummary],
    failure: (any Error)? = nil
  ) {
    storedItems = items
    storedCategories = categories
    self.failure = failure
  }

  func browseItems(matching filter: CatalogFilter, page: CatalogPage) throws -> [CatalogItem] {
    try failIfNeeded()
    lastFilter = filter
    requestCount += 1
    return pageValues(storedItems, page: page)
  }

  func searchItems(
    _ text: String, matching filter: CatalogFilter, page: CatalogPage
  ) throws -> [CatalogItem] {
    try failIfNeeded()
    lastFilter = filter
    requestCount += 1
    let terms = text.lowercased().split(whereSeparator: \.isWhitespace)
    return pageValues(
      storedItems.filter { item in terms.allSatisfy { item.title.lowercased().contains($0) } },
      page: page
    )
  }

  func categories(
    matching filter: CatalogFilter, page: CatalogPage
  ) throws -> [CatalogCategorySummary] {
    try failIfNeeded()
    lastFilter = filter
    return pageValues(storedCategories, page: page)
  }

  func item(id: String) throws -> CatalogItem? {
    try failIfNeeded()
    return storedItems.first { $0.id == id }
  }

  func itemCount(matching _: CatalogFilter) throws -> Int {
    try failIfNeeded()
    return storedItems.count
  }

  func sourceCatalogCount(sourceID _: SourceConfiguration.ID?) throws -> Int {
    try failIfNeeded()
    return storedItems.isEmpty ? 0 : 1
  }

  private func failIfNeeded() throws {
    if let failure { throw failure }
  }
}

private actor PagingServiceStub: ProductionLibraryServing {
  struct Request: Sendable {
    let query: LibraryQuery
    let page: LibraryPageRequest
  }

  let totalCount: Int
  let duplicateAtPageBoundary: Bool
  private(set) var requestCount = 0
  private(set) var requests: [Request] = []

  init(totalCount: Int = 8, duplicateAtPageBoundary: Bool = false) {
    self.totalCount = totalCount
    self.duplicateAtPageBoundary = duplicateAtPageBoundary
  }

  func context() -> ProductionLibraryContext {
    ProductionLibraryContext(sources: [], committedCatalogCount: 1, itemCount: totalCount)
  }

  func items(matching query: LibraryQuery, page: LibraryPageRequest) async
    -> [LibraryItemPresentation]
  {
    requestCount += 1
    requests.append(Request(query: query, page: page))
    if query.searchText == "slow" {
      try? await Task.sleep(for: .milliseconds(80))
    }
    guard page.offset < totalCount else { return [] }
    var indices = Array(page.offset..<min(totalCount, page.offset + page.limit))
    if duplicateAtPageBoundary, page.offset > 0, !indices.isEmpty {
      indices[0] = page.offset - 1
    }
    return indices.map {
      LibraryItemPresentation(
        id: "\(query.searchText)-item-\($0)",
        title: "\(query.searchText)-title-\($0)",
        mediaKind: .vod,
        sourceID: fixedSourceID(9),
        sourceName: "Fixture",
        categoryID: nil,
        categoryTitle: nil,
        artworkURL: nil
      )
    }
  }

  func categories(matching _: LibraryQuery, page _: LibraryPageRequest)
    -> [LibraryCategoryPresentation]
  {
    []
  }

  func revisions() -> AsyncStream<UInt64> { AsyncStream { $0.finish() } }
}

private actor CancellablePagingServiceStub: ProductionLibraryServing {
  private(set) var startedRequestCount = 0
  private(set) var cancelledRequestCount = 0

  func context() -> ProductionLibraryContext {
    ProductionLibraryContext(sources: [], committedCatalogCount: 1, itemCount: 1)
  }

  func items(
    matching query: LibraryQuery, page _: LibraryPageRequest
  ) async throws -> [LibraryItemPresentation] {
    startedRequestCount += 1
    if query.searchText == "blocked" {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch is CancellationError {
        cancelledRequestCount += 1
        throw CancellationError()
      }
    }
    return [
      LibraryItemPresentation(
        id: "\(query.searchText)-item",
        title: query.searchText,
        mediaKind: .vod,
        sourceID: fixedSourceID(14),
        sourceName: "Fixture",
        categoryID: nil,
        categoryTitle: nil,
        artworkURL: nil
      )
    ]
  }

  func categories(
    matching _: LibraryQuery, page _: LibraryPageRequest
  ) -> [LibraryCategoryPresentation] { [] }

  func revisions() -> AsyncStream<UInt64> { AsyncStream { $0.finish() } }
}

private actor ContinueWatchingProgressStub: WatchProgressRepository {
  let records: [WatchProgress]
  init(records: [WatchProgress]) { self.records = records }
  func progress(for mediaID: String) -> WatchProgress? { records.first { $0.mediaID == mediaID } }
  func allProgress() -> [WatchProgress] { records }
  func save(_: WatchProgress) {}
  func remove(mediaID _: String) {}
}

private actor SourceManagingStub: SourceManaging {
  let storedSources: [ManagedSource]
  init(sources: [ManagedSource]) { storedSources = sources }
  func listSources() -> [ManagedSource] { storedSources }
  func source(id: SourceConfiguration.ID) -> ManagedSource? { storedSources.first { $0.id == id } }
  func validateDraft(_: SourceDraft, editing _: SourceConfiguration.ID?) -> [SourceValidationIssue]
  { [] }
  func createSource(from _: SourceDraft) throws -> SourceConfiguration {
    throw SourceManagementError.persistenceFailure
  }
  func updateSource(id _: SourceConfiguration.ID, from _: SourceDraft) throws -> SourceConfiguration
  { throw SourceManagementError.persistenceFailure }
  func deleteSource(id _: SourceConfiguration.ID) throws {
    throw SourceManagementError.persistenceFailure
  }
  func setEnabled(_: Bool, id _: SourceConfiguration.ID) throws {
    throw SourceManagementError.persistenceFailure
  }
  func testConnection(_: SourceDraft, editing _: SourceConfiguration.ID?) throws
    -> SourceConnectionReport
  { throw SourceManagementError.unreachableProvider }
  func refreshNow(id _: SourceConfiguration.ID, onStage _: CatalogRefreshStageHandler?) throws
    -> CatalogRefreshReport
  { throw SourceManagementError.unreachableProvider }
}

private func fixedSourceID(_ suffix: UInt8) -> SourceConfiguration.ID {
  SourceConfiguration.ID(
    rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix)))
}

private func managedSource(
  _ id: SourceConfiguration.ID, name: String, enabled: Bool
) -> ManagedSource {
  ManagedSource(
    configuration: SourceConfiguration(
      id: id,
      displayName: name,
      kind: .m3u,
      endpoint: URL(string: "https://example.invalid/list.m3u").flatMap {
        try? SourceEndpoint(url: $0)
      },
      isEnabled: enabled
    ),
    refreshMetadata: nil
  )
}

private func categorySummary(
  _ id: String,
  _ title: String,
  source: SourceConfiguration.ID,
  kind: CatalogMediaKind
) -> CatalogCategorySummary {
  let scope = CatalogScope(sourceID: source, origin: .xtream, kind: kind)
  return CatalogCategorySummary(
    category: CatalogCategory(id: id, scope: scope, title: title), itemCount: 1)
}

private func pageValues<Value>(_ values: [Value], page: CatalogPage) -> [Value] {
  guard page.offset < values.count else { return [] }
  return Array(values[page.offset..<min(values.count, page.offset + page.limit)])
}
