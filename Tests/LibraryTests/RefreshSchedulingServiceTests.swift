import Domain
import Foundation
import Library
import Persistence
import Testing

@Suite("Automatic refresh scheduling")
struct RefreshSchedulingServiceTests {
  private let now = Date(timeIntervalSince1970: 4_000_000)

  @Test("No eligible source performs no refresh call")
  func noEligibleSources() async throws {
    let manual = try makeSource(idByte: 1, policy: .manualOnly)
    let disabled = try makeSource(idByte: 2, policy: .automatic(.every6Hours), enabled: false)
    let context = SchedulingContext(sources: [manual, disabled], now: now)

    let report = try await context.scheduler.evaluateAndRefreshDueSources()

    #expect(await context.refresher.order.isEmpty)
    #expect(report.outcomes.count == 2)
    #expect(report.nextEligibleAt == nil)
  }

  @Test("Due sources run sequentially in oldest-eligible then stable-ID order")
  func deterministicSequentialOrdering() async throws {
    let tieFirst = try makeSource(idByte: 1, policy: .automatic(.every6Hours))
    let oldest = try makeSource(idByte: 2, policy: .automatic(.every6Hours))
    let tieSecond = try makeSource(idByte: 3, policy: .automatic(.every6Hours))
    let context = SchedulingContext(sources: [tieSecond, tieFirst, oldest], now: now)
    await context.store.setMetadata(successMetadata(for: tieFirst, hoursAgo: 10))
    await context.store.setMetadata(successMetadata(for: oldest, hoursAgo: 20))
    await context.store.setMetadata(successMetadata(for: tieSecond, hoursAgo: 10))

    _ = try await context.scheduler.evaluateAndRefreshDueSources()

    #expect(await context.refresher.order == [oldest.id, tieFirst.id, tieSecond.id])
    #expect(await context.refresher.maximumConcurrentCount == 1)
  }

  @Test("One source failure does not stop the next due source")
  func failureIsolation() async throws {
    let first = try makeSource(idByte: 1, policy: .automatic(.every6Hours))
    let second = try makeSource(idByte: 2, policy: .automatic(.every6Hours))
    let context = SchedulingContext(
      sources: [first, second],
      now: now,
      behaviors: [first.id: .failure(.networkFailure)]
    )

    let report = try await context.scheduler.evaluateAndRefreshDueSources()

    #expect(await context.refresher.order == [first.id, second.id])
    #expect(
      report.outcomes.contains {
        $0.sourceID == first.id && $0.result == .failed(.networkFailure)
      }
    )
    #expect(
      report.outcomes.contains {
        guard $0.sourceID == second.id, case .refreshed = $0.result else { return false }
        return true
      }
    )
  }

  @Test("An already-running same-source refresh is a safe outcome")
  func inProgressIsSafe() async throws {
    let source = try makeSource(idByte: 1, policy: .automatic(.daily))
    let context = SchedulingContext(
      sources: [source], now: now, behaviors: [source.id: .failure(.inProgress)])

    let report = try await context.scheduler.evaluateAndRefreshDueSources()

    #expect(report.outcomes == [AutomaticRefreshOutcome(sourceID: source.id, result: .inProgress)])
  }

  @Test("A duplicate cycle trigger is coalesced")
  func duplicateCycleIsCoalesced() async throws {
    let source = try makeSource(idByte: 1, policy: .automatic(.daily))
    let context = SchedulingContext(
      sources: [source], now: now, behaviors: [source.id: .waitForCancellation])
    let firstCycle = Task { try await context.scheduler.evaluateAndRefreshDueSources() }
    await context.refresher.waitUntilStarted(source.id)

    let duplicate = try await context.scheduler.evaluateAndRefreshDueSources()
    #expect(duplicate.wasCoalesced)
    #expect(await context.refresher.order == [source.id])

    firstCycle.cancel()
    await #expect(throws: CancellationError.self) { try await firstCycle.value }
  }

  @Test("Cancellation reaches current work and prevents later queued refreshes")
  func cancellationStopsQueue() async throws {
    let first = try makeSource(idByte: 1, policy: .automatic(.daily))
    let second = try makeSource(idByte: 2, policy: .automatic(.daily))
    let third = try makeSource(idByte: 3, policy: .automatic(.daily))
    let context = SchedulingContext(
      sources: [first, second, third],
      now: now,
      behaviors: [second.id: .waitForCancellation]
    )
    let cycle = Task { try await context.scheduler.evaluateAndRefreshDueSources() }
    await context.refresher.waitUntilStarted(second.id)

    cycle.cancel()
    await #expect(throws: CancellationError.self) { try await cycle.value }
    #expect(await context.refresher.order == [first.id, second.id])
    #expect(await context.store.metadataValue(for: first.id)?.lastResult == .success)
    #expect(await context.store.metadataValue(for: third.id) == nil)
  }

  @Test("Repeated active notifications keep one lifecycle scheduling session")
  func lifecycleActivationIsCoalesced() async throws {
    let scheduler = LifecycleSchedulingFake()
    let coordinator = ActiveRefreshSchedulingCoordinator(scheduler: scheduler)

    await coordinator.activate()
    await scheduler.waitUntilEvaluated()
    await coordinator.activate()
    await Task.yield()

    #expect(await scheduler.evaluationCount == 1)
    #expect(await coordinator.hasActiveSession)
    await coordinator.deactivate()
    #expect(await coordinator.hasActiveSession == false)
  }

  @Test("Leaving active cancels the current scheduling wait")
  func lifecycleDeactivationCancelsWaitingSession() async throws {
    let scheduler = WaitingLifecycleSchedulingFake(now: now)
    let clock = WaitingSchedulingClock(now: now)
    let coordinator = ActiveRefreshSchedulingCoordinator(scheduler: scheduler, clock: clock)

    await coordinator.activate()
    await clock.waitUntilSleeping()
    await coordinator.deactivate()
    await clock.waitUntilCancelled()

    #expect(await scheduler.evaluationCount == 1)
    #expect(await clock.requestedWakeDate == now.addingTimeInterval(6 * 60 * 60))
    #expect(await coordinator.hasActiveSession == false)
  }

  private func successMetadata(
    for source: SourceConfiguration,
    hoursAgo: TimeInterval
  ) -> CatalogRefreshMetadata {
    let date = now.addingTimeInterval(-hoursAgo * 60 * 60)
    return CatalogRefreshMetadata(
      sourceID: source.id,
      lastAttemptedAt: date,
      lastSuccessfulAt: date,
      lastCommittedItemCount: 1,
      lastResult: .success
    )
  }

  private func makeSource(
    idByte: UInt8,
    policy: RefreshPolicy,
    enabled: Bool = true
  ) throws -> SourceConfiguration {
    SourceConfiguration(
      id: SourceConfiguration.ID(
        rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, idByte))
      ),
      displayName: "Synthetic \(idByte)",
      kind: .m3u,
      endpoint: try SourceEndpoint(url: #require(URL(string: "https://example.invalid/list.m3u"))),
      isEnabled: enabled,
      refreshPolicy: policy
    )
  }
}

private struct SchedulingContext {
  let store: SchedulingStore
  let refresher: SchedulingRefresher
  let scheduler: RefreshSchedulingService

  init(
    sources: [SourceConfiguration],
    now: Date,
    behaviors: [SourceConfiguration.ID: SchedulingRefresher.Behavior] = [:]
  ) {
    let store = SchedulingStore(sources: sources)
    let refresher = SchedulingRefresher(now: now, store: store, behaviors: behaviors)
    self.store = store
    self.refresher = refresher
    scheduler = RefreshSchedulingService(
      sourceRepository: store,
      metadataRepository: store,
      refreshService: refresher,
      clock: FixedSchedulingClock(now: now)
    )
  }
}

private struct FixedSchedulingClock: RefreshSchedulingClock {
  let nowValue: Date
  init(now: Date) { nowValue = now }
  func now() async -> Date { nowValue }
  func sleep(until date: Date) async throws { try await Task.sleep(for: .seconds(60)) }
}

private actor SchedulingStore: SourceRepository, CatalogRefreshMetadataRepository {
  private var sources: [SourceConfiguration]
  private var metadata: [SourceConfiguration.ID: CatalogRefreshMetadata] = [:]

  init(sources: [SourceConfiguration]) { self.sources = sources }

  func setMetadata(_ value: CatalogRefreshMetadata) { metadata[value.sourceID] = value }
  func metadataValue(for sourceID: SourceConfiguration.ID) -> CatalogRefreshMetadata? {
    metadata[sourceID]
  }
  func listSources() async throws -> [SourceConfiguration] { sources }
  func source(id: SourceConfiguration.ID) async throws -> SourceConfiguration? {
    sources.first { $0.id == id }
  }
  func create(_ source: SourceConfiguration) async throws { sources.append(source) }
  func update(_ source: SourceConfiguration) async throws {
    guard let index = sources.firstIndex(where: { $0.id == source.id }) else {
      throw SourceRepositoryError.sourceNotFound
    }
    sources[index] = source
  }
  func delete(id: SourceConfiguration.ID) async throws { sources.removeAll { $0.id == id } }
  func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async throws {}
  func refreshMetadata(for sourceID: SourceConfiguration.ID) async throws
    -> CatalogRefreshMetadata?
  {
    metadata[sourceID]
  }
  func recordRefreshAttempt(
    sourceID: SourceConfiguration.ID,
    attemptedAt: Date,
    result: CatalogRefreshResultCategory
  ) async throws {
    metadata[sourceID] = CatalogRefreshMetadata(
      sourceID: sourceID,
      lastAttemptedAt: attemptedAt,
      lastSuccessfulAt: metadata[sourceID]?.lastSuccessfulAt,
      lastCommittedItemCount: metadata[sourceID]?.lastCommittedItemCount ?? 0,
      lastResult: result
    )
  }
}

private actor SchedulingRefresher: CatalogRefreshing {
  enum Behavior: Sendable {
    case success
    case failure(CatalogRefreshError)
    case waitForCancellation
  }

  private let now: Date
  private let store: SchedulingStore
  private let behaviors: [SourceConfiguration.ID: Behavior]
  private var startedWaiters: [SourceConfiguration.ID: [CheckedContinuation<Void, Never>]] = [:]
  private(set) var order: [SourceConfiguration.ID] = []
  private(set) var maximumConcurrentCount = 0
  private var concurrentCount = 0

  init(
    now: Date,
    store: SchedulingStore,
    behaviors: [SourceConfiguration.ID: Behavior]
  ) {
    self.now = now
    self.store = store
    self.behaviors = behaviors
  }

  func waitUntilStarted(_ sourceID: SourceConfiguration.ID) async {
    if order.contains(sourceID) { return }
    await withCheckedContinuation { continuation in
      startedWaiters[sourceID, default: []].append(continuation)
    }
  }

  func refresh(
    _ source: SourceConfiguration,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> CatalogRefreshReport {
    order.append(source.id)
    concurrentCount += 1
    maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
    let waiters = startedWaiters.removeValue(forKey: source.id) ?? []
    for waiter in waiters { waiter.resume() }
    defer { concurrentCount -= 1 }

    switch behaviors[source.id] ?? .success {
    case .success:
      await store.setMetadata(
        CatalogRefreshMetadata(
          sourceID: source.id,
          lastAttemptedAt: now,
          lastSuccessfulAt: now,
          lastCommittedItemCount: 1,
          lastResult: .success
        )
      )
      return CatalogRefreshReport(sourceID: source.id, committedItemCount: 1, completedAt: now)
    case .failure(let error):
      try await store.recordRefreshAttempt(
        sourceID: source.id, attemptedAt: now, result: error.category)
      throw error
    case .waitForCancellation:
      try await Task.sleep(for: .seconds(3_600))
      throw CatalogRefreshError.persistenceFailure
    }
  }
}

private actor LifecycleSchedulingFake: RefreshScheduling {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var evaluationCount = 0

  func waitUntilEvaluated() async {
    if evaluationCount > 0 { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func evaluateAndRefreshDueSources() async throws -> RefreshSchedulingCycleReport {
    evaluationCount += 1
    let continuations = waiters
    waiters = []
    for continuation in continuations { continuation.resume() }
    return RefreshSchedulingCycleReport(outcomes: [], nextEligibleAt: nil)
  }

  func nextEligibleDate() async throws -> Date? { nil }
}

private actor WaitingLifecycleSchedulingFake: RefreshScheduling {
  let now: Date
  private(set) var evaluationCount = 0

  init(now: Date) { self.now = now }

  func evaluateAndRefreshDueSources() async throws -> RefreshSchedulingCycleReport {
    evaluationCount += 1
    return RefreshSchedulingCycleReport(
      outcomes: [],
      nextEligibleAt: now.addingTimeInterval(6 * 60 * 60)
    )
  }

  func nextEligibleDate() async throws -> Date? { now.addingTimeInterval(6 * 60 * 60) }
}

private actor WaitingSchedulingClock: RefreshSchedulingClock {
  let nowValue: Date
  private var sleepingWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requestedWakeDate: Date?
  private var wasCancelled = false

  init(now: Date) { nowValue = now }

  func now() async -> Date { nowValue }

  func sleep(until date: Date) async throws {
    requestedWakeDate = date
    let waiters = sleepingWaiters
    sleepingWaiters = []
    for waiter in waiters { waiter.resume() }
    do {
      try await Task.sleep(for: .seconds(3_600))
    } catch is CancellationError {
      wasCancelled = true
      let waiters = cancellationWaiters
      cancellationWaiters = []
      for waiter in waiters { waiter.resume() }
      throw CancellationError()
    }
  }

  func waitUntilSleeping() async {
    if requestedWakeDate != nil { return }
    await withCheckedContinuation { sleepingWaiters.append($0) }
  }

  func waitUntilCancelled() async {
    if wasCancelled { return }
    await withCheckedContinuation { cancellationWaiters.append($0) }
  }
}
