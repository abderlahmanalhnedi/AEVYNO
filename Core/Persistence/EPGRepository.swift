import Domain
import Foundation

public enum EPGStoreError: Error, Equatable, Sendable {
  case invalidInput
  case invalidTransaction
  case busy
  case unavailable
  case writeFailed
}

public protocol EPGImportRepository: Sendable {
  func beginStaging(sourceID: SourceConfiguration.ID) async throws -> UUID
  func stage(_ programmes: [EPGProgramme], in stagingID: UUID) async throws
  func commitStagedReplacement(_ stagingID: UUID, at now: Date) async throws
  func discardStaging(_ stagingID: UUID) async
}

public protocol EPGQueryRepository: Sendable {
  func nowNext(
    sourceID: SourceConfiguration.ID, channelID: EPGChannelIdentity, at instant: Date
  ) async throws -> EPGNowNextPresentation
}

/// Rebuildable source-scoped XMLTV cache. Its separate database prevents EPG publishing from
/// migrating or blocking catalog writes while retaining the same SQLite actor ownership pattern.
public actor SQLiteEPGStore: EPGImportRepository, EPGQueryRepository {
  public static let schemaVersion = 1
  public static let batchLimit = 256
  public static let retainedPast: TimeInterval = 24 * 60 * 60
  public static let retainedFuture: TimeInterval = 14 * 24 * 60 * 60

  private var writer: CatalogDatabase?
  private var reader: CatalogDatabase?
  private var activeSources: [UUID: SourceConfiguration.ID] = [:]

  public init(url: URL) throws {
    guard url.isFileURL else { throw EPGStoreError.invalidInput }
    let database = try CatalogDatabase(url: url)
    try database.execute("PRAGMA foreign_keys = ON")
    try database.execute("PRAGMA journal_mode = WAL")
    try database.execute("PRAGMA synchronous = NORMAL")
    try database.execute("PRAGMA cache_size = -4096")
    try Self.prepare(database)
    // Staging is disposable. Clean both tables explicitly so correctness does not depend solely on
    // connection-local foreign-key configuration after an interrupted process.
    try database.execute("DELETE FROM epg_staging")
    try database.execute("DELETE FROM epg_staging_sessions")
    writer = database
    reader = try CatalogDatabase(url: url, readOnly: true)
    try reader?.execute("PRAGMA foreign_keys = ON")
  }

  public static func openDefault() throws -> SQLiteEPGStore {
    do {
      let root = try FileManager.default.url(
        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      var directory = root.appendingPathComponent("AEVYNOEPG", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      return try SQLiteEPGStore(url: directory.appendingPathComponent("epg.sqlite"))
    } catch { throw EPGStoreError.unavailable }
  }

  public func beginStaging(sourceID: SourceConfiguration.ID) throws -> UUID {
    guard !activeSources.values.contains(sourceID) else { throw EPGStoreError.busy }
    let stagingID = UUID()
    try writerDatabase().execute(
      "INSERT INTO epg_staging_sessions(staging_id,source) VALUES(?,?)",
      [stagingID.uuidString, sourceID.rawValue.uuidString])
    activeSources[stagingID] = sourceID
    return stagingID
  }

  public func stage(_ programmes: [EPGProgramme], in stagingID: UUID) throws {
    guard let source = activeSources[stagingID], !programmes.isEmpty,
      programmes.count <= Self.batchLimit
    else { throw EPGStoreError.invalidInput }
    let database = try writerDatabase()
    do {
      try database.execute("BEGIN IMMEDIATE")
      let statement = try database.statement(
        """
        INSERT OR REPLACE INTO epg_staging(staging_id,source,programme_id,channel,start,end,title,subtitle,description,category)
        VALUES(?,?,?,?,?,?,?,?,?,?)
        """)
      for programme in programmes {
        try Task.checkCancellation()
        try statement.bind([
          stagingID.uuidString, source.rawValue.uuidString, programme.id,
          programme.channelID.rawValue,
          String(programme.timeRange.start.timeIntervalSince1970),
          String(programme.timeRange.end.timeIntervalSince1970), programme.title,
          programme.subtitle,
          programme.description, programme.category,
        ])
        _ = try statement.step()
      }
      try database.execute("COMMIT")
    } catch {
      try? database.rollback()
      throw EPGStoreError.writeFailed
    }
  }

  public func commitStagedReplacement(_ stagingID: UUID, at now: Date = Date()) throws {
    guard let source = activeSources[stagingID] else { throw EPGStoreError.invalidTransaction }
    let database = try writerDatabase()
    do {
      try Task.checkCancellation()
      guard
        try database.scalar(
          "SELECT COUNT(*) FROM epg_staging WHERE staging_id=?", [stagingID.uuidString]) > 0
      else { throw EPGStoreError.invalidInput }
      let lower = now.addingTimeInterval(-Self.retainedPast).timeIntervalSince1970
      let upper = now.addingTimeInterval(Self.retainedFuture).timeIntervalSince1970
      try database.execute("PRAGMA synchronous = FULL")
      try database.execute("BEGIN IMMEDIATE")
      try database.execute(
        "DELETE FROM epg_programmes WHERE source=?", [source.rawValue.uuidString])
      try database.execute(
        """
        INSERT INTO epg_programmes(source,programme_id,channel,start,end,title,subtitle,description,category)
        SELECT source,programme_id,channel,start,end,title,subtitle,description,category FROM epg_staging
        WHERE staging_id=? AND CAST(end AS REAL)>=? AND CAST(start AS REAL)<=?
        """, [stagingID.uuidString, String(lower), String(upper)])
      try database.execute(
        "DELETE FROM epg_staging WHERE staging_id=?", [stagingID.uuidString])
      try database.execute(
        "DELETE FROM epg_staging_sessions WHERE staging_id=?", [stagingID.uuidString])
      try database.execute("COMMIT")
      try database.execute("PRAGMA synchronous = NORMAL")
      activeSources[stagingID] = nil
    } catch {
      try? database.rollback()
      try? database.executeIgnoringCancellation(
        "DELETE FROM epg_staging WHERE staging_id=?", [stagingID.uuidString])
      try? database.executeIgnoringCancellation(
        "DELETE FROM epg_staging_sessions WHERE staging_id=?", [stagingID.uuidString])
      activeSources[stagingID] = nil
      throw error is EPGStoreError ? error : EPGStoreError.writeFailed
    }
  }

  public func discardStaging(_ stagingID: UUID) {
    guard activeSources.removeValue(forKey: stagingID) != nil, let database = writer else { return }
    try? database.executeIgnoringCancellation(
      "DELETE FROM epg_staging WHERE staging_id=?", [stagingID.uuidString])
    try? database.executeIgnoringCancellation(
      "DELETE FROM epg_staging_sessions WHERE staging_id=?", [stagingID.uuidString])
  }

  public func nowNext(
    sourceID: SourceConfiguration.ID, channelID: EPGChannelIdentity, at instant: Date
  ) throws -> EPGNowNextPresentation {
    let database = try readerDatabase()
    let source = sourceID.rawValue.uuidString
    let time = String(instant.timeIntervalSince1970)
    let now = try firstProgramme(
      database,
      sql: """
        SELECT programme_id,channel,start,end,title,subtitle,description,category FROM epg_programmes
        WHERE source=? AND channel=? AND CAST(start AS REAL)<=? AND ?<CAST(end AS REAL)
        ORDER BY CAST(start AS REAL) DESC, programme_id ASC LIMIT 1
        """, values: [source, channelID.rawValue, time, time])
    let nextThreshold = now?.timeRange.end.timeIntervalSince1970 ?? instant.timeIntervalSince1970
    let next = try firstProgramme(
      database,
      sql: """
        SELECT programme_id,channel,start,end,title,subtitle,description,category FROM epg_programmes
        WHERE source=? AND channel=? AND CAST(start AS REAL)>=?
        ORDER BY CAST(start AS REAL) ASC, programme_id ASC LIMIT 1
        """, values: [source, channelID.rawValue, String(nextThreshold)])
    return EPGNowNextPresentation(now: now, next: next)
  }

  /// Internal deterministic verification hook; never exposed through the repository protocols.
  func stagedRowCountForTesting() throws -> Int {
    try writerDatabase().scalar("SELECT COUNT(*) FROM epg_staging")
  }

  private func firstProgramme(_ database: CatalogDatabase, sql: String, values: [String?]) throws
    -> EPGProgramme?
  {
    let row = try database.statement(sql, values)
    guard try row.step() else { return nil }
    guard let channelText = row.text(1), let channel = EPGChannelIdentity(rawValue: channelText),
      let startText = row.text(2), let start = TimeInterval(startText), let endText = row.text(3),
      let end = TimeInterval(endText),
      let range = EPGTimeRange(
        start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end)),
      let title = row.text(4),
      let programme = EPGProgramme(
        channelID: channel, timeRange: range, title: title, subtitle: row.text(5),
        description: row.text(6), category: row.text(7))
    else { throw EPGStoreError.writeFailed }
    return programme
  }

  private func writerDatabase() throws -> CatalogDatabase {
    try Task.checkCancellation()
    guard let writer else { throw EPGStoreError.unavailable }
    return writer
  }

  private func readerDatabase() throws -> CatalogDatabase {
    try Task.checkCancellation()
    guard let reader else { throw EPGStoreError.unavailable }
    return reader
  }

  private static func prepare(_ database: CatalogDatabase) throws {
    let version = try database.scalar("PRAGMA user_version")
    guard version == 0 || version == Self.schemaVersion else { throw EPGStoreError.unavailable }
    if version == 0 {
      try database.execute("BEGIN IMMEDIATE")
      do {
        try database.execute(
          "CREATE TABLE epg_programmes(source TEXT NOT NULL, programme_id TEXT NOT NULL, channel TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT, description TEXT, category TEXT, PRIMARY KEY(source,programme_id))"
        )
        try database.execute(
          "CREATE INDEX epg_now_next ON epg_programmes(source,channel,start,end)")
        try database.execute(
          "CREATE TABLE epg_staging_sessions(staging_id TEXT PRIMARY KEY, source TEXT NOT NULL)")
        try database.execute(
          "CREATE TABLE epg_staging(staging_id TEXT NOT NULL, source TEXT NOT NULL, programme_id TEXT NOT NULL, channel TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT, description TEXT, category TEXT, PRIMARY KEY(staging_id,programme_id), FOREIGN KEY(staging_id) REFERENCES epg_staging_sessions(staging_id) ON DELETE CASCADE)"
        )
        try database.execute("PRAGMA user_version=1")
        try database.execute("COMMIT")
      } catch {
        try? database.rollback()
        throw EPGStoreError.writeFailed
      }
    }
  }
}
