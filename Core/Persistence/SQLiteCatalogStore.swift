import AEVYNOSecurity
import CryptoKit
import Domain
import Foundation
import OSLog

/// One actor owns independent reader/writer handles. Reads see only committed WAL snapshots.
/// One replacement may run at a time; callers must commit/rollback every successful begin.
public actor SQLiteCatalogStore: CatalogQueryRepository, CatalogImportRepository {
  private let logger = Logger(subsystem: "com.aevyno", category: "catalog-persistence")
  private var writer: CatalogDatabase?
  private var reader: CatalogDatabase?
  private let cipher: CatalogReferenceCipher
  private var active: (token: UUID, scope: CatalogScope)?

  public init(url: URL, encryptionKey: SymmetricKey) async throws {
    cipher = CatalogReferenceCipher(key: encryptionKey)
    guard url.isFileURL, encryptionKey.bitCount == 256 else { throw CatalogStoreError.invalidInput }
    try Task.checkCancellation()
    let database = try CatalogDatabase(url: url)
    try database.execute("PRAGMA foreign_keys = ON")
    try CatalogSchema.prepare(database)
    try database.execute("PRAGMA journal_mode = WAL")
    try database.execute("PRAGMA synchronous = FULL")
    try database.execute("PRAGMA cache_size = -4096")
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

  public func beginReplacement(in scope: CatalogScope) throws -> UUID {
    try Task.checkCancellation()
    guard active == nil else { throw CatalogStoreError.busy }
    guard (scope.origin == .m3u) == (scope.kind == .unspecified) else {
      throw CatalogStoreError.invalidInput
    }
    let database = try writeDatabase()
    try database.execute("BEGIN IMMEDIATE")
    do {
      try database.execute(
        "DELETE FROM catalogs WHERE source=? AND origin=? AND kind=?", scope.values)
      try database.execute("INSERT INTO catalogs VALUES(?,?,?)", scope.values)
      let token = UUID()
      active = (token, scope)
      return token
    } catch {
      rollbackAfterFailure()
      throw error
    }
  }

  public func write(
    items: [CatalogItem], categories: [CatalogCategory], transaction: UUID
  ) throws {
    let scope = try requireTransaction(transaction)
    do {
      try Task.checkCancellation()
      guard items.count <= CatalogPage.maximumSize, categories.count <= CatalogPage.maximumSize
      else {
        throw CatalogStoreError.invalidInput
      }
      let database = try writeDatabase()
      let categoryStatement = try database.statement(
        """
        INSERT INTO categories VALUES(?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, search_title=excluded.search_title
        WHERE categories.source=excluded.source AND categories.origin=excluded.origin
          AND categories.kind=excluded.kind
        """)
      for category in categories {
        try Task.checkCancellation()
        guard category.scope == scope else { throw CatalogStoreError.invalidInput }
        try validateText(category.id)
        try validateText(category.title)
        try categoryStatement.bind(
          [category.id] + scope.values + [category.title, Self.searchTitle(category.title)])
        _ = try categoryStatement.step()
        try categoryStatement.requireChangedRow()
      }
      let itemStatement = try database.statement(
        """
        INSERT INTO items VALUES(?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, search_title=excluded.search_title,
          category=excluded.category, sealed_references=excluded.sealed_references
        WHERE items.source=excluded.source AND items.origin=excluded.origin AND items.kind=excluded.kind
        """)
      for item in items {
        try Task.checkCancellation()
        try validate(item, scope: scope)
        try itemStatement.bind(
          [item.id] + scope.values
            + [item.title, Self.searchTitle(item.title), item.categoryID, try cipher.seal(item)])
        _ = try itemStatement.step()
        try itemStatement.requireChangedRow()
      }
    } catch {
      rollbackAfterFailure()
      throw error
    }
  }

  public func commit(transaction: UUID) throws {
    _ = try requireTransaction(transaction)
    do {
      try Task.checkCancellation()
      try writeDatabase().execute("COMMIT")
      active = nil
    } catch {
      rollbackAfterFailure()
      throw error
    }
  }

  public func rollback(transaction: UUID) {
    guard active?.token == transaction else { return }
    rollbackAfterFailure()
  }

  public func deleteCatalog(sourceID: SourceConfiguration.ID) throws {
    try Task.checkCancellation()
    guard active == nil else { throw CatalogStoreError.busy }
    try writeDatabase().execute("DELETE FROM catalogs WHERE source=?", [sourceID.databaseValue])
  }

  /// Explicit lifecycle release also rolls back an unfinished refresh through SQLite close.
  public func close() {
    rollbackAfterFailure()
    reader = nil
    writer = nil
  }

  private func requireTransaction(_ token: UUID) throws -> CatalogScope {
    guard let active, active.token == token else { throw CatalogStoreError.invalidTransaction }
    return active.scope
  }

  private func rollbackAfterFailure() {
    do { try writer?.rollback() } catch {
      logger.error("Catalog rollback failed; closing the writer to prevent further changes.")
      // Closing a failed writer prevents reuse of uncertain transaction state; SQLite discards it.
      writer = nil
    }
    active = nil
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
    title.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .precomposedStringWithCanonicalMapping
  }
}

extension CatalogScope {
  var values: [String?] { [sourceID.databaseValue, origin.rawValue, kind.rawValue] }
}

extension SourceConfiguration.ID {
  var databaseValue: String { rawValue.uuidString.lowercased() }
}
