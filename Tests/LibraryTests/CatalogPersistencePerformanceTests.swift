import Domain
import Foundation
import Library
import Persistence
import Testing

@Suite("Production catalog persistence benchmarks", .serialized)
struct CatalogPersistencePerformanceTests {
  @Test(
    "Disk-backed encrypted transactional import and bounded indexed queries",
    arguments: [10_000, 50_000, 100_000])
  func catalog(entryCount: Int) async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let clock = ContinuousClock()
    let start = clock.now
    try await writeCatalog(store, fixture: fixture, count: entryCount)
    let importTime = start.duration(to: clock.now)
    var timings: [(String, Duration)] = []
    let page = try CatalogPage(limit: 64)
    let filters: [(String, CatalogFilter)] = [
      ("page", CatalogFilter()),
      ("source", CatalogFilter(sourceID: fixture.sourceID)),
      ("kind", CatalogFilter(kind: .live)),
      ("category", CatalogFilter(categoryID: "category-42")),
    ]
    for (name, filter) in filters {
      let queryStart = clock.now
      let result = try await store.items(matching: filter, page: page)
      timings.append((name, queryStart.duration(to: clock.now)))
      #expect(result.count == 64)
      let again = try await store.items(matching: filter, page: page)
      #expect(again == result)
    }
    let lookupStart = clock.now
    #expect(try await store.item(id: fixture.item(entryCount / 2).id) != nil)
    timings.append(("id", lookupStart.duration(to: clock.now)))
    let countStart = clock.now
    #expect(
      try await store.itemCount(matching: CatalogFilter(sourceID: fixture.sourceID)) == entryCount)
    timings.append(("count", countStart.duration(to: clock.now)))
    let categoriesStart = clock.now
    #expect(
      try await store.categories(
        matching: CatalogFilter(sourceID: fixture.sourceID, kind: .live), page: page
      ).count == 64)
    timings.append(("categories", categoriesStart.duration(to: clock.now)))
    let lastStart = clock.now
    let lastPage = try await store.items(
      matching: CatalogFilter(), page: CatalogPage(limit: 64, offset: entryCount - 32))
    timings.append(("deep-page", lastStart.duration(to: clock.now)))
    #expect(lastPage.count == 32)
    let replacementStart = clock.now
    try await writeCatalog(store, fixture: fixture, count: entryCount)
    let replacementTime = replacementStart.duration(to: clock.now)
    #expect(try await store.itemCount(matching: CatalogFilter()) == entryCount)
    await store.close()
    let reopenStart = clock.now
    let reopened = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    #expect(try await reopened.items(matching: CatalogFilter(), page: page).count == 64)
    let reopenTime = reopenStart.duration(to: clock.now)
    await reopened.close()
    print(
      "CATALOG rows=\(entryCount) import=\(importTime) replacement=\(replacementTime) reopen+page=\(reopenTime)"
    )
    for (name, duration) in timings {
      print("CATALOG rows=\(entryCount) query=\(name) elapsed=\(duration)")
    }
  }

  @Test("M3U parser through encrypted disk persistence", arguments: [10_000, 50_000, 100_000])
  func m3u(entryCount: Int) async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let clock = ContinuousClock()
    for phase in ["import", "replacement"] {
      let start = clock.now
      let report = try await M3UImportService().importPlaylist(
        lines: SyntheticM3ULineSequence(entryCount: entryCount), sourceID: fixture.sourceID,
        sink: PersistentCatalogImportSink(repository: store))
      let elapsed = start.duration(to: clock.now)
      #expect(report.importedCount == entryCount)
      #expect(try await store.itemCount(matching: CatalogFilter()) == entryCount)
      #expect(
        try await store.items(matching: CatalogFilter(), page: CatalogPage(limit: 64)).count == 64)
      print("M3U-DATABASE rows=\(entryCount) phase=\(phase) elapsed=\(elapsed)")
    }
    await store.close()
  }

  private func writeCatalog(_ store: SQLiteCatalogStore, fixture: CatalogFixture, count: Int)
    async throws
  {
    let token = try await store.beginReplacement(in: fixture.scope)
    do {
      try await store.write(
        items: [],
        categories: (0..<100).map {
          CatalogCategory(id: "category-\($0)", scope: fixture.scope, title: "Category \($0)")
        }, transaction: token)
      for start in stride(from: 0, to: count, by: 256) {
        let items = (start..<min(count, start + 256)).map {
          fixture.item($0, category: "category-\($0 % 100)")
        }
        try await store.write(items: items, categories: [], transaction: token)
      }
      try await store.commit(transaction: token)
    } catch {
      await store.rollback(transaction: token)
      throw error
    }
  }
}
