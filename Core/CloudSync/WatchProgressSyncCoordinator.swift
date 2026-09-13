import Domain
import Foundation
import Playback

public actor WatchProgressSyncCoordinator {
  private static let maximumOutboundBatch = 100

  private let localRepository: any WatchProgressRepository
  private let cloudStore: any CloudWatchProgressStore
  private let stateStore: any WatchProgressSyncStateStore
  private let retryPolicy: WatchProgressRetryPolicy
  private let sleeper: any WatchProgressSyncSleeper
  private let operationIDGenerator: any WatchProgressOperationIDGenerator
  private let automaticallySynchronizes: Bool

  private var operationGeneration: UInt64 = 0
  private var scheduledTask: Task<Void, Never>?

  public private(set) var status: WatchProgressSyncStatus = .idle

  public init(
    localRepository: any WatchProgressRepository,
    cloudStore: any CloudWatchProgressStore,
    stateStore: any WatchProgressSyncStateStore,
    retryPolicy: WatchProgressRetryPolicy = WatchProgressRetryPolicy(),
    sleeper: any WatchProgressSyncSleeper = SystemWatchProgressSyncSleeper(),
    operationIDGenerator: any WatchProgressOperationIDGenerator =
      UUIDWatchProgressOperationIDGenerator(),
    automaticallySynchronizes: Bool = true
  ) {
    self.localRepository = localRepository
    self.cloudStore = cloudStore
    self.stateStore = stateStore
    self.retryPolicy = retryPolicy
    self.sleeper = sleeper
    self.operationIDGenerator = operationIDGenerator
    self.automaticallySynchronizes = automaticallySynchronizes
  }

  public func enqueue(_ progress: WatchProgress) async throws {
    try await enqueue(progress, isStartOver: false)
  }

  public func enqueueStartOver(_ progress: WatchProgress) async throws {
    try await enqueue(progress, isStartOver: true)
  }

  public func synchronize() async {
    scheduledTask?.cancel()
    scheduledTask = nil
    let generation = nextOperationGeneration()
    await performSynchronization(generation: generation)
  }

  public func scheduleSynchronization() {
    beginScheduledSynchronization()
  }

  public func cancelSynchronization() {
    _ = nextOperationGeneration()
    scheduledTask?.cancel()
    scheduledTask = nil
    status = .idle
  }

  private func enqueue(_ progress: WatchProgress, isStartOver: Bool) async throws {
    var snapshot = try await stateStore.load()
    var entries = snapshot.indexedEntries()
    let existing = entries[progress.mediaID]
    let operationID = await operationIDGenerator.next()
    let generation: UInt64
    if isStartOver {
      generation = increment(existing?.record.resetGeneration ?? 0)
    } else {
      generation = existing?.record.resetGeneration ?? 0
    }
    let revision = increment(existing?.record.logicalRevision ?? 0)
    let record = CloudWatchProgressRecord(
      progress: progress,
      resetGeneration: generation,
      logicalRevision: revision,
      operationID: operationID
    )
    try WatchProgressConflictResolver.validate(record)
    entries[progress.mediaID] = WatchProgressSyncEntry(
      record: record,
      pendingUpload: true,
      pendingReset: isStartOver || existing?.pendingReset == true
    )
    snapshot = makeSnapshot(changeToken: snapshot.changeToken, entries: entries)
    try await stateStore.save(snapshot)
    if automaticallySynchronizes { beginScheduledSynchronization() }
  }

  private func beginScheduledSynchronization() {
    scheduledTask?.cancel()
    let generation = nextOperationGeneration()
    scheduledTask = Task { [weak self] in
      await self?.performSynchronization(generation: generation)
    }
  }

  private func performSynchronization(generation: UInt64) async {
    guard isCurrent(generation) else { return }
    status = .syncing

    for attempt in 1...retryPolicy.maximumAttempts {
      do {
        try Task.checkCancellation()
        try await synchronizeOnce(generation: generation)
        guard isCurrent(generation) else { return }
        status = .upToDate
        if scheduledTask != nil { scheduledTask = nil }
        return
      } catch is CancellationError {
        guard isCurrent(generation) else { return }
        status = .idle
        return
      } catch is WatchProgressSyncStateStoreError {
        guard isCurrent(generation) else { return }
        status = .failed(.localMetadata)
        return
      } catch let error as CloudWatchProgressValidationError {
        guard isCurrent(generation) else { return }
        status = error == .unsupportedSchema ? .failed(.schema) : .failed(.cloudService)
        return
      } catch let error as CloudProgressStoreError {
        guard isCurrent(generation) else { return }
        if case .accountUnavailable(let availability) = error,
          availability == .noAccount || availability == .restricted
        {
          status = .unavailable(availability)
          return
        }
        guard error.isRetryable, attempt < retryPolicy.maximumAttempts else {
          status = terminalStatus(for: error)
          return
        }
        let delay = retryPolicy.delay(
          afterFailedAttempt: attempt,
          serverHint: error.retryAfter
        )
        status = .waitingForRetry(attempt: attempt, delay: delay)
        do {
          try await sleeper.sleep(for: delay)
        } catch {
          guard isCurrent(generation) else { return }
          status = .idle
          return
        }
        guard isCurrent(generation) else { return }
        status = .syncing
      } catch {
        guard isCurrent(generation) else { return }
        status = .failed(.cloudService)
        return
      }
    }
  }

  private func synchronizeOnce(generation: UInt64) async throws {
    switch await cloudStore.accountAvailability() {
    case .available:
      break
    case let availability:
      throw CloudProgressStoreError.accountUnavailable(availability)
    }
    try ensureCurrent(generation)

    var snapshot = try await stateStore.load()
    var entries = snapshot.indexedEntries()
    for progress in try await localRepository.allProgress() where entries[progress.mediaID] == nil {
      try ensureCurrent(generation)
      let record = CloudWatchProgressRecord(
        progress: progress,
        resetGeneration: 0,
        logicalRevision: 1,
        operationID: await operationIDGenerator.next()
      )
      entries[progress.mediaID] = WatchProgressSyncEntry(
        record: record,
        pendingUpload: true,
        pendingReset: false
      )
    }

    let batch = try await cloudStore.fetchChanges(since: snapshot.changeToken)
    try ensureCurrent(generation)
    let remoteRecords = try coalescedRemoteRecords(batch.records)

    for remote in remoteRecords.values.sorted(by: { $0.mediaID < $1.mediaID }) {
      try ensureCurrent(generation)
      let localProgress = try await localRepository.progress(for: remote.mediaID)
      var localEntry = entries[remote.mediaID]

      if localEntry == nil, let localProgress {
        localEntry = WatchProgressSyncEntry(
          record: CloudWatchProgressRecord(
            progress: localProgress,
            resetGeneration: 0,
            logicalRevision: 1,
            operationID: await operationIDGenerator.next()
          ),
          pendingUpload: true,
          pendingReset: false
        )
      }

      guard var localEntry else {
        try await localRepository.save(remote.progress)
        entries[remote.mediaID] = WatchProgressSyncEntry(
          record: remote,
          pendingUpload: false,
          pendingReset: false
        )
        continue
      }

      if localEntry.pendingReset,
        localEntry.record.resetGeneration <= remote.resetGeneration
      {
        localEntry = WatchProgressSyncEntry(
          record: localEntry.record.replacing(
            resetGeneration: increment(remote.resetGeneration),
            logicalRevision: increment(
              max(localEntry.record.logicalRevision, remote.logicalRevision)
            ),
            operationID: await operationIDGenerator.next()
          ),
          pendingUpload: true,
          pendingReset: true
        )
      }

      let resolved = try WatchProgressConflictResolver.resolve(localEntry.record, remote)
      let shouldUpload = localEntry.pendingReset || resolved != remote
      if localProgress != resolved.progress {
        try ensureCurrent(generation)
        try await localRepository.save(resolved.progress)
      }
      entries[remote.mediaID] = WatchProgressSyncEntry(
        record: resolved,
        pendingUpload: shouldUpload,
        pendingReset: localEntry.pendingReset
      )
    }

    try ensureCurrent(generation)
    let pending = entries.values
      .filter(\.pendingUpload)
      .map(\.record)
      .sorted { $0.mediaID < $1.mediaID }
    if !pending.isEmpty {
      for start in stride(from: 0, to: pending.count, by: Self.maximumOutboundBatch) {
        let end = min(start + Self.maximumOutboundBatch, pending.count)
        let outboundBatch = Array(pending[start..<end])
        let saved = try await cloudStore.save(outboundBatch)
        try ensureCurrent(generation)
        let savedByID = try coalescedRemoteRecords(saved)
        guard Set(savedByID.keys) == Set(outboundBatch.map(\.mediaID)) else {
          throw CloudProgressStoreError.invalidData
        }
        for record in savedByID.values {
          let localProgress = try await localRepository.progress(for: record.mediaID)
          if localProgress != record.progress {
            try ensureCurrent(generation)
            try await localRepository.save(record.progress)
          }
          entries[record.mediaID] = WatchProgressSyncEntry(
            record: record,
            pendingUpload: false,
            pendingReset: false
          )
        }
      }
    }

    snapshot = makeSnapshot(changeToken: batch.changeToken, entries: entries)
    try await stateStore.save(snapshot)
  }

  private func coalescedRemoteRecords(
    _ records: [CloudWatchProgressRecord]
  ) throws -> [String: CloudWatchProgressRecord] {
    var result: [String: CloudWatchProgressRecord] = [:]
    for record in records {
      try WatchProgressConflictResolver.validate(record)
      if let existing = result[record.mediaID] {
        result[record.mediaID] = try WatchProgressConflictResolver.resolve(existing, record)
      } else {
        result[record.mediaID] = record
      }
    }
    return result
  }

  private func makeSnapshot(
    changeToken: Data?,
    entries: [String: WatchProgressSyncEntry]
  ) -> WatchProgressSyncSnapshot {
    WatchProgressSyncSnapshot(
      changeToken: changeToken,
      entries: entries.values.sorted { $0.record.mediaID < $1.record.mediaID }
    )
  }

  private func terminalStatus(for error: CloudProgressStoreError) -> WatchProgressSyncStatus {
    switch error {
    case .accountUnavailable(let availability): .unavailable(availability)
    case .quotaExceeded: .failed(.quota)
    case .unsupportedSchema: .failed(.schema)
    case .configuration: .failed(.configuration)
    case .networkUnavailable, .serviceUnavailable, .rateLimited, .serverConflict, .invalidData,
      .unknown:
      .failed(.cloudService)
    }
  }

  private func nextOperationGeneration() -> UInt64 {
    operationGeneration = increment(operationGeneration)
    return operationGeneration
  }

  private func isCurrent(_ generation: UInt64) -> Bool {
    operationGeneration == generation && !Task.isCancelled
  }

  private func ensureCurrent(_ generation: UInt64) throws {
    guard isCurrent(generation) else { throw CancellationError() }
  }

  private func increment(_ value: UInt64) -> UInt64 {
    let maximum = UInt64(Int64.max)
    return value >= maximum ? maximum : value + 1
  }
}

public struct LocalFirstCloudWatchProgressRepository: WatchProgressRepository {
  private let localRepository: any WatchProgressRepository
  private let coordinator: WatchProgressSyncCoordinator

  public init(
    localRepository: any WatchProgressRepository,
    coordinator: WatchProgressSyncCoordinator
  ) {
    self.localRepository = localRepository
    self.coordinator = coordinator
  }

  public func progress(for mediaID: String) async throws -> WatchProgress? {
    try await localRepository.progress(for: mediaID)
  }

  public func allProgress() async throws -> [WatchProgress] {
    try await localRepository.allProgress()
  }

  public func save(_ progress: WatchProgress) async throws {
    try await localRepository.save(progress)
    try? await coordinator.enqueue(progress)
  }

  public func remove(mediaID: String) async throws {
    try await localRepository.remove(mediaID: mediaID)
  }

  @discardableResult
  public func startOver(mediaID: String, at date: Date) async throws -> WatchProgress? {
    guard let reset = try await localRepository.startOver(mediaID: mediaID, at: date) else {
      return nil
    }
    try? await coordinator.enqueueStartOver(reset)
    return reset
  }
}
