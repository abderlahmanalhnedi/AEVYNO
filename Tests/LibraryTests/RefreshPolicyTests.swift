import Domain
import Foundation
import Testing

@Suite("Refresh policy evaluation")
struct RefreshPolicyTests {
  private let now = Date(timeIntervalSince1970: 2_000_000)

  @Test("Manual-only and disabled automatic sources are never due")
  func permanentSkips() throws {
    let evaluator = RefreshPolicyEvaluator()
    let manual = try source(policy: .manualOnly)
    let disabled = try source(policy: .automatic(.every6Hours), isEnabled: false)

    #expect(
      evaluator.evaluate(source: manual, metadata: nil, now: now)
        == .skipped(reason: .manualOnly, nextEligibleAt: nil)
    )
    #expect(
      evaluator.evaluate(source: disabled, metadata: nil, now: now)
        == .skipped(reason: .sourceDisabled, nextEligibleAt: nil)
    )
  }

  @Test("An automatic source without a successful refresh is immediately due")
  func firstAutomaticRefreshIsDue() throws {
    let evaluation = RefreshPolicyEvaluator().evaluate(
      source: try source(policy: .automatic(.daily)), metadata: nil, now: now)
    #expect(evaluation.isDue)
    #expect(evaluation.nextEligibleAt == .distantPast)
  }

  @Test("Cadence boundaries use elapsed instants")
  func cadenceBoundaries() throws {
    let cases: [(RefreshCadence, TimeInterval)] = [
      (.every6Hours, 6 * 60 * 60),
      (.every12Hours, 12 * 60 * 60),
      (.daily, 24 * 60 * 60),
    ]
    for (cadence, interval) in cases {
      let source = try source(policy: .automatic(cadence))
      let successfulAt = now.addingTimeInterval(-interval)
      let metadata = refreshMetadata(
        sourceID: source.id,
        attemptedAt: successfulAt,
        successfulAt: successfulAt,
        result: .success
      )
      let evaluator = RefreshPolicyEvaluator()

      #expect(
        evaluator.evaluate(
          source: source, metadata: metadata, now: now.addingTimeInterval(-0.001))
          == .skipped(reason: .cadenceNotElapsed, nextEligibleAt: now)
      )
      #expect(evaluator.evaluate(source: source, metadata: metadata, now: now).isDue)
      #expect(
        evaluator.evaluate(source: source, metadata: metadata, now: now.addingTimeInterval(1)).isDue
      )
      #expect(
        evaluator.evaluate(source: source, metadata: metadata, now: now).nextEligibleAt == now)
    }
  }

  @Test("Recent unsuccessful attempts observe the deterministic retry cooldown")
  func retryCooldown() throws {
    let source = try source(policy: .automatic(.every6Hours))
    let attemptedAt = now.addingTimeInterval(-10 * 60)
    let expected = attemptedAt.addingTimeInterval(30 * 60)

    for result in [CatalogRefreshResultCategory.networkFailure, .cancelled] {
      let metadata = refreshMetadata(
        sourceID: source.id,
        attemptedAt: attemptedAt,
        successfulAt: nil,
        result: result
      )
      #expect(
        RefreshPolicyEvaluator().evaluate(source: source, metadata: metadata, now: now)
          == .skipped(reason: .retryCooldown, nextEligibleAt: expected)
      )
      #expect(
        RefreshPolicyEvaluator().evaluate(source: source, metadata: metadata, now: expected).isDue
      )
    }
  }

  @Test("Time-zone changes cannot alter instant-based cadence semantics")
  func timeZoneIndependent() throws {
    let source = try source(policy: .automatic(.every12Hours))
    let successfulAt = Date(timeIntervalSince1970: 1_000_000)
    let dueAt = successfulAt.addingTimeInterval(12 * 60 * 60)
    let metadata = refreshMetadata(
      sourceID: source.id,
      attemptedAt: successfulAt,
      successfulAt: successfulAt,
      result: .success
    )

    for identifier in ["Pacific/Kiritimati", "UTC", "America/Adak"] {
      _ = TimeZone(identifier: identifier)
      #expect(
        RefreshPolicyEvaluator().evaluate(source: source, metadata: metadata, now: dueAt).isDue
      )
    }
  }

  private func source(
    policy: RefreshPolicy,
    isEnabled: Bool = true
  ) throws -> SourceConfiguration {
    SourceConfiguration(
      id: SourceConfiguration.ID(
        rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
      ),
      displayName: "Synthetic",
      kind: .m3u,
      endpoint: try SourceEndpoint(url: #require(URL(string: "https://example.invalid/list.m3u"))),
      isEnabled: isEnabled,
      refreshPolicy: policy
    )
  }

  private func refreshMetadata(
    sourceID: SourceConfiguration.ID,
    attemptedAt: Date,
    successfulAt: Date?,
    result: CatalogRefreshResultCategory
  ) -> CatalogRefreshMetadata {
    CatalogRefreshMetadata(
      sourceID: sourceID,
      lastAttemptedAt: attemptedAt,
      lastSuccessfulAt: successfulAt,
      lastCommittedItemCount: successfulAt == nil ? 0 : 1,
      lastResult: result
    )
  }
}
