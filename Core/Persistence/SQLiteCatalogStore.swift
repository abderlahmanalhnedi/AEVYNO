import AEVYNOSecurity
import CryptoKit
import Domain
import Foundation
import OSLog

/// Acquisition writes only invisible staging rows. The live writer transaction starts at commit.
/// One actor owns independent reader/writer handles; readers see only committed catalog snapshots.
public actor SQLiteCatalogStore: CatalogQueryRepository, CatalogImportRepository,
  CatalogRefreshMetadataRepository
{
  private let logger = Logger(subsystem: "com.aevyno", category: "catalog-persistence")
  private var writer: CatalogDatabase?
  private var reader: CatalogDatabase?
  private let cipher: CatalogReferenceCipher
  private var activeScopesByStagingID: [UUID: Set<CatalogScope>] = [:]

  public init(url: URL, encryptionKey: SymmetricKey) async throws {
    cipher = CatalogReferenceCipher(key: encryptionKey)
    guard url.isFileURL, encryptionKey.bitCount == 256 else { throw CatalogStoreError.invalidInput }
    try Task.checkCancellation()
    let database = try CatalogDatabase(url: url)
    try database.execute("PRAGMA foreign_keys = ON")
    try CatalogSchema.prepare(database)
    try database.execute("PRAGMA journal_mode = WAL")
    // Staging is disposable after a crash. The final live replacement switches to FULL.
    try database.execute("PRAGMA synchronous = NORMAL")
    try database.execute("PRAGMA cache_size = -4096")
    // Staging belongs to the importing process. A prior crash can leave only invisible rows.
    try database.execute("DELETE FROM staged_catalogs")
    // Initialize the WAL shared-memory files before opening the read-only connection.
    try database.execute("SELECT 1 FROM catalogs LIMIT 1")
    writer = database
    reader = try CatalogDatabase(url: url, readOnly: true)
    try reader?.execute("PRAGMA cache_size = -4096")
  }

  /// Rebuildable local cache. tvOS may purge Caches; callers must offer re-import on cache loss.
  public static func openDefault() async throws -> SQLiteCatalogStore {
    let key = try await CatalogKeyStore().key()
    do {
      let root = try FileManager.default.url(
        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      var directory = root.appendingPathComponent("AEVYNOCatalog", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      return try await SQLiteCatalogStore(
        url: directory.appendingPathComponent("catalog.sqlite"), encryptionKey: key)
    } catch is CancellationError { throw CancellationError() } catch let error as CatalogStoreError
    {
      throw error
    } catch { throw CatalogStoreError.unavailable }
  }

  public func beginStaging(in scope: CatalogScope) throws -> UUID {
    try beginStaging(in: [scope])
  }

  public func beginStaging(in scopes: [CatalogScope]) throws -> UUID {
    try Task.checkCancellation()
    let uniqueScopes = Set(scopes)
    guard !uniqueScopes.isEmpty, uniqueScopes.count == scopes.count else {
      throw CatalogStoreError.invalidInput
    }
    for scope in uniqueScopes {
      guard (scope.origin == .m3u) == (scope.kind == .unspecified) else {
        throw CatalogStoreError.invalidInput
      }
    }
    let sourceIDs = Set(uniqueScopes.map(\.sourceID))
    guard sourceIDs.count == 1 else { throw CatalogStoreError.invalidInput }
    guard
      activeScopesByStagingID.values.allSatisfy({ activeScopes in
        activeScopes.isDisjoint(with: uniqueScopes)
          && Set(activeScopes.map(\.sourceID)).isDisjoint(with: sourceIDs)
      })
    else { throw CatalogStoreError.busy }

    let database = try writeDatabase()
    let stagingID = UUID()
    do {
      try database.execute("BEGIN IMMEDIATE")
      for scope in uniqueScopes.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
        try database.execute(
          "INSERT INTO staged_catalogs VALUES(?,?,?,?)", [stagingID.databaseValue] + scope.values)
      }
      try database.execute("COMMIT")
    } catch {
      _ = rollbackAfterSQLFailure(database)
      throw error
    }
    activeScopesByStagingID[stagingID] = uniqueScopes
    return stagingID
  }

  public func stage(
    items: [CatalogItem], categories: [CatalogCategory], in stagingID: UUID
  ) throws {
    let scopes = try requireStaging(stagingID)
    let database = try writeDatabase()
    do {
      try Task.checkCancellation()
      guard items.count <= CatalogPage.maximumSize, categories.count <= CatalogPage.maximumSize
      else {
        throw CatalogStoreError.invalidInput
      }
      // Each bounded staging batch is its own short transaction. No network wait occurs inside it.
      try database.execute("BEGIN IMMEDIATE")
      let categoryStatement = try database.statement(
        """
        INSERT INTO staged_categories(staging_id,id,source,origin,kind,title,search_title)
        VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(staging_id,id) DO UPDATE SET title=excluded.title,
          search_title=excluded.search_title
        """)
      for category in categories {
        try Task.checkCancellation()
        guard scopes.contains(category.scope) else { throw CatalogStoreError.invalidInput }
        try validateText(category.id)
        try validateText(category.title)
        try categoryStatement.bind(
          [stagingID.databaseValue, category.id] + category.scope.values
            + [category.title, Self.searchTitle(category.title)])
        _ = try categoryStatement.step()
        try categoryStatement.requireChangedRows()
      }
      let itemStatement = try database.statement(
        """
        INSERT INTO staged_items(
          staging_id,id,source,origin,kind,title,search_title,category,sealed_references)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(staging_id,id) DO UPDATE SET title=excluded.title,
          search_title=excluded.search_title,
          category=excluded.category, sealed_references=excluded.sealed_references
        """)
      for item in items {
        try Task.checkCancellation()
        guard scopes.contains(item.scope) else { throw CatalogStoreError.invalidInput }
        try validate(item, scope: item.scope)
        try itemStatement.bind(
          [stagingID.databaseValue, item.id] + item.scope.values
            + [item.title, Self.searchTitle(item.title), item.categoryID, try cipher.seal(item)])
        _ = try itemStatement.step()
        try itemStatement.requireChangedRows()
      }
      try database.execute("COMMIT")
    } catch {
      if rollbackAfterSQLFailure(database) { discardAfterFailure(stagingID) }
      throw error
    }
  }

  public func commitStagedReplacement(_ stagingID: UUID) throws {
    _ = try performStagedReplacementCommit(stagingID, successfulRefresh: nil)
  }

  public func commitStagedReplacement(
    _ stagingID: UUID, successfulRefresh metadata: CatalogRefreshMetadata
  ) throws -> Int {
    try performStagedReplacementCommit(stagingID, successfulRefresh: metadata)
  }

  private func performStagedReplacementCommit(
    _ stagingID: UUID, successfulRefresh metadata: CatalogRefreshMetadata?
  ) throws -> Int {
    let scopes = try requireStaging(stagingID)
    if let metadata {
      guard Set(scopes.map(\.sourceID)) == Set([metadata.sourceID]),
        metadata.lastResult == .success, metadata.lastSuccessfulAt != nil,
        metadata.lastCommittedItemCount >= 0
      else { throw CatalogStoreError.invalidInput }
    }
    let database = try writeDatabase()
    do {
      try Task.checkCancellation()
      // This is the only live-catalog transaction. Acquisition and validation are complete.
      try database.execute("PRAGMA synchronous = FULL")
      try database.execute("BEGIN IMMEDIATE")
      let committedItemCount = try database.scalar(
        "SELECT COUNT(*) FROM staged_items WHERE staging_id=?", [stagingID.databaseValue])
      for scope in scopes.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
        try database.execute(
          "DELETE FROM catalogs WHERE source=? AND origin=? AND kind=?", scope.values)
        try database.execute("INSERT INTO catalogs VALUES(?,?,?)", scope.values)
      }
      try copyStagedCategories(stagingID, database: database)
      try copyStagedItems(stagingID, database: database)
      if let metadata {
        try writeSuccessfulRefreshMetadata(
          CatalogRefreshMetadata(
            sourceID: metadata.sourceID,
            lastAttemptedAt: metadata.lastAttemptedAt,
            lastSuccessfulAt: metadata.lastSuccessfulAt,
            lastCommittedItemCount: committedItemCount,
            lastResult: metadata.lastResult
          ),
          database: database
        )
      }
      try database.execute(
        "DELETE FROM staged_catalogs WHERE staging_id=?", [stagingID.databaseValue])
      try database.execute("COMMIT")
      activeScopesByStagingID[stagingID] = nil
      restoreStagingSynchronousMode(database)
      return committedItemCount
    } catch {
      if rollbackAfterSQLFailure(database) {
        discardAfterFailure(stagingID)
        restoreStagingSynchronousMode(database)
      }
      throw error
    }
  }

  public func discardStaging(_ stagingID: UUID) {
    guard activeScopesByStagingID[stagingID] != nil else { return }
    discardAfterFailure(stagingID)
  }

  public func deleteCatalog(sourceID: SourceConfiguration.ID) throws {
    try Task.checkCancellation()
    guard
      activeScopesByStagingID.values.allSatisfy({ scopes in
        !scopes.contains(where: { $0.sourceID == sourceID })
      })
    else { throw CatalogStoreError.busy }
    try writeDatabase().execute("DELETE FROM catalogs WHERE source=?", [sourceID.databaseValue])
  }

  /// Explicit lifecycle release also discards an unfinished invisible staging set.
  public func close() {
    for stagingID in Array(activeScopesByStagingID.keys) { discardAfterFailure(stagingID) }
    reader = nil
    writer = nil
  }

  private func requireStaging(_ stagingID: UUID) throws -> Set<CatalogScope> {
    guard let scopes = activeScopesByStagingID[stagingID] else {
      throw CatalogStoreError.invalidTransaction
    }
    return scopes
  }

  private func discardAfterFailure(_ stagingID: UUID) {
    do {
      try writer?.executeIgnoringCancellation(
        "DELETE FROM staged_catalogs WHERE staging_id=?", [stagingID.databaseValue])
    } catch {
      logger.error("Catalog staging cleanup failed; closing the writer to prevent further changes.")
      writer = nil
    }
    activeScopesByStagingID[stagingID] = nil
  }

  private func rollbackAfterSQLFailure(_ database: CatalogDatabase) -> Bool {
    do {
      try database.rollback()
      return true
    } catch {
      logger.error("Catalog transaction rollback failed; closing the writer.")
      writer = nil
      activeScopesByStagingID.removeAll()
      return false
    }
  }

  public func recordRefreshAttempt(
    sourceID: SourceConfiguration.ID,
    attemptedAt: Date,
    result: CatalogRefreshResultCategory
  ) throws {
    guard result != .success, attemptedAt.timeIntervalSince1970.isFinite else {
      throw CatalogStoreError.invalidInput
    }
    let database = try writeDatabase()
    try database.executeIgnoringCancellation(
      """
      INSERT INTO refresh_metadata(
        source,last_attempt,last_success,committed_item_count,last_result)
      VALUES(?,?,NULL,0,?)
      ON CONFLICT(source) DO UPDATE SET
        last_attempt=excluded.last_attempt,last_result=excluded.last_result
      """,
      [sourceID.databaseValue, String(attemptedAt.timeIntervalSince1970), result.rawValue])
  }

  public func refreshMetadata(for sourceID: SourceConfiguration.ID) throws
    -> CatalogRefreshMetadata?
  {
    let row = try readDatabase().statement(
      """
      SELECT last_attempt,last_success,committed_item_count,last_result
      FROM refresh_metadata WHERE source=?
      """, [sourceID.databaseValue])
    guard try row.step() else { return nil }
    guard let resultValue = row.text(3),
      let result = CatalogRefreshResultCategory(rawValue: resultValue)
    else { throw CatalogStoreError.corruptedStore }
    let successInterval = row.isNull(1) ? nil : row.double(1)
    return CatalogRefreshMetadata(
      sourceID: sourceID,
      lastAttemptedAt: Date(timeIntervalSince1970: row.double(0)),
      lastSuccessfulAt: successInterval.map(Date.init(timeIntervalSince1970:)),
      lastCommittedItemCount: row.integer(2),
      lastResult: result)
  }

  private func writeSuccessfulRefreshMetadata(
    _ metadata: CatalogRefreshMetadata, database: CatalogDatabase
  ) throws {
    guard let successfulAt = metadata.lastSuccessfulAt else {
      throw CatalogStoreError.invalidInput
    }
    guard metadata.lastAttemptedAt.timeIntervalSince1970.isFinite,
      successfulAt.timeIntervalSince1970.isFinite
    else { throw CatalogStoreError.invalidInput }
    try database.execute(
      """
      INSERT INTO refresh_metadata(
        source,last_attempt,last_success,committed_item_count,last_result)
      VALUES(?,?,?,?,?)
      ON CONFLICT(source) DO UPDATE SET
        last_attempt=excluded.last_attempt,last_success=excluded.last_success,
        committed_item_count=excluded.committed_item_count,last_result=excluded.last_result
      """,
      [
        metadata.sourceID.databaseValue,
        String(metadata.lastAttemptedAt.timeIntervalSince1970),
        String(successfulAt.timeIntervalSince1970),
        String(metadata.lastCommittedItemCount),
        metadata.lastResult.rawValue,
      ])
  }

  private func restoreStagingSynchronousMode(_ database: CatalogDatabase) {
    do {
      try database.executeIgnoringCancellation("PRAGMA synchronous = NORMAL")
    } catch {
      // Keeping FULL is safe; it only makes later staging batches more expensive.
      logger.error("Catalog writer could not restore staging durability mode.")
    }
  }

  private func copyStagedCategories(_ stagingID: UUID, database: CatalogDatabase) throws {
    var lowerBound = 0
    while let page = try stagedPageBoundary(
      table: "staged_categories", stagingID: stagingID, after: lowerBound, database: database)
    {
      try Task.checkCancellation()
      let statement = try database.statement(
        """
        INSERT INTO categories(id,source,origin,kind,title,search_title)
        SELECT id,source,origin,kind,title,search_title FROM staged_categories
        WHERE staging_id=? AND sequence>? AND sequence<=? ORDER BY sequence
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, search_title=excluded.search_title
        WHERE categories.source=excluded.source AND categories.origin=excluded.origin
          AND categories.kind=excluded.kind
        """, [stagingID.databaseValue, String(lowerBound), String(page.upperBound)])
      _ = try statement.step()
      try statement.requireChangedRows(page.count)
      lowerBound = page.upperBound
    }
  }

  private func copyStagedItems(_ stagingID: UUID, database: CatalogDatabase) throws {
    var lowerBound = 0
    while let page = try stagedPageBoundary(
      table: "staged_items", stagingID: stagingID, after: lowerBound, database: database)
    {
      try Task.checkCancellation()
      let statement = try database.statement(
        """
        INSERT INTO items(id,source,origin,kind,title,search_title,category,sealed_references)
        SELECT id,source,origin,kind,title,search_title,category,sealed_references
        FROM staged_items WHERE staging_id=? AND sequence>? AND sequence<=? ORDER BY sequence
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, search_title=excluded.search_title,
          category=excluded.category, sealed_references=excluded.sealed_references
        WHERE items.source=excluded.source AND items.origin=excluded.origin
          AND items.kind=excluded.kind
        """, [stagingID.databaseValue, String(lowerBound), String(page.upperBound)])
      _ = try statement.step()
      try statement.requireChangedRows(page.count)
      lowerBound = page.upperBound
    }
  }

  private func stagedPageBoundary(
    table: String, stagingID: UUID, after lowerBound: Int, database: CatalogDatabase
  ) throws -> (upperBound: Int, count: Int)? {
    // `table` is supplied only by the two fixed internal callers above.
    let statement = try database.statement(
      """
      SELECT sequence FROM \(table) WHERE staging_id=? AND sequence>? ORDER BY sequence
      LIMIT \(CatalogPage.maximumSize)
      """, [stagingID.databaseValue, String(lowerBound)])
    var upperBound: Int?
    var count = 0
    while try statement.step() {
      upperBound = statement.integer(0)
      count += 1
    }
    return upperBound.map { ($0, count) }
  }

  private func writeDatabase() throws -> CatalogDatabase {
    guard let writer else { throw CatalogStoreError.unavailable }
    return writer
  }

  func readDatabase() throws -> CatalogDatabase {
    try Task.checkCancellation()
    guard let reader else { throw CatalogStoreError.unavailable }
    return reader
  }

  func decodeItem(_ row: CatalogStatement) throws -> CatalogItem {
    guard let id = row.text(0), let title = row.text(4), let sealed = row.text(6) else {
      throw CatalogStoreError.corruptedStore
    }
    let references = try cipher.open(sealed, id: id)
    return CatalogItem(
      id: id, scope: try decodeScope(row), title: title, categoryID: row.text(5),
      artworkURL: try decodeURL(references.artwork), mediaURL: try decodeURL(references.media),
      providerReference: references.provider)
  }

  func decodeScope(_ row: CatalogStatement) throws -> CatalogScope {
    guard let source = row.text(1).flatMap(UUID.init(uuidString:)),
      let origin = row.text(2).flatMap(CatalogOrigin.init(rawValue:)),
      let kind = row.text(3).flatMap(CatalogMediaKind.init(rawValue:))
    else { throw CatalogStoreError.corruptedStore }
    return CatalogScope(sourceID: .init(rawValue: source), origin: origin, kind: kind)
  }

  private func decodeURL(_ value: String?) throws -> URL? {
    guard let value else { return nil }
    guard let url = URL(string: value), isMediaURL(url) else {
      throw CatalogStoreError.corruptedStore
    }
    return url
  }

  private func validate(_ item: CatalogItem, scope: CatalogScope) throws {
    guard item.scope == scope else { throw CatalogStoreError.invalidInput }
    try validateText(item.id)
    try validateText(item.title)
    if let category = item.categoryID { try validateText(category) }
    if let artwork = item.artworkURL, !isMediaURL(artwork) { throw CatalogStoreError.invalidInput }
    switch scope.origin {
    case .m3u:
      guard let url = item.mediaURL, isMediaURL(url), item.providerReference == nil else {
        throw CatalogStoreError.invalidInput
      }
    case .xtream:
      guard item.mediaURL == nil, let reference = item.providerReference,
        CatalogMediaKind(reference.kind) == scope.kind
      else { throw CatalogStoreError.invalidInput }
      try validateText(reference.providerID)
    }
  }

  private func isMediaURL(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
      && url.absoluteString.utf8.count <= 65_536
  }

  private func validateText(_ text: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.utf8.count <= 16_384, !text.contains("\0")
    else { throw CatalogStoreError.invalidInput }
  }

  static func searchTitle(_ title: String) -> String {
    CatalogSearchNormalization.fold(title)
  }
}

extension CatalogScope {
  var values: [String?] { [sourceID.databaseValue, origin.rawValue, kind.rawValue] }
}

extension SourceConfiguration.ID {
  var databaseValue: String { rawValue.uuidString.lowercased() }
}

extension UUID {
  var databaseValue: String { uuidString.lowercased() }
}
