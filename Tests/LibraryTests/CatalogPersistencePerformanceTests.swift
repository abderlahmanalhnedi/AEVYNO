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
    let importPhases = try await writeCatalog(store, fixture: fixture, count: entryCount)
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
      let result = try await store.items(matching: filter, page: page)
      #expect(result.count == 64)
      let again = try await store.items(matching: filter, page: page)
      #expect(again == result)
      let duration = try await medianDuration {
        _ = try await store.items(matching: filter, page: page)
      }
      timings.append((name, duration))
    }
    #expect(try await store.item(id: fixture.item(entryCount / 2).id) != nil)
    timings.append(
      (
        "id",
        try await medianDuration {
          _ = try await store.item(id: fixture.item(entryCount / 2).id)
        }
      ))
    #expect(
      try await store.itemCount(matching: CatalogFilter(sourceID: fixture.sourceID)) == entryCount)
    timings.append(
      (
        "count",
        try await medianDuration {
          _ = try await store.itemCount(matching: CatalogFilter(sourceID: fixture.sourceID))
        }
      ))
    #expect(
      try await store.categories(
        matching: CatalogFilter(sourceID: fixture.sourceID, kind: .live), page: page
      ).count == 64)
    timings.append(
      (
        "categories",
        try await medianDuration {
          _ = try await store.categories(
            matching: CatalogFilter(sourceID: fixture.sourceID, kind: .live), page: page)
        }
      ))
    let lastPage = try await store.items(
      matching: CatalogFilter(), page: CatalogPage(limit: 64, offset: entryCount - 32))
    #expect(lastPage.count == 32)
    timings.append(
      (
        "deep-page",
        try await medianDuration {
          _ = try await store.items(
            matching: CatalogFilter(), page: CatalogPage(limit: 64, offset: entryCount - 32))
        }
      ))
    let replacementStart = clock.now
    let replacementPhases = try await writeCatalog(store, fixture: fixture, count: entryCount)
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
    print(
      "CATALOG-PHASES rows=\(entryCount) import-stage=\(importPhases.staging) import-commit=\(importPhases.commit) replacement-stage=\(replacementPhases.staging) replacement-commit=\(replacementPhases.commit)"
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
    async throws -> (staging: Duration, commit: Duration)
  {
    let clock = ContinuousClock()
    let stagingStart = clock.now
    let stagingID = try await store.beginStaging(in: fixture.scope)
    do {
      try await store.stage(
        items: [],
        categories: (0..<100).map {
          CatalogCategory(id: "category-\($0)", scope: fixture.scope, title: "Category \($0)")
        }, in: stagingID)
      for start in stride(from: 0, to: count, by: 256) {
        let items = (start..<min(count, start + 256)).map {
          fixture.item($0, category: "category-\($0 % 100)")
        }
        try await store.stage(items: items, categories: [], in: stagingID)
      }
      let staging = stagingStart.duration(to: clock.now)
      let commitStart = clock.now
      try await store.commitStagedReplacement(stagingID)
      return (staging, commitStart.duration(to: clock.now))
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
