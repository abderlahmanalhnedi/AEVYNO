import Domain
import Foundation
import Persistence

public protocol CatalogRefreshing: Sendable {
  func refresh(
    _ source: SourceConfiguration,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> CatalogRefreshReport
}

extension CatalogRefreshService: CatalogRefreshing {}

public protocol RefreshSchedulingClock: Sendable {
  func now() async -> Date
  func sleep(until date: Date) async throws
}

public struct SystemRefreshSchedulingClock: RefreshSchedulingClock {
  public init() {}

  public func now() async -> Date { Date() }

  public func sleep(until date: Date) async throws {
    let delay = max(0, date.timeIntervalSinceNow)
    try await Task.sleep(for: .seconds(delay))
  }
}

public enum AutomaticRefreshOutcomeResult: Equatable, Sendable {
  case skipped(reason: AutomaticRefreshSkipReason, nextEligibleAt: Date?)
  case refreshed(committedItemCount: Int, completedAt: Date)
  case failed(CatalogRefreshResultCategory)
  case inProgress
}

public struct AutomaticRefreshOutcome: Equatable, Sendable {
  public let sourceID: SourceConfiguration.ID
  public let result: AutomaticRefreshOutcomeResult

  public init(sourceID: SourceConfiguration.ID, result: AutomaticRefreshOutcomeResult) {
    self.sourceID = sourceID
    self.result = result
  }
}

public struct RefreshSchedulingCycleReport: Equatable, Sendable {
  public let outcomes: [AutomaticRefreshOutcome]
  public let nextEligibleAt: Date?
  public let wasCoalesced: Bool

  public init(
    outcomes: [AutomaticRefreshOutcome],
    nextEligibleAt: Date?,
    wasCoalesced: Bool = false
  ) {
    self.outcomes = outcomes
    self.nextEligibleAt = nextEligibleAt
    self.wasCoalesced = wasCoalesced
  }
}

public enum RefreshSchedulingError: Error, Equatable, Sendable {
  case persistenceFailure
}

public protocol RefreshScheduling: Sendable {
  func evaluateAndRefreshDueSources() async throws -> RefreshSchedulingCycleReport
  func nextEligibleDate() async throws -> Date?
}

/// Evaluates small source/metadata records and delegates due work to the durable refresh service.
public actor RefreshSchedulingService: RefreshScheduling {
  private struct DueSource {
    let source: SourceConfiguration
    let eligibleSince: Date
  }

  private let sourceRepository: any SourceRepository
  private let metadataRepository: any CatalogRefreshMetadataRepository
  private let refreshService: any CatalogRefreshing
  private let clock: any RefreshSchedulingClock
  private let evaluator: RefreshPolicyEvaluator
  private var isCycleRunning = false

  public init(
    sourceRepository: any SourceRepository,
    metadataRepository: any CatalogRefreshMetadataRepository,
    refreshService: any CatalogRefreshing,
    clock: any RefreshSchedulingClock = SystemRefreshSchedulingClock(),
    evaluator: RefreshPolicyEvaluator = RefreshPolicyEvaluator()
  ) {
    self.sourceRepository = sourceRepository
    self.metadataRepository = metadataRepository
    self.refreshService = refreshService
    self.clock = clock
    self.evaluator = evaluator
  }

  public func evaluateAndRefreshDueSources() async throws -> RefreshSchedulingCycleReport {
    guard !isCycleRunning else {
      return RefreshSchedulingCycleReport(outcomes: [], nextEligibleAt: nil, wasCoalesced: true)
    }
    isCycleRunning = true
    defer { isCycleRunning = false }

    let now = await clock.now()
    let evaluations = try await evaluateSources(now: now)
    var outcomes = evaluations.skipped

    for due in evaluations.due {
      try Task.checkCancellation()
      do {
        let report = try await refreshService.refresh(due.source, onStage: nil)
        outcomes.append(
          AutomaticRefreshOutcome(
            sourceID: due.source.id,
            result: .refreshed(
              committedItemCount: report.committedItemCount,
              completedAt: report.completedAt
            )
          )
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as CatalogRefreshError where error == .inProgress {
        outcomes.append(
          AutomaticRefreshOutcome(sourceID: due.source.id, result: .inProgress)
        )
      } catch let error as CatalogRefreshError {
        outcomes.append(
          AutomaticRefreshOutcome(sourceID: due.source.id, result: .failed(error.category))
        )
      } catch {
        outcomes.append(
          AutomaticRefreshOutcome(sourceID: due.source.id, result: .failed(.persistenceFailure))
        )
      }
    }

    let nextEligibleAt = try await nextEligibleDate(at: await clock.now())
    return RefreshSchedulingCycleReport(
      outcomes: outcomes,
      nextEligibleAt: nextEligibleAt
    )
  }

  public func nextEligibleDate() async throws -> Date? {
    try await nextEligibleDate(at: await clock.now())
  }

  private func evaluateSources(now: Date) async throws -> (
    due: [DueSource], skipped: [AutomaticRefreshOutcome]
  ) {
    let sources: [SourceConfiguration]
    do {
      sources = try await sourceRepository.listSources()
    } catch {
      throw RefreshSchedulingError.persistenceFailure
    }

    var due: [DueSource] = []
    var skipped: [AutomaticRefreshOutcome] = []
    due.reserveCapacity(sources.count)
    skipped.reserveCapacity(sources.count)
    for source in sources {
      try Task.checkCancellation()
      let metadata: CatalogRefreshMetadata?
      do {
        metadata = try await metadataRepository.refreshMetadata(for: source.id)
      } catch {
        throw RefreshSchedulingError.persistenceFailure
      }
      switch evaluator.evaluate(source: source, metadata: metadata, now: now) {
      case .due(let eligibleSince):
        due.append(DueSource(source: source, eligibleSince: eligibleSince))
      case .skipped(let reason, let nextEligibleAt):
        skipped.append(
          AutomaticRefreshOutcome(
            sourceID: source.id,
            result: .skipped(reason: reason, nextEligibleAt: nextEligibleAt)
          )
        )
      }
    }
    due.sort {
      if $0.eligibleSince != $1.eligibleSince { return $0.eligibleSince < $1.eligibleSince }
      return $0.source.id.rawValue.uuidString < $1.source.id.rawValue.uuidString
    }
    return (due, skipped)
  }

  private func nextEligibleDate(at now: Date) async throws -> Date? {
    let evaluations = try await evaluateSources(now: now)
    if !evaluations.due.isEmpty { return now }
    return evaluations.skipped.compactMap { outcome in
      guard case .skipped(_, let nextEligibleAt) = outcome.result else { return nil }
      return nextEligibleAt
    }.min()
  }
}

/// Owns one cancellable scheduling loop for the current active application session.
public actor ActiveRefreshSchedulingCoordinator {
  private let scheduler: any RefreshScheduling
  private let clock: any RefreshSchedulingClock
  private var sessionTask: Task<Void, any Error>?

  public init(
    scheduler: any RefreshScheduling,
    clock: any RefreshSchedulingClock = SystemRefreshSchedulingClock()
  ) {
    self.scheduler = scheduler
    self.clock = clock
  }

  public func activate() {
    guard sessionTask == nil else { return }
    sessionTask = Task { [scheduler, clock] in
      try await Self.runActiveSession(scheduler: scheduler, clock: clock)
    }
  }

  public func deactivate() {
    sessionTask?.cancel()
    sessionTask = nil
  }

  public var hasActiveSession: Bool { sessionTask != nil }

  private static func runActiveSession(
    scheduler: any RefreshScheduling,
    clock: any RefreshSchedulingClock
  ) async throws {
    while true {
      try Task.checkCancellation()
      let report = try await scheduler.evaluateAndRefreshDueSources()
      guard let nextEligibleAt = report.nextEligibleAt else { return }
      let now = await clock.now()
      let wakeDate = max(nextEligibleAt, now.addingTimeInterval(60))
      try await clock.sleep(until: wakeDate)
    }
  }
}

/// Resolves production dependencies lazily so launch rendering never waits on disk or Keychain.
public actor LazyActiveRefreshSchedulingCoordinator {
  public typealias SchedulerFactory = @Sendable () async throws -> any RefreshScheduling

  private let schedulerFactory: SchedulerFactory
  private var coordinator: ActiveRefreshSchedulingCoordinator?
  private var isActive = false

  public init(schedulerFactory: @escaping SchedulerFactory) {
    self.schedulerFactory = schedulerFactory
  }

  public func activate() async throws {
    guard !isActive else { return }
    isActive = true
    do {
      let scheduler = try await schedulerFactory()
      try Task.checkCancellation()
      guard isActive else { return }
      let resolved = ActiveRefreshSchedulingCoordinator(scheduler: scheduler)
      coordinator = resolved
      await resolved.activate()
    } catch {
      isActive = false
      throw error
    }
  }

  public func deactivate() async {
    isActive = false
    await coordinator?.deactivate()
    coordinator = nil
  }
}
