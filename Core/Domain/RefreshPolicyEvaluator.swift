import Foundation

public enum AutomaticRefreshSkipReason: Equatable, Sendable {
  case sourceDisabled
  case manualOnly
  case cadenceNotElapsed
  case retryCooldown
}

public enum AutomaticRefreshEvaluation: Equatable, Sendable {
  case due(eligibleSince: Date)
  case skipped(reason: AutomaticRefreshSkipReason, nextEligibleAt: Date?)

  public var nextEligibleAt: Date? {
    switch self {
    case .due(let eligibleSince): eligibleSince
    case .skipped(_, let nextEligibleAt): nextEligibleAt
    }
  }

  public var isDue: Bool {
    if case .due = self { return true }
    return false
  }
}

public struct RefreshPolicyEvaluator: Sendable {
  public static let defaultRetryCooldown: TimeInterval = 30 * 60

  public let retryCooldown: TimeInterval

  public init(retryCooldown: TimeInterval = Self.defaultRetryCooldown) {
    self.retryCooldown = max(0, retryCooldown)
  }

  public func evaluate(
    source: SourceConfiguration,
    metadata: CatalogRefreshMetadata?,
    now: Date
  ) -> AutomaticRefreshEvaluation {
    guard source.isEnabled else {
      return .skipped(reason: .sourceDisabled, nextEligibleAt: nil)
    }
    guard case .automatic(let cadence) = source.refreshPolicy else {
      return .skipped(reason: .manualOnly, nextEligibleAt: nil)
    }

    let cadenceEligibleAt =
      metadata?.lastSuccessfulAt?.addingTimeInterval(cadence.duration) ?? .distantPast
    var eligibleAt = cadenceEligibleAt
    var waitingForCooldown = false

    if let metadata, metadata.lastResult != .success {
      let cooldownEligibleAt = metadata.lastAttemptedAt.addingTimeInterval(retryCooldown)
      if cooldownEligibleAt > eligibleAt {
        eligibleAt = cooldownEligibleAt
        waitingForCooldown = true
      }
    }

    guard now >= eligibleAt else {
      return .skipped(
        reason: waitingForCooldown ? .retryCooldown : .cadenceNotElapsed,
        nextEligibleAt: eligibleAt
      )
    }
    return .due(eligibleSince: eligibleAt)
  }
}
