import Foundation

public enum CloudAccountAvailability: Equatable, Sendable {
  case available
  case noAccount
  case restricted
  case temporarilyUnavailable
  case couldNotDetermine
}

public enum CloudProgressStoreError: Error, Equatable, Sendable {
  case accountUnavailable(CloudAccountAvailability)
  case networkUnavailable
  case serviceUnavailable(retryAfter: TimeInterval?)
  case rateLimited(retryAfter: TimeInterval?)
  case quotaExceeded
  case serverConflict
  case unsupportedSchema
  case invalidData
  case configuration
  case unknown

  var isRetryable: Bool {
    switch self {
    case .networkUnavailable, .serviceUnavailable, .rateLimited, .serverConflict:
      true
    case .accountUnavailable(let availability):
      availability == .temporarilyUnavailable || availability == .couldNotDetermine
    case .quotaExceeded, .unsupportedSchema, .invalidData, .configuration, .unknown:
      false
    }
  }

  var retryAfter: TimeInterval? {
    switch self {
    case .serviceUnavailable(let delay), .rateLimited(let delay): delay
    default: nil
    }
  }
}

public struct CloudWatchProgressChangeBatch: Equatable, Sendable {
  public let records: [CloudWatchProgressRecord]
  public let changeToken: Data?

  public init(records: [CloudWatchProgressRecord], changeToken: Data?) {
    self.records = records
    self.changeToken = changeToken
  }
}

public protocol CloudWatchProgressStore: Sendable {
  func accountAvailability() async -> CloudAccountAvailability
  func fetchChanges(since changeToken: Data?) async throws -> CloudWatchProgressChangeBatch
  @discardableResult
  func save(_ records: [CloudWatchProgressRecord]) async throws -> [CloudWatchProgressRecord]
}

public enum WatchProgressSyncFailure: Equatable, Sendable {
  case localMetadata
  case schema
  case quota
  case configuration
  case cloudService
}

public enum WatchProgressSyncStatus: Equatable, Sendable {
  case idle
  case syncing
  case upToDate
  case unavailable(CloudAccountAvailability)
  case waitingForRetry(attempt: Int, delay: TimeInterval)
  case failed(WatchProgressSyncFailure)
}

public struct WatchProgressRetryPolicy: Equatable, Sendable {
  public let maximumAttempts: Int
  public let initialDelay: TimeInterval
  public let multiplier: Double
  public let maximumDelay: TimeInterval

  public init(
    maximumAttempts: Int = 3,
    initialDelay: TimeInterval = 1,
    multiplier: Double = 2,
    maximumDelay: TimeInterval = 30
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.initialDelay = max(0, initialDelay)
    self.multiplier = max(1, multiplier)
    self.maximumDelay = max(0, maximumDelay)
  }

  public func delay(afterFailedAttempt attempt: Int, serverHint: TimeInterval? = nil)
    -> TimeInterval
  {
    let exponent = Double(max(0, attempt - 1))
    let policyDelay = min(initialDelay * pow(multiplier, exponent), maximumDelay)
    guard let serverHint, serverHint.isFinite, serverHint >= 0 else { return policyDelay }
    return min(max(policyDelay, serverHint), maximumDelay)
  }
}

public protocol WatchProgressSyncSleeper: Sendable {
  func sleep(for delay: TimeInterval) async throws
}

public struct SystemWatchProgressSyncSleeper: WatchProgressSyncSleeper {
  public init() {}

  public func sleep(for delay: TimeInterval) async throws {
    guard delay > 0 else {
      try Task.checkCancellation()
      return
    }
    try await Task.sleep(for: .seconds(delay))
  }
}

public protocol WatchProgressOperationIDGenerator: Sendable {
  func next() async -> String
}

public struct UUIDWatchProgressOperationIDGenerator: WatchProgressOperationIDGenerator {
  public init() {}
  public func next() -> String { UUID().uuidString.lowercased() }
}
