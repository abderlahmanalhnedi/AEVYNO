import CloudSync
import Domain
import Foundation
import Playback
import Testing

@Suite("Cloud watch progress continuity", .serialized)
struct CloudWatchProgressSyncTests {
  @Test("Conflict resolution prevents progress regression in either direction")
  func progressDoesNotRegress() throws {
    let twenty = cloudRecord(position: 1_200, operationID: "phone")
    let forty = cloudRecord(position: 2_400, operationID: "tv")

    #expect(try WatchProgressConflictResolver.resolve(twenty, forty) == forty)
    #expect(try WatchProgressConflictResolver.resolve(forty, twenty) == forty)
  }

  @Test("Completion is sticky within a playback generation")
  func completionWinsStaleIncomplete() throws {
    let completed = cloudRecord(
      position: 3_600,
      completed: true,
      revision: 4,
      operationID: "complete"
    )
    let stale = cloudRecord(
      position: 1_200,
      completed: false,
      revision: 99,
      operationID: "stale"
    )

    #expect(try WatchProgressConflictResolver.resolve(completed, stale) == completed)
  }

  @Test("Equivalent progress and material duration differences resolve deterministically")
  func equivalentAndDurationConflicts() throws {
    let olderClock = cloudRecord(
      position: 1_200,
      duration: 3_600,
      updatedAt: Date(timeIntervalSince1970: 9_000),
      revision: 7,
      operationID: "a"
    )
    let newerRevision = cloudRecord(
      position: 1_200,
      duration: 7_200,
      updatedAt: Date(timeIntervalSince1970: 1),
      revision: 8,
      operationID: "b"
    )

    #expect(try WatchProgressConflictResolver.resolve(olderClock, newerRevision) == newerRevision)
    #expect(try WatchProgressConflictResolver.resolve(newerRevision, olderClock) == newerRevision)

    let farther = cloudRecord(position: 2_400, duration: 7_200, operationID: "farther")
    #expect(try WatchProgressConflictResolver.resolve(newerRevision, farther) == farther)
  }

  @Test("Repeated delivery is idempotent")
  func duplicateDelivery() async throws {
    let remote = cloudRecord(position: 2_400, operationID: "same")
    let local = MemoryProgressRepository()
    let cloud = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [remote, remote], changeToken: Data("one".utf8)))]
    )
    let state = MemorySyncStateStore()
    let coordinator = coordinator(local: local, cloud: cloud, state: state)

    await coordinator.synchronize()

    #expect(await local.progress(for: "media") == remote.progress)
    #expect(await local.saveCount == 1)
    #expect(await cloud.savedRecords.isEmpty)
  }

  @Test("Local-first saves succeed offline and upload after reconnect")
  func offlineThenReconnect() async throws {
    let local = MemoryProgressRepository()
    let cloud = FakeCloudProgressStore(availability: .noAccount)
    let state = MemorySyncStateStore()
    let coordinator = coordinator(local: local, cloud: cloud, state: state)
    let repository = LocalFirstCloudWatchProgressRepository(
      localRepository: local,
      coordinator: coordinator
    )
    let progress = watchProgress(position: 900)

    try await repository.save(progress)
    await coordinator.synchronize()
    #expect(await local.progress(for: "media") == progress)
    #expect(await coordinator.status == .unavailable(.noAccount))
    #expect(await cloud.savedRecords.isEmpty)

    await cloud.setAvailability(.available)
    await cloud.setFetchResults([
      .success(.init(records: [], changeToken: Data("reconnected".utf8)))
    ])
    await coordinator.synchronize()

    #expect(await cloud.savedRecords == [progress])
    #expect(await coordinator.status == .upToDate)
  }

  @Test("Remote and local progress converge without regression")
  func bidirectionalConvergence() async throws {
    let localTwenty = MemoryProgressRepository(records: ["media": watchProgress(position: 1_200)])
    let remoteForty = cloudRecord(position: 2_400, operationID: "remote-forty")
    let cloudDown = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [remoteForty], changeToken: nil))]
    )
    let coordinatorDown = coordinator(
      local: localTwenty,
      cloud: cloudDown,
      state: MemorySyncStateStore()
    )
    await coordinatorDown.synchronize()
    #expect(await localTwenty.progress(for: "media")?.position == 2_400)
    #expect(await cloudDown.savedRecords.isEmpty)

    let localForty = MemoryProgressRepository(records: ["media": watchProgress(position: 2_400)])
    let remoteTwenty = cloudRecord(position: 1_200, operationID: "remote-twenty")
    let cloudUp = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [remoteTwenty], changeToken: nil))]
    )
    let coordinatorUp = coordinator(
      local: localForty,
      cloud: cloudUp,
      state: MemorySyncStateStore()
    )
    await coordinatorUp.synchronize()
    #expect(await cloudUp.savedRecords.map(\.position) == [2_400])
    #expect(await localForty.progress(for: "media")?.position == 2_400)
  }

  @Test("Explicit Start Over rebases above a prior completion")
  func startOverSupersedesCompletion() async throws {
    let completed = watchProgress(position: 3_600, completed: true)
    let local = MemoryProgressRepository(records: ["media": completed])
    let prior = cloudRecord(
      position: 3_600,
      completed: true,
      resetGeneration: 10,
      revision: 20,
      operationID: "prior-completion"
    )
    let state = MemorySyncStateStore(
      snapshot: WatchProgressSyncSnapshot(entries: [
        WatchProgressSyncEntry(record: prior, pendingUpload: false, pendingReset: false)
      ])
    )
    let cloud = FakeCloudProgressStore(
      fetchResults: [
        .success(.init(records: [prior], changeToken: nil)),
        .success(.init(records: [prior], changeToken: nil)),
      ],
      saveResults: [.failure(.serverConflict)]
    )
    let ids = SequenceOperationIDGenerator(ids: ["reset", "rebased-reset"])
    let sleeper = RecordingSleeper()
    let coordinator = WatchProgressSyncCoordinator(
      localRepository: local,
      cloudStore: cloud,
      stateStore: state,
      sleeper: sleeper,
      operationIDGenerator: ids,
      automaticallySynchronizes: false
    )
    let repository = LocalFirstCloudWatchProgressRepository(
      localRepository: local,
      coordinator: coordinator
    )

    let reset = try await repository.startOver(
      mediaID: "media",
      at: Date(timeIntervalSince1970: 2_000)
    )
    #expect(reset?.position == 0)
    #expect(reset?.isCompleted == false)
    await coordinator.synchronize()

    let uploaded = try #require(await cloud.savedCloudRecords.last)
    #expect(uploaded.resetGeneration == 11)
    #expect(uploaded.position == 0)
    #expect(!uploaded.isCompleted)
    #expect(await local.progress(for: "media")?.isCompleted == false)
    #expect(await cloud.saveCount == 2)
    #expect(await sleeper.delays == [1])
  }

  @Test("Cloud and account failures never erase local progress")
  func failuresPreserveLocal() async throws {
    let progress = watchProgress(position: 1_800)
    let local = MemoryProgressRepository(records: ["media": progress])
    let cloud = FakeCloudProgressStore(
      fetchResults: [.failure(.networkUnavailable)]
    )
    let coordinator = WatchProgressSyncCoordinator(
      localRepository: local,
      cloudStore: cloud,
      stateStore: MemorySyncStateStore(),
      retryPolicy: WatchProgressRetryPolicy(maximumAttempts: 1),
      automaticallySynchronizes: false
    )
    await coordinator.synchronize()
    #expect(await local.progress(for: "media") == progress)
    #expect(await coordinator.status == .failed(.cloudService))

    await cloud.setAvailability(.restricted)
    await coordinator.synchronize()
    #expect(await local.progress(for: "media") == progress)
    #expect(await coordinator.status == .unavailable(.restricted))
  }

  @Test("The coordinator persists the semantic record committed during a save race")
  func saveRaceConvergesLocally() async throws {
    let local = MemoryProgressRepository(records: ["media": watchProgress(position: 1_200)])
    let completed = cloudRecord(
      position: 3_600,
      completed: true,
      revision: 10,
      operationID: "server-race-winner"
    )
    let cloud = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [], changeToken: nil))],
      saveResults: [.success([completed])]
    )
    let coordinator = coordinator(
      local: local,
      cloud: cloud,
      state: MemorySyncStateStore()
    )

    await coordinator.synchronize()

    #expect(await local.progress(for: "media") == completed.progress)
    #expect(await coordinator.status == .upToDate)
  }

  @Test("Server-record-changed retries refetch and converge on the committed completion")
  func serverConflictRefetchesAndConverges() async throws {
    let local = MemoryProgressRepository(records: ["media": watchProgress(position: 1_200)])
    let completed = cloudRecord(
      position: 3_600,
      completed: true,
      revision: 12,
      operationID: "remote-after-conflict"
    )
    let cloud = FakeCloudProgressStore(
      fetchResults: [
        .success(.init(records: [], changeToken: nil)),
        .success(.init(records: [completed], changeToken: Data("after-conflict".utf8))),
      ],
      saveResults: [.failure(.serverConflict)]
    )
    let sleeper = RecordingSleeper()
    let coordinator = WatchProgressSyncCoordinator(
      localRepository: local,
      cloudStore: cloud,
      stateStore: MemorySyncStateStore(),
      retryPolicy: WatchProgressRetryPolicy(maximumAttempts: 3, initialDelay: 1),
      sleeper: sleeper,
      operationIDGenerator: SequenceOperationIDGenerator(ids: ["local-one", "local-two"]),
      automaticallySynchronizes: false
    )

    await coordinator.synchronize()

    #expect(await cloud.fetchCount == 2)
    #expect(await cloud.saveCount == 1)
    #expect(await sleeper.delays == [1])
    #expect(await local.progress(for: "media") == completed.progress)
    #expect(await coordinator.status == .upToDate)
  }

  @Test("Repeated server-record-changed conflicts stop at the retry bound")
  func serverConflictRetryIsBounded() async {
    let cloud = FakeCloudProgressStore(
      fetchResults: [
        .success(.init(records: [], changeToken: nil)),
        .success(.init(records: [], changeToken: nil)),
        .success(.init(records: [], changeToken: nil)),
      ],
      saveResults: [
        .failure(.serverConflict),
        .failure(.serverConflict),
        .failure(.serverConflict),
      ]
    )
    let sleeper = RecordingSleeper()
    let coordinator = WatchProgressSyncCoordinator(
      localRepository: MemoryProgressRepository(records: ["media": watchProgress(position: 600)]),
      cloudStore: cloud,
      stateStore: MemorySyncStateStore(),
      retryPolicy: WatchProgressRetryPolicy(maximumAttempts: 3, initialDelay: 1),
      sleeper: sleeper,
      automaticallySynchronizes: false
    )

    await coordinator.synchronize()

    #expect(await cloud.fetchCount == 3)
    #expect(await cloud.saveCount == 3)
    #expect(await sleeper.delays == [1, 2])
    #expect(await coordinator.status == .failed(.cloudService))
  }

  @Test("Retry count and delays are bounded and deterministic")
  func retryPolicyIsBounded() async {
    let cloud = FakeCloudProgressStore(fetchResults: [
      .failure(.serviceUnavailable(retryAfter: nil)),
      .failure(.rateLimited(retryAfter: 3)),
      .failure(.networkUnavailable),
    ])
    let sleeper = RecordingSleeper()
    let coordinator = WatchProgressSyncCoordinator(
      localRepository: MemoryProgressRepository(),
      cloudStore: cloud,
      stateStore: MemorySyncStateStore(),
      retryPolicy: WatchProgressRetryPolicy(
        maximumAttempts: 3,
        initialDelay: 2,
        multiplier: 2,
        maximumDelay: 5
      ),
      sleeper: sleeper,
      automaticallySynchronizes: false
    )

    await coordinator.synchronize()

    #expect(await cloud.fetchCount == 3)
    #expect(await sleeper.delays == [2, 4])
    #expect(await coordinator.status == .failed(.cloudService))
  }

  @Test("Cancellation does not publish a stale remote result")
  func cancellationRejectsStaleResult() async throws {
    let original = watchProgress(position: 600)
    let local = MemoryProgressRepository(records: ["media": original])
    let cloud = FakeCloudProgressStore(suspendFirstFetch: true)
    let coordinator = coordinator(
      local: local,
      cloud: cloud,
      state: MemorySyncStateStore()
    )

    let task = Task { await coordinator.synchronize() }
    try await waitForFetch(cloud)
    await coordinator.cancelSynchronization()
    await cloud.resumeSuspendedFetch(
      with: .success(
        .init(
          records: [cloudRecord(position: 3_600, completed: true, operationID: "late")],
          changeToken: nil
        ))
    )
    await task.value

    #expect(await local.progress(for: "media") == original)
    #expect(await coordinator.status == .idle)
  }

  @Test("A newer sync generation ignores an older completion")
  func newerGenerationRejectsOlderCompletion() async throws {
    let local = MemoryProgressRepository(records: ["media": watchProgress(position: 600)])
    let newer = cloudRecord(position: 2_400, operationID: "newer-sync")
    let cloud = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [newer], changeToken: Data("new".utf8)))],
      suspendFirstFetch: true
    )
    let coordinator = coordinator(
      local: local,
      cloud: cloud,
      state: MemorySyncStateStore()
    )

    let olderTask = Task { await coordinator.synchronize() }
    try await waitForFetch(cloud)
    await coordinator.synchronize()
    await cloud.resumeSuspendedFetch(
      with: .success(
        .init(
          records: [cloudRecord(position: 3_600, completed: true, operationID: "old-result")],
          changeToken: Data("old".utf8)
        ))
    )
    await olderTask.value

    #expect(await local.progress(for: "media")?.position == 2_400)
    #expect(await local.progress(for: "media")?.isCompleted == false)
  }

  @Test("Cloud records contain only approved progress fields")
  func recordPrivacy() throws {
    let record = cloudRecord(position: 900, operationID: "privacy")
    let data = try JSONEncoder().encode(record)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(!text.contains("https://"))
    #expect(!text.lowercased().contains("password"))
    #expect(!text.lowercased().contains("token"))
    #expect(!text.contains("providerReference"))
    #expect(!text.contains("CredentialReference"))
    #expect(record.mediaID == "media")
  }

  @Test("Unsupported cloud schema fails safely")
  func unsupportedSchema() async throws {
    let original = watchProgress(position: 600)
    let future = CloudWatchProgressRecord(
      schemaVersion: 99,
      mediaID: "media",
      position: 1_200,
      duration: 3_600,
      updatedAt: Date(timeIntervalSince1970: 1_000),
      isCompleted: false,
      resetGeneration: 0,
      logicalRevision: 1,
      operationID: "future"
    )
    let local = MemoryProgressRepository(records: ["media": original])
    let cloud = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [future], changeToken: nil))]
    )
    let coordinator = coordinator(
      local: local,
      cloud: cloud,
      state: MemorySyncStateStore()
    )

    await coordinator.synchronize()

    #expect(await coordinator.status == .failed(.schema))
    #expect(await local.progress(for: "media") == original)
  }

  @Test("Change token and metadata survive coordinator restart")
  func tokenSurvivesRestart() async {
    let token = Data("opaque-token".utf8)
    let local = MemoryProgressRepository()
    let state = MemorySyncStateStore()
    let firstCloud = FakeCloudProgressStore(
      fetchResults: [
        .success(
          .init(
            records: [cloudRecord(position: 1_200, operationID: "first")],
            changeToken: token
          ))
      ]
    )
    await coordinator(local: local, cloud: firstCloud, state: state).synchronize()

    let secondCloud = FakeCloudProgressStore(
      fetchResults: [.success(.init(records: [], changeToken: token))]
    )
    await coordinator(local: local, cloud: secondCloud, state: state).synchronize()

    #expect(await secondCloud.requestedTokens == [token])
  }

  @Test("File sync state reopens and rejects corrupt or future schemas")
  func fileStatePersistence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AEVYNO-CloudSync-\(UUID().uuidString)",
      isDirectory: true
    )
    let url = directory.appendingPathComponent("sync.json")
    let record = cloudRecord(position: 1_200, operationID: "persisted")
    let snapshot = WatchProgressSyncSnapshot(
      changeToken: Data("token".utf8),
      entries: [
        WatchProgressSyncEntry(
          record: record,
          pendingUpload: true,
          pendingReset: false
        )
      ]
    )

    try await FileWatchProgressSyncStateStore(url: url).save(snapshot)
    #expect(try await FileWatchProgressSyncStateStore(url: url).load() == snapshot)

    try Data("not-json".utf8).write(to: url, options: .atomic)
    await #expect(throws: WatchProgressSyncStateStoreError.corruptedStore) {
      try await FileWatchProgressSyncStateStore(url: url).load()
    }

    let future = Data("{\"schemaVersion\":99,\"entries\":[]}".utf8)
    try future.write(to: url, options: .atomic)
    await #expect(throws: WatchProgressSyncStateStoreError.unsupportedSchema) {
      try await FileWatchProgressSyncStateStore(url: url).load()
    }
  }

  @Test("Corrupt sync metadata fails without destroying WatchProgress")
  func corruptMetadataIsNonDestructive() async throws {
    let progress = watchProgress(position: 1_200)
    let local = MemoryProgressRepository(records: ["media": progress])
    let state = FailingSyncStateStore(error: .corruptedStore)
    let coordinator = WatchProgressSyncCoordinator(
      localRepository: local,
      cloudStore: FakeCloudProgressStore(),
      stateStore: state,
      automaticallySynchronizes: false
    )

    await coordinator.synchronize()

    #expect(await coordinator.status == .failed(.localMetadata))
    #expect(await local.progress(for: "media") == progress)
  }
}

private actor MemoryProgressRepository: WatchProgressRepository {
  private var records: [String: WatchProgress]
  private(set) var saveCount = 0

  init(records: [String: WatchProgress] = [:]) { self.records = records }

  func progress(for mediaID: String) -> WatchProgress? { records[mediaID] }
  func allProgress() -> [WatchProgress] { records.values.sorted { $0.mediaID < $1.mediaID } }
  func save(_ progress: WatchProgress) {
    saveCount += 1
    records[progress.mediaID] = progress
  }
  func remove(mediaID: String) { records.removeValue(forKey: mediaID) }
}

private actor MemorySyncStateStore: WatchProgressSyncStateStore {
  private var snapshot: WatchProgressSyncSnapshot

  init(snapshot: WatchProgressSyncSnapshot = WatchProgressSyncSnapshot()) {
    self.snapshot = snapshot
  }

  func load() -> WatchProgressSyncSnapshot { snapshot }
  func save(_ snapshot: WatchProgressSyncSnapshot) { self.snapshot = snapshot }
}

private actor FailingSyncStateStore: WatchProgressSyncStateStore {
  let error: WatchProgressSyncStateStoreError
  init(error: WatchProgressSyncStateStoreError) { self.error = error }
  func load() throws -> WatchProgressSyncSnapshot { throw error }
  func save(_: WatchProgressSyncSnapshot) throws { throw error }
}

private actor FakeCloudProgressStore: CloudWatchProgressStore {
  private var availability: CloudAccountAvailability
  private var fetchResults: [Result<CloudWatchProgressChangeBatch, CloudProgressStoreError>]
  private var saveResults: [Result<[CloudWatchProgressRecord], CloudProgressStoreError>]
  private var suspendFirstFetch: Bool
  private var suspendedFetch: CheckedContinuation<CloudWatchProgressChangeBatch, any Error>?

  private(set) var fetchCount = 0
  private(set) var saveCount = 0
  private(set) var requestedTokens: [Data?] = []
  private(set) var savedCloudRecords: [CloudWatchProgressRecord] = []

  init(
    availability: CloudAccountAvailability = .available,
    fetchResults: [Result<CloudWatchProgressChangeBatch, CloudProgressStoreError>] = [],
    saveResults: [Result<[CloudWatchProgressRecord], CloudProgressStoreError>] = [],
    suspendFirstFetch: Bool = false
  ) {
    self.availability = availability
    self.fetchResults = fetchResults
    self.saveResults = saveResults
    self.suspendFirstFetch = suspendFirstFetch
  }

  var savedRecords: [WatchProgress] { savedCloudRecords.map(\.progress) }

  func accountAvailability() -> CloudAccountAvailability { availability }

  func fetchChanges(since changeToken: Data?) async throws -> CloudWatchProgressChangeBatch {
    fetchCount += 1
    requestedTokens.append(changeToken)
    if suspendFirstFetch {
      suspendFirstFetch = false
      return try await withCheckedThrowingContinuation { continuation in
        suspendedFetch = continuation
      }
    }
    guard !fetchResults.isEmpty else {
      return CloudWatchProgressChangeBatch(records: [], changeToken: changeToken)
    }
    return try fetchResults.removeFirst().get()
  }

  func save(_ records: [CloudWatchProgressRecord]) throws -> [CloudWatchProgressRecord] {
    saveCount += 1
    savedCloudRecords.append(contentsOf: records)
    if !saveResults.isEmpty { return try saveResults.removeFirst().get() }
    return records
  }

  func setAvailability(_ availability: CloudAccountAvailability) {
    self.availability = availability
  }

  func setFetchResults(
    _ results: [Result<CloudWatchProgressChangeBatch, CloudProgressStoreError>]
  ) {
    fetchResults = results
  }

  func resumeSuspendedFetch(
    with result: Result<CloudWatchProgressChangeBatch, CloudProgressStoreError>
  ) {
    let continuation = suspendedFetch
    suspendedFetch = nil
    continuation?.resume(with: result.mapError { $0 as any Error })
  }
}

private actor RecordingSleeper: WatchProgressSyncSleeper {
  private(set) var delays: [TimeInterval] = []
  func sleep(for delay: TimeInterval) { delays.append(delay) }
}

private actor SequenceOperationIDGenerator: WatchProgressOperationIDGenerator {
  private var ids: [String]
  init(ids: [String]) { self.ids = ids }
  func next() -> String { ids.isEmpty ? "fallback" : ids.removeFirst() }
}

private func coordinator(
  local: MemoryProgressRepository,
  cloud: FakeCloudProgressStore,
  state: MemorySyncStateStore
) -> WatchProgressSyncCoordinator {
  WatchProgressSyncCoordinator(
    localRepository: local,
    cloudStore: cloud,
    stateStore: state,
    operationIDGenerator: SequenceOperationIDGenerator(
      ids: (1...100).map { String(format: "operation-%03d", $0) }
    ),
    automaticallySynchronizes: false
  )
}

private func watchProgress(
  position: TimeInterval,
  duration: TimeInterval = 3_600,
  completed: Bool = false
) -> WatchProgress {
  WatchProgress(
    mediaID: "media",
    position: position,
    duration: duration,
    updatedAt: Date(timeIntervalSince1970: 1_000),
    isCompleted: completed
  )
}

private func cloudRecord(
  position: TimeInterval,
  duration: TimeInterval = 3_600,
  updatedAt: Date = Date(timeIntervalSince1970: 1_000),
  completed: Bool = false,
  resetGeneration: UInt64 = 0,
  revision: UInt64 = 1,
  operationID: String
) -> CloudWatchProgressRecord {
  CloudWatchProgressRecord(
    mediaID: "media",
    position: position,
    duration: duration,
    updatedAt: updatedAt,
    isCompleted: completed,
    resetGeneration: resetGeneration,
    logicalRevision: revision,
    operationID: operationID
  )
}

private func waitForFetch(_ cloud: FakeCloudProgressStore) async throws {
  for _ in 0..<200 {
    if await cloud.fetchCount > 0 { return }
    await Task.yield()
  }
  throw CloudProgressStoreError.unknown
}
