import Domain
import Foundation
import Library
import Persistence
import Testing

@Suite("Phase 2F library query performance", .serialized)
struct CatalogLibrarySearchPerformanceTests {
  @Test(
    "Bounded browse, category, lookup, count, and search", arguments: [10_000, 50_000, 100_000])
  func queries(entryCount: Int) async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await writeCatalog(store, fixture: fixture, count: entryCount)
    let service = CatalogLibraryService(repository: store)
    let page = try CatalogPage(limit: 64)
    let middlePage = try CatalogPage(limit: 64, offset: entryCount / 2)
    let categoryFilter = CatalogFilter(
      sourceID: fixture.sourceID, origin: .xtream, kind: .live, categoryID: "category-42")
    let categoryListFilter = CatalogFilter(
      sourceID: fixture.sourceID, origin: .xtream, kind: .live)

    #expect(try await service.browseItems(page: page).count == 64)
    #expect(try await service.browseItems(page: middlePage).count == 64)
    let adjacentMiddlePage = try await service.browseItems(
      page: CatalogPage(limit: 64, offset: entryCount / 2 + 64))
    let middleItems = try await service.browseItems(page: middlePage)
    #expect(Set(middleItems.map(\.id)).isDisjoint(with: Set(adjacentMiddlePage.map(\.id))))
    #expect(try await service.browseItems(matching: categoryFilter, page: page).count == 64)
    #expect(try await service.categories(matching: categoryListFilter, page: page).count == 64)
    #expect(try await service.item(id: fixture.item(entryCount / 2).id) != nil)
    #expect(try await service.searchItems("common", page: page).count == 64)
    #expect(try await service.searchItems("rare needle", page: page).count == 1)
    #expect(try await service.searchItems("absent needle", page: page).isEmpty)
    #expect(
      try await service.itemCount(matching: CatalogFilter(sourceID: fixture.sourceID)) == entryCount
    )

    let operations: [(String, () async throws -> Void)] = [
      ("first-page", { _ = try await service.browseItems(page: page) }),
      ("middle-page", { _ = try await service.browseItems(page: middlePage) }),
      (
        "category-items",
        { _ = try await service.browseItems(matching: categoryFilter, page: page) }
      ),
      (
        "category-list",
        { _ = try await service.categories(matching: categoryListFilter, page: page) }
      ),
      ("item-id", { _ = try await service.item(id: fixture.item(entryCount / 2).id) }),
      ("common-search", { _ = try await service.searchItems("common", page: page) }),
      ("rare-search", { _ = try await service.searchItems("rare needle", page: page) }),
      ("no-result-search", { _ = try await service.searchItems("absent needle", page: page) }),
      (
        "source-count",
        {
          _ = try await service.itemCount(matching: CatalogFilter(sourceID: fixture.sourceID))
        }
      ),
    ]
    for (name, operation) in operations {
      let duration = try await medianDuration(operation: operation)
      print("LIBRARY-QUERY rows=\(entryCount) operation=\(name) elapsed=\(duration)")
    }
    await store.close()
  }

  private func writeCatalog(_ store: SQLiteCatalogStore, fixture: CatalogFixture, count: Int)
    async throws
  {
    let stagingID = try await store.beginStaging(in: fixture.scope)
    do {
      try await store.stage(
        items: [],
        categories: (0..<100).map {
          CatalogCategory(id: "category-\($0)", scope: fixture.scope, title: "Category \($0)")
        }, in: stagingID)
      for start in stride(from: 0, to: count, by: CatalogPage.maximumSize) {
        let items = (start..<min(count, start + CatalogPage.maximumSize)).map { index in
          fixture.item(
            index,
            title: index == count - 1
              ? "Rare Needle \(String(format: "%06d", index))"
              : "Common Channel \(String(format: "%06d", index))",
            category: "category-\(index % 100)")
        }
        try await store.stage(items: items, categories: [], in: stagingID)
      }
      try await store.commitStagedReplacement(stagingID)
    } catch {
      await store.discardStaging(stagingID)
      throw error
    }
  }

  private func medianDuration(
    samples: Int = 5, operation: () async throws -> Void
  ) async rethrows -> Duration {
    let clock = ContinuousClock()
    var durations: [Duration] = []
    durations.reserveCapacity(samples)
    for _ in 0..<samples {
      let start = clock.now
      try await operation()
      durations.append(start.duration(to: clock.now))
    }
    return durations.sorted()[samples / 2]
  }
}
