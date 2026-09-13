import Domain
import Foundation

public struct CloudFavoriteChangeBatch: Equatable, Sendable {
  public let records: [CloudFavoriteRecord]
  public let changeToken: Data?
  public init(records: [CloudFavoriteRecord], changeToken: Data?) {
    self.records = records
    self.changeToken = changeToken
  }
}

public protocol CloudFavoriteStore: Sendable {
  func accountAvailability() async -> CloudAccountAvailability
  func fetchChanges(since changeToken: Data?) async throws -> CloudFavoriteChangeBatch
  func save(_ records: [CloudFavoriteRecord]) async throws -> [CloudFavoriteRecord]
}

public enum FavoriteSyncStatus: Equatable, Sendable {
  case idle, syncing, upToDate
  case unavailable(CloudAccountAvailability)
  case waitingForRetry(attempt: Int, delay: TimeInterval)
  case failed
}

public struct FavoriteSyncEntry: Codable, Equatable, Sendable {
  public let record: CloudFavoriteRecord
  public let pendingUpload: Bool
  public init(record: CloudFavoriteRecord, pendingUpload: Bool) {
    self.record = record
    self.pendingUpload = pendingUpload
  }
}
public struct FavoriteSyncSnapshot: Codable, Equatable, Sendable {
  public static let schemaVersion = 1
  public let schemaVersion: Int
  public let changeToken: Data?
  public let entries: [FavoriteSyncEntry]
  public init(
    schemaVersion: Int = Self.schemaVersion, changeToken: Data? = nil,
    entries: [FavoriteSyncEntry] = []
  ) {
    self.schemaVersion = schemaVersion
    self.changeToken = changeToken
    self.entries = entries
  }
}
public protocol FavoriteSyncStateStore: Sendable {
  func load() async throws -> FavoriteSyncSnapshot
  func save(_ snapshot: FavoriteSyncSnapshot) async throws
}

public actor FileFavoriteSyncStateStore: FavoriteSyncStateStore {
  private let url: URL
  private let fileManager: FileManager
  public init(url: URL, fileManager: FileManager = .default) {
    self.url = url
    self.fileManager = fileManager
  }
  public static func openDefault() throws -> FileFavoriteSyncStateStore {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("AEVYNO", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return FileFavoriteSyncStateStore(url: root.appendingPathComponent("favorite-sync.json"))
  }
  public func load() throws -> FavoriteSyncSnapshot {
    guard fileManager.fileExists(atPath: url.path) else { return FavoriteSyncSnapshot() }
    do {
      let value = try JSONDecoder().decode(FavoriteSyncSnapshot.self, from: Data(contentsOf: url))
      try validate(value)
      return value
    } catch { throw WatchProgressSyncStateStoreError.corruptedStore }
  }
  public func save(_ snapshot: FavoriteSyncSnapshot) throws {
    do {
      try validate(snapshot)
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(snapshot).write(to: url, options: .atomic)
    } catch { throw WatchProgressSyncStateStoreError.writeFailed }
  }
  private func validate(_ value: FavoriteSyncSnapshot) throws {
    guard value.schemaVersion == FavoriteSyncSnapshot.schemaVersion,
      Set(value.entries.map { $0.record.mediaID }).count == value.entries.count
    else { throw WatchProgressSyncStateStoreError.corruptedStore }
    for entry in value.entries {
      try FavoriteConflictResolver.validate(entry.record)
    }
  }
}

public actor FavoriteSyncCoordinator {
  private let local: any FavoriteRepository
  private let cloud: any CloudFavoriteStore
  private let state: any FavoriteSyncStateStore
  private let retry: WatchProgressRetryPolicy
  private let sleeper: any WatchProgressSyncSleeper
  private let ids: any WatchProgressOperationIDGenerator
  private var generation: UInt64 = 0
  public private(set) var status: FavoriteSyncStatus = .idle
  public init(
    localRepository: any FavoriteRepository, cloudStore: any CloudFavoriteStore,
    stateStore: any FavoriteSyncStateStore, retryPolicy: WatchProgressRetryPolicy = .init(),
    sleeper: any WatchProgressSyncSleeper = SystemWatchProgressSyncSleeper(),
    operationIDGenerator: any WatchProgressOperationIDGenerator =
      UUIDWatchProgressOperationIDGenerator()
  ) {
    local = localRepository
    cloud = cloudStore
    state = stateStore
    retry = retryPolicy
    self.sleeper = sleeper
    ids = operationIDGenerator
  }
  public func enqueue(mediaID: String, removed: Bool, at date: Date) async throws {
    let loaded = try await state.load()
    var values = Dictionary(uniqueKeysWithValues: loaded.entries.map { ($0.record.mediaID, $0) })
    let old = values[mediaID]?.record
    let record = CloudFavoriteRecord(
      mediaID: mediaID, isRemoved: removed, updatedAt: date,
      logicalRevision: min(UInt64(Int64.max), (old?.logicalRevision ?? 0) + 1),
      operationID: await ids.next())
    values[mediaID] = FavoriteSyncEntry(record: record, pendingUpload: true)
    try await state.save(makeSnapshot(values, loaded.changeToken))
  }
  public func synchronize() async {
    generation &+= 1
    let current = generation
    status = .syncing
    for attempt in 1...retry.maximumAttempts {
      do {
        try await once(current)
        guard generation == current else { return }
        status = .upToDate
        return
      } catch let error as CloudProgressStoreError {
        guard generation == current else { return }
        if case .accountUnavailable(let a) = error, a == .noAccount || a == .restricted {
          status = .unavailable(a)
          return
        }
        guard error.isRetryable, attempt < retry.maximumAttempts else {
          status = .failed
          return
        }
        let delay = retry.delay(afterFailedAttempt: attempt, serverHint: error.retryAfter)
        status = .waitingForRetry(attempt: attempt, delay: delay)
        try? await sleeper.sleep(for: delay)
        guard generation == current else { return }
        status = .syncing
      } catch {
        guard generation == current else { return }
        status = .failed
        return
      }
    }
  }
  public func cancelSynchronization() {
    generation &+= 1
    status = .idle
  }
  private func once(_ current: UInt64) async throws {
    guard await cloud.accountAvailability() == .available else {
      throw CloudProgressStoreError.accountUnavailable(await cloud.accountAvailability())
    }
    var loaded = try await state.load()
    var values = Dictionary(uniqueKeysWithValues: loaded.entries.map { ($0.record.mediaID, $0) })
    for favorite in try await local.allFavorites() where values[favorite.mediaID] == nil {
      values[favorite.mediaID] = FavoriteSyncEntry(
        record: CloudFavoriteRecord(
          mediaID: favorite.mediaID, isRemoved: false, updatedAt: favorite.updatedAt,
          logicalRevision: 1, operationID: await ids.next()), pendingUpload: true)
    }
    let batch = try await cloud.fetchChanges(since: loaded.changeToken)
    guard generation == current else { return }
    for remote in batch.records {
      try FavoriteConflictResolver.validate(remote)
      let resolved =
        try values[remote.mediaID].map { try FavoriteConflictResolver.resolve($0.record, remote) }
        ?? remote
      if resolved.isRemoved {
        try await local.remove(mediaID: resolved.mediaID)
      } else if try await local.favorite(for: resolved.mediaID) == nil {
        try await local.add(Favorite(mediaID: resolved.mediaID, updatedAt: resolved.updatedAt))
      }
      values[remote.mediaID] = FavoriteSyncEntry(
        record: resolved, pendingUpload: resolved != remote)
    }
    let pending = values.values.filter(\.pendingUpload).map(\.record).sorted {
      $0.mediaID < $1.mediaID
    }
    if !pending.isEmpty {
      let saved = try await cloud.save(pending)
      for record in saved {
        values[record.mediaID] = FavoriteSyncEntry(record: record, pendingUpload: false)
        if record.isRemoved {
          try await local.remove(mediaID: record.mediaID)
        } else if try await local.favorite(for: record.mediaID) == nil {
          try await local.add(Favorite(mediaID: record.mediaID, updatedAt: record.updatedAt))
        }
      }
    }
    loaded = makeSnapshot(values, batch.changeToken)
    try await state.save(loaded)
  }
  private func makeSnapshot(_ values: [String: FavoriteSyncEntry], _ token: Data?)
    -> FavoriteSyncSnapshot
  {
    FavoriteSyncSnapshot(
      changeToken: token, entries: values.values.sorted { $0.record.mediaID < $1.record.mediaID })
  }
}

public struct LocalFirstCloudFavoriteRepository: FavoriteRepository {
  private let local: any FavoriteRepository
  private let coordinator: FavoriteSyncCoordinator
  public init(localRepository: any FavoriteRepository, coordinator: FavoriteSyncCoordinator) {
    local = localRepository
    self.coordinator = coordinator
  }
  public func favorite(for mediaID: String) async throws -> Favorite? {
    try await local.favorite(for: mediaID)
  }
  public func allFavorites() async throws -> [Favorite] { try await local.allFavorites() }
  public func add(_ favorite: Favorite) async throws {
    try await local.add(favorite)
    try? await coordinator.enqueue(
      mediaID: favorite.mediaID, removed: false, at: favorite.updatedAt)
  }
  public func remove(mediaID: String) async throws {
    try await local.remove(mediaID: mediaID)
    try? await coordinator.enqueue(mediaID: mediaID, removed: true, at: Date())
  }
}
