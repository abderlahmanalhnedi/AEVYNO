import CryptoKit
import Domain
import Foundation
import IPTVCore
import Library
import Testing

@testable import Persistence

struct CatalogFixture {
  let directory: URL
  let url: URL
  let key = SymmetricKey(size: .bits256)
  let sourceID = SourceConfiguration.ID(rawValue: UUID())

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    url = directory.appendingPathComponent("catalog.sqlite")
  }

  func remove() throws { try FileManager.default.removeItem(at: directory) }

  var scope: CatalogScope { CatalogScope(sourceID: sourceID, origin: .xtream, kind: .live) }

  func item(_ index: Int, scope: CatalogScope? = nil, title: String? = nil, category: String? = nil)
    -> CatalogItem
  {
    let scope = scope ?? self.scope
    let kind = ProviderMediaKind(rawValue: scope.kind.rawValue) ?? .live
    let reference = ProviderItemReference(kind: kind, providerID: String(index))
    return CatalogItem(
      id: ProviderCatalogItem.ID(sourceID: scope.sourceID, reference: reference).rawValue,
      scope: scope, title: title ?? String(format: "Synthetic %06d", index), categoryID: category,
      providerReference: reference)
  }

  func seed(_ store: SQLiteCatalogStore) async throws {
    let stagingID = try await store.beginStaging(in: scope)
    try await store.stage(items: [item(0, title: "Catalog A")], categories: [], in: stagingID)
    try await store.commitStagedReplacement(stagingID)
  }
}

struct CatalogPersistenceTests {
  @Test("Reopen preserves exact IDs, opaque encrypted references and M3U groups")
  func m3uReopenAndPrivacy() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let opaque =
      "https://example.invalid/synthetic-user/synthetic-secret/%2f?token=synthetic-token&x=1&x=2+3"
    let playlist =
      "#EXTM3U\n#EXTINF:-1 tvg-id=\"stable\" group-title=\"العربية HD\" tvg-logo=\"https://example.invalid/logo?token=synthetic-art\",Ö Test\n\(opaque)\n"
    let report = try await M3UImportService().importPlaylist(
      lines: M3UDataLineSequence(data: Data(playlist.utf8)), sourceID: fixture.sourceID,
      sink: PersistentCatalogImportSink(repository: store))
    #expect(report.importedCount == 1)
    let page = try CatalogPage(limit: 1)
    let first = try #require(try await store.items(matching: CatalogFilter(), page: page).first)
    #expect(first.mediaURL?.absoluteString == opaque)
    #expect(first.scope.kind == .unspecified)
    #expect(!String(reflecting: first).contains("synthetic-token"))
    let groups = try await store.categories(
      matching: CatalogFilter(sourceID: fixture.sourceID), page: page)
    #expect(groups.first?.title == "العربية HD")
    #expect(first.categoryID == groups.first?.id)
    await store.close()
    let data = try Data(contentsOf: fixture.url)
    for secret in [
      "synthetic-user", "synthetic-secret", "synthetic-token", "synthetic-art", opaque,
    ] {
      #expect(data.range(of: Data(secret.utf8)) == nil)
    }
    let reopened = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    #expect(try await reopened.item(id: first.id) == first)
    await reopened.close()
  }

  @Test("Committed reader stays on A until B atomically commits; source and kind are isolated")
  func atomicVisibilityAndDeletion() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let otherScope = CatalogScope(sourceID: .init(rawValue: UUID()), origin: .xtream, kind: .live)
    let vodScope = CatalogScope(sourceID: fixture.sourceID, origin: .xtream, kind: .vod)
    for scope in [otherScope, vodScope] {
      let stagingID = try await store.beginStaging(in: scope)
      try await store.stage(
        items: [fixture.item(0, scope: scope)], categories: [], in: stagingID)
      try await store.commitStagedReplacement(stagingID)
    }
    let attemptedAt = Date(timeIntervalSince1970: 1_000)
    try await store.recordRefreshAttempt(
      sourceID: fixture.sourceID,
      attemptedAt: attemptedAt,
      result: .inProgress
    )
    try await store.recordRefreshAttempt(
      sourceID: otherScope.sourceID,
      attemptedAt: attemptedAt,
      result: .inProgress
    )
    let stagingID = try await store.beginStaging(in: fixture.scope)
    try await store.stage(items: [fixture.item(1)], categories: [], in: stagingID)
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    #expect(try await store.item(id: fixture.item(1).id) == nil)
    let independentStagingID = try await store.beginStaging(in: otherScope)
    await #expect(throws: CatalogStoreError.busy) {
      try await store.beginStaging(in: fixture.scope)
    }
    await store.discardStaging(independentStagingID)
    await store.discardStaging(UUID())
    try await store.commitStagedReplacement(stagingID)
    #expect(try await store.item(id: fixture.item(0).id) == nil)
    #expect(try await store.itemCount(matching: CatalogFilter()) == 3)
    #expect(try await store.sourceCatalogCount(sourceID: fixture.sourceID) == 2)
    try await store.deleteCatalog(sourceID: fixture.sourceID)
    #expect(try await store.itemCount(matching: CatalogFilter()) == 1)
    #expect(try await store.item(id: fixture.item(0, scope: otherScope).id) != nil)
    #expect(try await store.refreshMetadata(for: fixture.sourceID) == nil)
    #expect(try await store.refreshMetadata(for: otherScope.sourceID) != nil)
    await store.close()
  }

  @Test("Catalog and refresh metadata deletion rolls back as one transaction")
  func catalogDeletionRollback() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    try await store.recordRefreshAttempt(
      sourceID: fixture.sourceID,
      attemptedAt: Date(timeIntervalSince1970: 1_000),
      result: .inProgress
    )
    let database = try CatalogDatabase(url: fixture.url)
    try database.execute(
      "CREATE TRIGGER fail_refresh_metadata_delete BEFORE DELETE ON refresh_metadata "
        + "BEGIN SELECT RAISE(FAIL,'synthetic'); END"
    )

    await #expect(throws: CatalogStoreError.writeFailed) {
      try await store.deleteCatalog(sourceID: fixture.sourceID)
    }

    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    #expect(try await store.refreshMetadata(for: fixture.sourceID) != nil)
    await store.close()
  }

  @Test("SQLite staging and final-copy failures discard staging and preserve A")
  func databaseWriteFailures() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let database = try CatalogDatabase(url: fixture.url)
    try database.execute(
      "CREATE TRIGGER fail_write BEFORE INSERT ON items WHEN NEW.title='fail' BEGIN SELECT RAISE(FAIL,'synthetic'); END"
    )
    let stagingID = try await store.beginStaging(in: fixture.scope)
    try await store.stage(items: [fixture.item(1)], categories: [], in: stagingID)
    try await store.stage(
      items: [fixture.item(2, title: "fail")], categories: [], in: stagingID)
    await #expect(throws: CatalogStoreError.writeFailed) {
      try await store.commitStagedReplacement(stagingID)
    }
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    #expect(try await store.itemCount(matching: CatalogFilter()) == 1)
    let next = try await store.beginStaging(in: fixture.scope)
    await store.discardStaging(next)

    try database.execute(
      "CREATE TRIGGER fail_stage BEFORE INSERT ON staged_items WHEN NEW.title='stage-fail' BEGIN SELECT RAISE(FAIL,'synthetic'); END"
    )
    let failedStage = try await store.beginStaging(in: fixture.scope)
    try await store.stage(items: [fixture.item(3)], categories: [], in: failedStage)
    await #expect(throws: CatalogStoreError.writeFailed) {
      try await store.stage(
        items: [fixture.item(4, title: "stage-fail")], categories: [], in: failedStage)
    }
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    let afterStageFailure = try await store.beginStaging(in: fixture.scope)
    await store.discardStaging(afterStageFailure)
    await store.close()
  }

  @Test("Cancelled commit rolls back; close also abandons an unfinished refresh")
  func cancelledCommitAndAbandonedRefresh() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let stagingID = try await store.beginStaging(in: fixture.scope)
    try await store.stage(items: [fixture.item(1)], categories: [], in: stagingID)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await store.commitStagedReplacement(stagingID)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    let abandoned = try await store.beginStaging(in: fixture.scope)
    try await store.stage(items: [fixture.item(2)], categories: [], in: abandoned)
    await store.close()
    let reopened = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    #expect(try await reopened.item(id: fixture.item(0).id)?.title == "Catalog A")
    #expect(try await reopened.itemCount(matching: CatalogFilter()) == 1)
    await reopened.close()
  }

  @Test("Duplicate IDs are last-write-wins; unresolved categories fail commit without replacing A")
  func duplicatesAndCategoryFailure() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let stagingID = try await store.beginStaging(in: fixture.scope)
    let category = CatalogCategory(
      id: "synthetic-category", scope: fixture.scope, title: "Category")
    try await store.stage(
      items: [fixture.item(0, category: category.id)], categories: [category], in: stagingID)
    try await store.stage(
      items: [fixture.item(0, title: "Last", category: category.id)], categories: [],
      in: stagingID)
    try await store.commitStagedReplacement(stagingID)
    #expect(try await store.itemCount(matching: CatalogFilter()) == 1)
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Last")
    let invalid = try await store.beginStaging(in: fixture.scope)
    try await store.stage(
      items: [fixture.item(1, category: "missing")], categories: [], in: invalid)
    await #expect(throws: CatalogStoreError.writeFailed) {
      try await store.commitStagedReplacement(invalid)
    }
    #expect(try await store.categories(matching: CatalogFilter(), page: CatalogPage()).count == 1)
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Last")
    let empty = try await store.beginStaging(in: fixture.scope)
    try await store.commitStagedReplacement(empty)
    #expect(try await store.itemCount(matching: CatalogFilter()) == 0)
    #expect(try await store.categories(matching: CatalogFilter(), page: CatalogPage()).isEmpty)
    #expect(try await store.sourceCatalogCount(sourceID: fixture.sourceID) == 1)
    await store.close()
  }

  @Test("Invalid scope and oversized batches fail safely; page limits are explicit")
  func invalidInput() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let stagingID = try await store.beginStaging(in: fixture.scope)
    await #expect(throws: CatalogStoreError.invalidInput) {
      try await store.stage(
        items: (0...256).map { fixture.item($0) }, categories: [], in: stagingID)
    }
    #expect(try await store.item(id: fixture.item(0).id)?.title == "Catalog A")
    for limit in [-1, 0, 257, Int.max] {
      #expect(throws: CatalogStoreError.invalidPage) { try CatalogPage(limit: limit) }
    }
    #expect(throws: CatalogStoreError.invalidPage) { try CatalogPage(offset: -1) }
    let invalid = try await store.beginStaging(in: fixture.scope)
    await #expect(throws: CatalogStoreError.invalidInput) {
      try await store.stage(
        items: [fixture.item(1, title: "\0")], categories: [], in: invalid)
    }
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await store.items(matching: CatalogFilter(), page: CatalogPage())
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    await store.close()
  }

  @Test("Sort ties are stable across refresh and Arabic display titles remain unchanged")
  func deterministicOrderingAndIndexes() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    let items = [
      fixture.item(2, title: "Ö Title"), fixture.item(1, title: "o title"),
      fixture.item(3, title: "العربية HD 2026"),
    ]
    var expected: [CatalogItem] = []
    for values in [items, Array(items.reversed())] {
      let stagingID = try await store.beginStaging(in: fixture.scope)
      try await store.stage(items: values, categories: [], in: stagingID)
      try await store.commitStagedReplacement(stagingID)
      let page = try await store.items(matching: CatalogFilter(), page: CatalogPage())
      if expected.isEmpty { expected = page } else { #expect(page == expected) }
      #expect(page[0].id == min(items[0].id, items[1].id))
      #expect(page.last?.title == "العربية HD 2026")
    }
    let database = try CatalogDatabase(url: fixture.url, readOnly: true)
    let row = try database.statement(
      "EXPLAIN QUERY PLAN SELECT id FROM items WHERE source=? AND kind=? ORDER BY search_title,id LIMIT 64",
      [fixture.sourceID.databaseValue, "live"])
    var plans: [String] = []
    while try row.step() { plans.append(row.text(3) ?? "") }
    #expect(plans.contains { $0.contains("items_source_kind") })
    #expect(!plans.contains { $0.contains("TEMP B-TREE") })

    let stagingID = try await store.beginStaging(in: fixture.scope)
    try await store.stage(items: items, categories: [], in: stagingID)
    let stagingPlan = try database.statement(
      "EXPLAIN QUERY PLAN SELECT sequence FROM staged_items WHERE staging_id=? AND sequence>? ORDER BY sequence LIMIT 256",
      [stagingID.databaseValue, "0"])
    var stagingPlans: [String] = []
    while try stagingPlan.step() { stagingPlans.append(stagingPlan.text(3) ?? "") }
    #expect(stagingPlans.contains { $0.contains("staged_items_order") })
    #expect(!stagingPlans.contains { $0.contains("TEMP B-TREE") })
    await store.discardStaging(stagingID)
    await store.close()
  }

  @Test("A cross-source ID collision rejects replacement and leaves both sources intact")
  func identityCollision() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    let scope = CatalogScope(sourceID: .init(rawValue: UUID()), origin: .xtream, kind: .live)
    let stagingID = try await store.beginStaging(in: scope)
    let collision = CatalogItem(
      id: fixture.item(0).id, scope: scope, title: "Collision",
      providerReference: ProviderItemReference(kind: .live, providerID: "0"))
    try await store.stage(items: [collision], categories: [], in: stagingID)
    await #expect(throws: CatalogStoreError.invalidInput) {
      try await store.commitStagedReplacement(stagingID)
    }
    #expect(try await store.item(id: collision.id)?.title == "Catalog A")
    #expect(try await store.sourceCatalogCount(sourceID: scope.sourceID) == 0)
    await store.close()
  }

  @Test("Unknown schema, invalid database and wrong encryption keys fail without destructive reset")
  func schemaAndCorruption() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    await store.close()
    let wrongKey = try await SQLiteCatalogStore(
      url: fixture.url, encryptionKey: SymmetricKey(size: .bits256))
    await #expect(throws: CatalogStoreError.corruptedStore) {
      try await wrongKey.item(id: fixture.item(0).id)
    }
    await wrongKey.close()
    let database = try CatalogDatabase(url: fixture.url)
    try database.execute("PRAGMA user_version = 99")
    await #expect(throws: CatalogStoreError.unsupportedSchema) {
      try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    }
    #expect(try database.scalar("SELECT count(*) FROM items") == 1)
    let corruptURL = fixture.directory.appendingPathComponent("invalid.sqlite")
    try Data("synthetic invalid database".utf8).write(to: corruptURL)
    await #expect(throws: CatalogStoreError.corruptedStore) {
      try await SQLiteCatalogStore(url: corruptURL, encryptionKey: fixture.key)
    }
  }

  @Test("Version 1 catalogs migrate to version 3 staging and metadata without data loss")
  func version1Migration() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    await store.close()

    let version1 = try CatalogDatabase(url: fixture.url)
    try version1.execute("DROP TABLE staged_items")
    try version1.execute("DROP TABLE staged_categories")
    try version1.execute("DROP TABLE staged_catalogs")
    try version1.execute("PRAGMA user_version = 1")

    let migrated = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    #expect(try await migrated.item(id: fixture.item(0).id)?.title == "Catalog A")
    let inspection = try CatalogDatabase(url: fixture.url, readOnly: true)
    #expect(try inspection.scalar("PRAGMA user_version") == 3)
    #expect(
      try inspection.scalar(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='staged_catalogs'") == 1)
    #expect(
      try inspection.scalar(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='refresh_metadata'") == 1)
    await migrated.close()
  }

  @Test("Version 2 staging migrates to multi-partition schema without losing committed items")
  func version2Migration() async throws {
    let fixture = try CatalogFixture()
    defer { try? fixture.remove() }
    let store = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    try await fixture.seed(store)
    await store.close()

    let version2 = try CatalogDatabase(url: fixture.url)
    try version2.execute("DROP TABLE staged_items")
    try version2.execute("DROP TABLE staged_categories")
    try version2.execute("DROP TABLE staged_catalogs")
    try version2.execute("DROP TABLE refresh_metadata")
    try version2.execute(
      """
      CREATE TABLE staged_catalogs (
        staging_id TEXT PRIMARY KEY, source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
        UNIQUE(staging_id, source, origin, kind))
      """)
    try version2.execute(
      """
      CREATE TABLE staged_categories (
        sequence INTEGER PRIMARY KEY, staging_id TEXT NOT NULL, id TEXT NOT NULL,
        source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
        title TEXT NOT NULL CHECK(length(title)>0), search_title TEXT NOT NULL,
        UNIQUE(staging_id, id),
        FOREIGN KEY(staging_id, source, origin, kind)
          REFERENCES staged_catalogs(staging_id, source, origin, kind) ON DELETE CASCADE)
      """)
    try version2.execute(
      """
      CREATE TABLE staged_items (
        sequence INTEGER PRIMARY KEY, staging_id TEXT NOT NULL, id TEXT NOT NULL,
        source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
        title TEXT NOT NULL CHECK(length(title)>0), search_title TEXT NOT NULL,
        category TEXT, sealed_references TEXT NOT NULL, UNIQUE(staging_id, id),
        FOREIGN KEY(staging_id, source, origin, kind)
          REFERENCES staged_catalogs(staging_id, source, origin, kind) ON DELETE CASCADE)
      """)
    try version2.execute("PRAGMA user_version = 2")

    let migrated = try await SQLiteCatalogStore(url: fixture.url, encryptionKey: fixture.key)
    #expect(try await migrated.item(id: fixture.item(0).id)?.title == "Catalog A")
    let scopes = [
      CatalogScope(sourceID: fixture.sourceID, origin: .xtream, kind: .live),
      CatalogScope(sourceID: fixture.sourceID, origin: .xtream, kind: .vod),
    ]
    let stagingID = try await migrated.beginStaging(in: scopes)
    await migrated.discardStaging(stagingID)
    #expect(try version2.scalar("PRAGMA user_version") == 3)
    await migrated.close()
  }
}
