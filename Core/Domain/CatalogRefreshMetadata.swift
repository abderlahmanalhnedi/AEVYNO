import Foundation

public enum CatalogRefreshResultCategory: String, Codable, CaseIterable, Sendable {
  case success
  case invalidSource
  case credentialUnavailable
  case authenticationRejected
  case networkFailure
  case timeout
  case malformedSource
  case persistenceFailure
  case cancelled
  case inProgress
}

/// Local-only operational state. It deliberately contains no provider payload or diagnostic text.
public struct CatalogRefreshMetadata: Codable, Equatable, Sendable {
  public let sourceID: SourceConfiguration.ID
  public let lastAttemptedAt: Date
  public let lastSuccessfulAt: Date?
  public let lastCommittedItemCount: Int
  public let lastResult: CatalogRefreshResultCategory

  public init(
    sourceID: SourceConfiguration.ID,
    lastAttemptedAt: Date,
    lastSuccessfulAt: Date?,
    lastCommittedItemCount: Int,
    lastResult: CatalogRefreshResultCategory
  ) {
    self.sourceID = sourceID
    self.lastAttemptedAt = lastAttemptedAt
    self.lastSuccessfulAt = lastSuccessfulAt
    self.lastCommittedItemCount = lastCommittedItemCount
    self.lastResult = lastResult
  }
}
