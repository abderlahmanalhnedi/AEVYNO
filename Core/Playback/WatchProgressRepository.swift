import Domain
import Foundation

public enum WatchProgressRepositoryError: Error, Equatable, Sendable {
  case unavailable
  case corruptedStore
  case unsupportedSchema
  case invalidProgress
  case writeFailed
}

public protocol WatchProgressRepository: Sendable {
  func progress(for mediaID: String) async throws -> WatchProgress?
  func save(_ progress: WatchProgress) async throws
  func remove(mediaID: String) async throws
}

/// Durable progress lives in Application Support, separately from the rebuildable catalog cache.
public actor FileWatchProgressRepository: WatchProgressRepository {
  public static let currentSchemaVersion = 1

  private struct Store: Codable {
    let schemaVersion: Int
    let records: [WatchProgress]
  }

  private struct Header: Decodable {
    let schemaVersion: Int
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private var loaded: [String: WatchProgress]?

  public init(url: URL, fileManager: FileManager = .default) {
    fileURL = url
    self.fileManager = fileManager
  }

  public static func openDefault() throws -> FileWatchProgressRepository {
    do {
      let applicationSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = applicationSupport.appendingPathComponent("AEVYNO", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return FileWatchProgressRepository(
        url: directory.appendingPathComponent("watch-progress.json"))
    } catch {
      throw WatchProgressRepositoryError.unavailable
    }
  }

  public func progress(for mediaID: String) throws -> WatchProgress? {
    guard isValidMediaID(mediaID) else { throw WatchProgressRepositoryError.invalidProgress }
    return try loadIfNeeded()[mediaID]
  }

  public func save(_ progress: WatchProgress) throws {
    try validate(progress)
    var records = try loadIfNeeded()
    records[progress.mediaID] = progress
    try persist(records)
  }

  public func remove(mediaID: String) throws {
    guard isValidMediaID(mediaID) else { throw WatchProgressRepositoryError.invalidProgress }
    var records = try loadIfNeeded()
    records.removeValue(forKey: mediaID)
    try persist(records)
  }

  private func loadIfNeeded() throws -> [String: WatchProgress] {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: fileURL.path) else {
      loaded = [:]
      return [:]
    }
    do {
      let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
      let header = try JSONDecoder().decode(Header.self, from: data)
      guard header.schemaVersion == Self.currentSchemaVersion else {
        throw WatchProgressRepositoryError.unsupportedSchema
      }
      let records = try JSONDecoder().decode(Store.self, from: data).records
      guard Set(records.map(\.mediaID)).count == records.count else {
        throw WatchProgressRepositoryError.corruptedStore
      }
      for record in records { try validate(record) }
      let indexed = Dictionary(uniqueKeysWithValues: records.map { ($0.mediaID, $0) })
      loaded = indexed
      return indexed
    } catch let error as WatchProgressRepositoryError {
      throw error
    } catch {
      throw WatchProgressRepositoryError.corruptedStore
    }
  }

  private func persist(_ records: [String: WatchProgress]) throws {
    do {
      let parent = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      let ordered = records.values.sorted { $0.mediaID < $1.mediaID }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(Store(schemaVersion: Self.currentSchemaVersion, records: ordered))
        .write(to: fileURL, options: [.atomic])
      loaded = records
    } catch {
      throw WatchProgressRepositoryError.writeFailed
    }
  }

  private func validate(_ progress: WatchProgress) throws {
    guard
      isValidMediaID(progress.mediaID),
      progress.position.isFinite,
      progress.position >= 0,
      progress.duration.isFinite,
      progress.duration > 0,
      progress.position <= progress.duration
    else {
      throw WatchProgressRepositoryError.invalidProgress
    }
  }

  private func isValidMediaID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 4_096 && !value.contains("\0")
  }
}
