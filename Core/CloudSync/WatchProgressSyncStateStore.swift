import Foundation

public struct WatchProgressSyncEntry: Codable, Equatable, Sendable {
  public let record: CloudWatchProgressRecord
  public let pendingUpload: Bool
  public let pendingReset: Bool

  public init(
    record: CloudWatchProgressRecord,
    pendingUpload: Bool,
    pendingReset: Bool
  ) {
    self.record = record
    self.pendingUpload = pendingUpload
    self.pendingReset = pendingReset
  }
}

public struct WatchProgressSyncSnapshot: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let changeToken: Data?
  public let entries: [WatchProgressSyncEntry]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    changeToken: Data? = nil,
    entries: [WatchProgressSyncEntry] = []
  ) {
    self.schemaVersion = schemaVersion
    self.changeToken = changeToken
    self.entries = entries
  }

  func indexedEntries() -> [String: WatchProgressSyncEntry] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.record.mediaID, $0) })
  }
}

public enum WatchProgressSyncStateStoreError: Error, Equatable, Sendable {
  case unavailable
  case corruptedStore
  case unsupportedSchema
  case writeFailed
}

public protocol WatchProgressSyncStateStore: Sendable {
  func load() async throws -> WatchProgressSyncSnapshot
  func save(_ snapshot: WatchProgressSyncSnapshot) async throws
}

public actor FileWatchProgressSyncStateStore: WatchProgressSyncStateStore {
  private struct Header: Decodable {
    let schemaVersion: Int
  }

  private let fileURL: URL
  private let fileManager: FileManager

  public init(url: URL, fileManager: FileManager = .default) {
    fileURL = url
    self.fileManager = fileManager
  }

  public static func openDefault() throws -> FileWatchProgressSyncStateStore {
    do {
      let applicationSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = applicationSupport.appendingPathComponent("AEVYNO", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return FileWatchProgressSyncStateStore(
        url: directory.appendingPathComponent("watch-progress-sync.json"))
    } catch {
      throw WatchProgressSyncStateStoreError.unavailable
    }
  }

  public func load() throws -> WatchProgressSyncSnapshot {
    guard fileManager.fileExists(atPath: fileURL.path) else { return WatchProgressSyncSnapshot() }
    do {
      let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
      let decoder = JSONDecoder()
      let header = try decoder.decode(Header.self, from: data)
      guard header.schemaVersion == WatchProgressSyncSnapshot.currentSchemaVersion else {
        throw WatchProgressSyncStateStoreError.unsupportedSchema
      }
      let snapshot = try decoder.decode(WatchProgressSyncSnapshot.self, from: data)
      try validate(snapshot)
      return snapshot
    } catch let error as WatchProgressSyncStateStoreError {
      throw error
    } catch {
      throw WatchProgressSyncStateStoreError.corruptedStore
    }
  }

  public func save(_ snapshot: WatchProgressSyncSnapshot) throws {
    do {
      try validate(snapshot)
      let parent = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      let ordered = WatchProgressSyncSnapshot(
        changeToken: snapshot.changeToken,
        entries: snapshot.entries.sorted { $0.record.mediaID < $1.record.mediaID }
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(ordered).write(to: fileURL, options: [.atomic])
    } catch let error as WatchProgressSyncStateStoreError {
      throw error
    } catch {
      throw WatchProgressSyncStateStoreError.writeFailed
    }
  }

  private func validate(_ snapshot: WatchProgressSyncSnapshot) throws {
    guard snapshot.schemaVersion == WatchProgressSyncSnapshot.currentSchemaVersion else {
      throw WatchProgressSyncStateStoreError.unsupportedSchema
    }
    guard Set(snapshot.entries.map(\.record.mediaID)).count == snapshot.entries.count else {
      throw WatchProgressSyncStateStoreError.corruptedStore
    }
    do {
      for entry in snapshot.entries {
        try WatchProgressConflictResolver.validate(entry.record)
        guard !entry.pendingReset || entry.pendingUpload else {
          throw WatchProgressSyncStateStoreError.corruptedStore
        }
      }
    } catch let error as WatchProgressSyncStateStoreError {
      throw error
    } catch {
      throw WatchProgressSyncStateStoreError.corruptedStore
    }
  }
}
