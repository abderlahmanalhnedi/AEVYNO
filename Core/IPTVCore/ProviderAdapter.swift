import Domain
import Foundation

public protocol ProviderAdapter: Sendable {
  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot

  func categories(
    for kind: ProviderMediaKind,
    source: SourceConfiguration
  ) async throws -> ProviderCategoryResult

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport
}

public struct ProviderCategoryResult: Equatable, Sendable {
  public let categories: [ProviderCategory]
  public let receivedCount: Int
  public let skippedCount: Int

  public init(
    categories: [ProviderCategory],
    receivedCount: Int,
    skippedCount: Int
  ) {
    self.categories = categories
    self.receivedCount = receivedCount
    self.skippedCount = skippedCount
  }
}

public struct ProviderCatalogReport: Equatable, Sendable {
  public let receivedCount: Int
  public let normalizedCount: Int
  public let skippedCount: Int

  public init(receivedCount: Int, normalizedCount: Int, skippedCount: Int) {
    self.receivedCount = receivedCount
    self.normalizedCount = normalizedCount
    self.skippedCount = skippedCount
  }
}

public enum ProviderAdapterError: Error, Equatable, Sendable, LocalizedError,
  CustomStringConvertible
{
  case invalidSourceConfiguration
  case credentialUnavailable
  case authenticationRejected
  case transportUnavailable
  case timedOut
  case httpError(statusCode: Int)
  case malformedResponse
  case providerResponseInvalid

  public var errorDescription: String? {
    switch self {
    case .invalidSourceConfiguration:
      return "The provider source is not configured correctly."
    case .credentialUnavailable:
      return "The provider credential is unavailable."
    case .authenticationRejected:
      return "The provider rejected the account credentials."
    case .transportUnavailable:
      return "The provider is currently unreachable."
    case .timedOut:
      return "The provider request timed out."
    case .httpError(let statusCode):
      return "The provider returned HTTP status \(statusCode)."
    case .malformedResponse:
      return "The provider returned an unreadable response."
    case .providerResponseInvalid:
      return "The provider response is missing required information."
    }
  }

  public var description: String {
    errorDescription ?? "The provider request failed."
  }
}
