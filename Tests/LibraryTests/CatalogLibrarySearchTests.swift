import CryptoKit
import Domain
import Foundation
import IPTVCore
import Library
import Persistence
import Testing

@testable import Persistence

@Suite("Production library search and categories")
struct CatalogLibrarySearchTests {
  @Test("Literal normalized search handles language, whitespace, punctuation, and empty queries")
  func searchSemantics() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let service = CatalogLibraryService(repository: store)
    let category = CatalogCategory(id: "news", scope: fixture.scope, title: "News")
    let longTitle = String(repeating: "ط", count: 8_000) + " Finale"
    let values = [
      fixture.item(0, title: "Café   NEWS 24", category: category.id),
      fixture.item(1, title: "قناة العربية HD 2026", category: category.id),
      fixture.item(2, title: "MBC مصر 2", category: category.id),
      fixture.item(3, title: "News: World! 📺", category: category.id),
      fixture.item(4, title: "Same Title", category: category.id),
      fixture.item(5, title: "Same Title", category: category.id),
      fixture.item(6, title: longTitle, category: category.id),
    ]
    try await replace(store, scope: fixture.scope, items: values, categories: [category])

    #expect(try CatalogSearchQuery("  CAFÉ\tالعربية  ").normalizedText == "cafe العربية")
    #expect(try await titles(service, "  CAFÉ\t24  ") == ["Café   NEWS 24"])
    #expect(try await titles(service, "news cafe") == ["Café   NEWS 24"])
    #expect(try await titles(service, "العربية 2026") == ["قناة العربية HD 2026"])
    #expect(try await titles(service, "MBC   مصر") == ["MBC مصر 2"])
    #expect(try await titles(service, "news:") == ["News: World! 📺"])
    #expect(try await titles(service, "📺") == ["News: World! 📺"])
    #expect(try await titles(service, "alarabiya").isEmpty)
    #expect(try await titles(service, "not-present").isEmpty)
    #expect(try await titles(service, "finale") == [longTitle])

    let emptySearch = try await service.searchItems(" \n\t", page: CatalogPage())
    let browse = try await service.browseItems(page: CatalogPage())
    #expect(emptySearch == browse)
    let duplicates = try await service.searchItems("same", page: CatalogPage())
    #expect(duplicates.map(\.id) == duplicates.map(\.id).sorted())
    await store.close()
  }

  @Test("Source, origin, kind, category, and combined filters cannot leak rows")
  func filterAndCategoryIsolation() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let sourceA = fixture.sourceID
    let sourceB = SourceConfiguration.ID()
    let scopes = [
      CatalogScope(sourceID: sourceA, origin: .xtream, kind: .live),
      CatalogScope(sourceID: sourceA, origin: .xtream, kind: .vod),
      CatalogScope(sourceID: sourceA, origin: .xtream, kind: .series),
      CatalogScope(sourceID: sourceB, origin: .xtream, kind: .live),
      CatalogScope(sourceID: sourceB, origin: .m3u, kind: .unspecified),
    ]
    for (index, scope) in scopes.enumerated() {
      let category = CatalogCategory(
        id: "category-\(index)", scope: scope, title: "Category \(index)")
      let items = (0..<(index + 1)).map {
        catalogItem(index * 100 + $0, scope: scope, title: "Shared \(index)", category: category.id)
      }
      let categories =
        index == 0
        ? [category, CatalogCategory(id: "empty-category", scope: scope, title: "Empty")]
        : [category]
      try await replace(store, scope: scope, items: items, categories: categories)
    }
    let service = CatalogLibraryService(repository: store)

    #expect(
      try await service.itemCount(matching: CatalogFilter(sourceID: sourceA, kind: .live)) == 1)
    #expect(
      try await service.itemCount(matching: CatalogFilter(sourceID: sourceA, kind: .vod)) == 2)
    #expect(
      try await service.itemCount(matching: CatalogFilter(sourceID: sourceA, kind: .series)) == 3)
    #expect(try await service.itemCount(matching: CatalogFilter(sourceID: sourceB)) == 9)
    #expect(try await service.sourceCatalogCount(sourceID: sourceA) == 3)
    #expect(try await service.itemCount(matching: CatalogFilter(origin: .m3u)) == 5)
    #expect(try await service.itemCount(matching: CatalogFilter(origin: .xtream)) == 10)
    #expect(
      try await service.itemCount(
        matching: CatalogFilter(sourceID: sourceB, origin: .xtream, kind: .live)) == 4)
    #expect(
      try await service.itemCount(matching: CatalogFilter(categoryID: "category-1")) == 2)

    let categories = try await service.categories(
      matching: CatalogFilter(sourceID: sourceA, origin: .xtream), page: CatalogPage())
    #expect(categories.count == 4)
    #expect(categories.map(\.itemCount).sorted() == [0, 1, 2, 3])
    let m3uGroups = try await service.categories(
      matching: CatalogFilter(sourceID: sourceB, origin: .m3u, kind: .unspecified),
      page: CatalogPage())
    #expect(m3uGroups.map(\.category.title) == ["Category 4"])
    #expect(m3uGroups.first?.itemCount == 5)

    let combined = try await service.searchItems(
      "shared", matching: CatalogFilter(sourceID: sourceA, kind: .vod), page: CatalogPage())
    #expect(combined.count == 2)
    #expect(combined.allSatisfy { $0.scope.sourceID == sourceA && $0.scope.kind == .vod })

    await #expect(throws: CatalogStoreError.invalidInput) {
      try await service.browseItems(
        matching: CatalogFilter(origin: .m3u, kind: .live), page: CatalogPage())
    }
    await #expect(throws: CatalogStoreError.invalidInput) {
      try await service.categories(
        matching: CatalogFilter(categoryID: " "), page: CatalogPage())
    }

    try await store.deleteCatalog(sourceID: sourceB)
    #expect(try await service.itemCount(matching: CatalogFilter(sourceID: sourceB)) == 0)
    #expect(
      try await service.categories(matching: CatalogFilter(sourceID: sourceB), page: CatalogPage())
        .isEmpty)
    await store.close()
  }

  @Test("Offset pages are bounded, repeatable, and use stable ID tie-breaking")
  func paginationStability() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let items = (0..<513).reversed().map { fixture.item($0, title: "Duplicate") }
    try await replace(store, scope: fixture.scope, items: items)
    let service = CatalogLibraryService(repository: store)
    let page = try CatalogPage(limit: 128)
    let first = try await service.searchItems("duplicate", page: page)
    let repeated = try await service.searchItems("duplicate", page: page)
    let second = try await service.searchItems(
      "duplicate", page: CatalogPage(limit: 128, offset: 128))
    #expect(first == repeated)
    #expect(first.count == 128 && second.count == 128)
    #expect(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
    #expect((first + second).map(\.id) == (first + second).map(\.id).sorted())
    await store.close()
  }

  @Test("Invalid and cancelled search input fails safely")
  func invalidAndCancelledSearch() async throws {
    #expect(throws: CatalogStoreError.invalidInput) {
      try CatalogSearchQuery(
        String(repeating: "x", count: CatalogSearchQuery.maximumUTF8Length + 1))
    }
    #expect(throws: CatalogStoreError.invalidInput) {
      try CatalogSearchQuery(
        (0...CatalogSearchQuery.maximumTermCount).map(String.init).joined(separator: " "))
    }
    #expect(throws: CatalogStoreError.invalidInput) { try CatalogSearchQuery("invalid\0query") }

    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let emptyService = CatalogLibraryService(repository: store)
    #expect(try await emptyService.browseItems(page: CatalogPage()).isEmpty)
    #expect(try await emptyService.searchItems("anything", page: CatalogPage()).isEmpty)
    #expect(try await emptyService.categories(page: CatalogPage()).isEmpty)
    #expect(try await emptyService.itemCount() == 0)
    try await fixture.seed(store)
    let service = CatalogLibraryService(repository: store)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await service.searchItems("catalog", page: CatalogPage())
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    await store.close()
  }

  @Test("Search and categories retain catalog A while refresh B is staged, then publish B")
  func refreshStagingVisibility() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let source = try m3uSource(id: fixture.sourceID)
    let scope = CatalogScope(sourceID: source.id, origin: .m3u, kind: .unspecified)
    let oldCategory = CatalogCategory(id: "old-category", scope: scope, title: "Old Group")
    try await replace(
      store, scope: scope,
      items: [catalogItem(0, scope: scope, title: "Catalog Old", category: oldCategory.id)],
      categories: [oldCategory])

    let pausingRepository = PausingRefreshRepository(store: store)
    let body = Data(
      "#EXTM3U\n#EXTINF:-1 group-title=\"New Group\",Catalog New\nhttps://example.invalid/new.ts\n"
        .utf8)
    let refresh = CatalogRefreshService(
      repository: pausingRepository,
      m3uAcquisition: M3UAcquisitionService(
        transport: SyntheticM3UTransport(behavior: .response(status: 200, data: body))),
      providerAdapter: SearchUnusedProviderAdapter())
    let refreshTask = Task { try await refresh.refresh(source) }
    await pausingRepository.waitUntilFirstStageCompletes()

    let service = CatalogLibraryService(repository: store)
    #expect(try await titles(service, "catalog old") == ["Catalog Old"])
    #expect(try await titles(service, "catalog new").isEmpty)
    #expect(
      try await service.categories(
        matching: CatalogFilter(sourceID: source.id), page: CatalogPage()
      )
      .map(\.category.title) == ["Old Group"])

    await pausingRepository.resumeRefresh()
    #expect(try await refreshTask.value.committedItemCount == 1)
    #expect(try await titles(service, "catalog old").isEmpty)
    #expect(try await titles(service, "catalog new") == ["Catalog New"])
    #expect(
      try await service.categories(
        matching: CatalogFilter(sourceID: source.id), page: CatalogPage()
      )
      .map(\.category.title) == ["New Group"])
    await store.close()
  }
}

private func titles(_ service: CatalogLibraryService, _ query: String) async throws -> [String] {
  try await service.searchItems(query, page: CatalogPage()).map(\.title)
}

private func replace(
  _ store: SQLiteCatalogStore,
  scope: CatalogScope,
  items: [CatalogItem],
  categories: [CatalogCategory] = []
) async throws {
  let stagingID = try await store.beginStaging(in: scope)
  for index in stride(from: 0, to: max(items.count, categories.count), by: CatalogPage.maximumSize)
  {
    try await store.stage(
      items: Array(items.dropFirst(index).prefix(CatalogPage.maximumSize)),
      categories: Array(categories.dropFirst(index).prefix(CatalogPage.maximumSize)),
      in: stagingID)
  }
  try await store.commitStagedReplacement(stagingID)
}

private func catalogItem(
  _ index: Int, scope: CatalogScope, title: String, category: String? = nil
) -> CatalogItem {
  if scope.origin == .m3u {
    return CatalogItem(
      id: "m3u-\(scope.sourceID.rawValue.uuidString)-\(index)", scope: scope, title: title,
      categoryID: category, mediaURL: URL(string: "https://example.invalid/\(index).ts"))
  }
  let kind = ProviderMediaKind(rawValue: scope.kind.rawValue) ?? .live
  let reference = ProviderItemReference(kind: kind, providerID: String(index))
  return CatalogItem(
    id: ProviderCatalogItem.ID(sourceID: scope.sourceID, reference: reference).rawValue,
    scope: scope, title: title, categoryID: category, providerReference: reference)
}

private actor PausingRefreshRepository: CatalogRefreshRepository {
  private let store: SQLiteCatalogStore
  private var firstStageCompleted = false
  private var shouldResume = false

  init(store: SQLiteCatalogStore) { self.store = store }

  func beginStaging(in scope: CatalogScope) async throws -> UUID {
    try await store.beginStaging(in: scope)
  }

  func beginStaging(in scopes: [CatalogScope]) async throws -> UUID {
    try await store.beginStaging(in: scopes)
  }

  func stage(items: [CatalogItem], categories: [CatalogCategory], in stagingID: UUID) async throws {
    try await store.stage(items: items, categories: categories, in: stagingID)
    guard !firstStageCompleted else { return }
    firstStageCompleted = true
    while !shouldResume {
      try Task.checkCancellation()
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  func commitStagedReplacement(_ stagingID: UUID) async throws {
    try await store.commitStagedReplacement(stagingID)
  }

  func commitStagedReplacement(
    _ stagingID: UUID, successfulRefresh metadata: CatalogRefreshMetadata
  ) async throws -> Int {
    try await store.commitStagedReplacement(stagingID, successfulRefresh: metadata)
  }

  func discardStaging(_ stagingID: UUID) async { await store.discardStaging(stagingID) }

  func deleteCatalog(sourceID: SourceConfiguration.ID) async throws {
    try await store.deleteCatalog(sourceID: sourceID)
  }

  func recordRefreshAttempt(
    sourceID: SourceConfiguration.ID, attemptedAt: Date, result: CatalogRefreshResultCategory
  ) async throws {
    try await store.recordRefreshAttempt(
      sourceID: sourceID, attemptedAt: attemptedAt, result: result)
  }

  func refreshMetadata(for sourceID: SourceConfiguration.ID) async throws
    -> CatalogRefreshMetadata?
  {
    try await store.refreshMetadata(for: sourceID)
  }

  func waitUntilFirstStageCompletes() async {
    while !firstStageCompleted { await Task.yield() }
  }

  func resumeRefresh() { shouldResume = true }
}

private struct SearchUnusedProviderAdapter: ProviderAdapter {
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
