import Domain
import Foundation
import IPTVCore
import Persistence

public enum CatalogRefreshStage: Equatable, Sendable {
  case validating
  case acquiring
  case parsingOrDecoding
  case staging
  case committing
  case completed
  case failed(CatalogRefreshResultCategory)
  case cancelled
}

public enum CatalogRefreshError: Error, Equatable, Sendable, LocalizedError,
  CustomStringConvertible
{
  case invalidSource
  case credentialUnavailable
  case authenticationRejected
  case networkFailure
  case timeout
  case malformedSource
  case persistenceFailure
  case inProgress

  public var category: CatalogRefreshResultCategory {
    switch self {
    case .invalidSource: .invalidSource
    case .credentialUnavailable: .credentialUnavailable
    case .authenticationRejected: .authenticationRejected
    case .networkFailure: .networkFailure
    case .timeout: .timeout
    case .malformedSource: .malformedSource
    case .persistenceFailure: .persistenceFailure
    case .inProgress: .inProgress
    }
  }

  public var errorDescription: String? {
    switch self {
    case .invalidSource: "The source configuration is not valid for refresh."
    case .credentialUnavailable: "The source credential is unavailable."
    case .authenticationRejected: "The source rejected the account credentials."
    case .networkFailure: "The source is currently unreachable."
    case .timeout: "The source request timed out."
    case .malformedSource: "The source returned an unreadable catalog."
    case .persistenceFailure: "The refreshed catalog could not be saved safely."
    case .inProgress: "This source is already being refreshed."
    }
  }

  public var description: String { errorDescription ?? "The source refresh failed." }
}

public struct CatalogRefreshReport: Equatable, Sendable {
  public let sourceID: SourceConfiguration.ID
  public let committedItemCount: Int
  public let completedAt: Date

  public init(
    sourceID: SourceConfiguration.ID,
    committedItemCount: Int,
    completedAt: Date
  ) {
    self.sourceID = sourceID
    self.committedItemCount = committedItemCount
    self.completedAt = completedAt
  }
}

public protocol CatalogRefreshClock: Sendable {
  func now() async -> Date
}

public struct SystemCatalogRefreshClock: CatalogRefreshClock {
  public init() {}
  public func now() async -> Date { Date() }
}

public typealias CatalogRefreshStageHandler = @Sendable (CatalogRefreshStage) async -> Void

/// Provider-neutral source refresh orchestration. UI receives only safe lifecycle stages.
public actor CatalogRefreshService {
  private let repository: any CatalogRefreshRepository
  private let m3uAcquisition: M3UAcquisitionService
  private let providerAdapter: any ProviderAdapter
  private let m3uImporter: M3UImportService
  private let providerImporter: ProviderCatalogImportService
  private let clock: any CatalogRefreshClock
  private var activeSourceIDs: Set<SourceConfiguration.ID> = []

  public init(
    repository: any CatalogRefreshRepository,
    m3uAcquisition: M3UAcquisitionService,
    providerAdapter: any ProviderAdapter,
    m3uImporter: M3UImportService = M3UImportService(),
    providerImporter: ProviderCatalogImportService = ProviderCatalogImportService(),
    clock: any CatalogRefreshClock = SystemCatalogRefreshClock()
  ) {
    self.repository = repository
    self.m3uAcquisition = m3uAcquisition
    self.providerAdapter = providerAdapter
    self.m3uImporter = m3uImporter
    self.providerImporter = providerImporter
    self.clock = clock
  }

  public func refresh(
    _ source: SourceConfiguration,
    onStage: CatalogRefreshStageHandler? = nil
  ) async throws -> CatalogRefreshReport {
    guard activeSourceIDs.insert(source.id).inserted else {
      await onStage?(.failed(.inProgress))
      throw CatalogRefreshError.inProgress
    }
    defer { activeSourceIDs.remove(source.id) }

    let attemptedAt = await clock.now()
    do {
      try await repository.recordRefreshAttempt(
        sourceID: source.id, attemptedAt: attemptedAt, result: .inProgress)
    } catch {
      await onStage?(.failed(.persistenceFailure))
      throw CatalogRefreshError.persistenceFailure
    }

    do {
      await onStage?(.validating)
      try validate(source)
      let committedItemCount: Int
      switch source.kind {
      case .m3u:
        committedItemCount = try await refreshM3U(
          source, attemptedAt: attemptedAt, onStage: onStage)
      case .xtreamCompatible:
        committedItemCount = try await refreshXtream(
          source, attemptedAt: attemptedAt, onStage: onStage)
      }
      let completedAt = await clock.now()
      await onStage?(.completed)
      return CatalogRefreshReport(
        sourceID: source.id,
        committedItemCount: committedItemCount,
        completedAt: completedAt
      )
    } catch {
      let category = Self.category(for: error)
      do {
        try await repository.recordRefreshAttempt(
          sourceID: source.id, attemptedAt: attemptedAt, result: category)
      } catch {
        await onStage?(.failed(.persistenceFailure))
        throw CatalogRefreshError.persistenceFailure
      }
      if category == .cancelled {
        await onStage?(.cancelled)
        throw CancellationError()
      }
      await onStage?(.failed(category))
      throw Self.publicError(for: category)
    }
  }

  private func validate(_ source: SourceConfiguration) throws {
    guard source.isEnabled, source.endpoint != nil else { throw CatalogRefreshError.invalidSource }
    if source.kind == .xtreamCompatible, source.credentialReference == nil {
      throw CatalogRefreshError.invalidSource
    }
  }

  private func refreshM3U(
    _ source: SourceConfiguration,
    attemptedAt: Date,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> Int {
    await onStage?(.acquiring)
    let data = try await m3uAcquisition.acquire(from: source)
    try Task.checkCancellation()

    let scope = CatalogScope(sourceID: source.id, origin: .m3u, kind: .unspecified)
    let stagingID = try await repository.beginStaging(in: [scope])
    do {
      await onStage?(.parsingOrDecoding)
      await onStage?(.staging)
      let report = try await m3uImporter.importPlaylist(
        lines: M3UDataLineSequence(data: data),
        sourceID: source.id,
        sink: PersistentCatalogImportSink(
          repository: repository, deferredStagingID: stagingID, scope: scope)
      )
      try Task.checkCancellation()
      let successfulAt = await clock.now()
      await onStage?(.committing)
      return try await repository.commitStagedReplacement(
        stagingID,
        successfulRefresh: CatalogRefreshMetadata(
          sourceID: source.id,
          lastAttemptedAt: attemptedAt,
          lastSuccessfulAt: successfulAt,
          lastCommittedItemCount: report.importedCount,
          lastResult: .success
        )
      )
    } catch {
      await repository.discardStaging(stagingID)
      throw error
    }
  }

  private func refreshXtream(
    _ source: SourceConfiguration,
    attemptedAt: Date,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> Int {
    await onStage?(.acquiring)
    _ = try await providerAdapter.discover(source: source)
    try Task.checkCancellation()

    let kinds = ProviderMediaKind.allCases
    let scopes = kinds.map {
      CatalogScope(sourceID: source.id, origin: .xtream, kind: CatalogMediaKind($0))
    }
    let stagingID = try await repository.beginStaging(in: scopes)
    do {
      var importedCount = 0
      await onStage?(.parsingOrDecoding)
      await onStage?(.staging)
      for (kind, scope) in zip(kinds, scopes) {
        try Task.checkCancellation()
        let report = try await providerImporter.importCatalog(
          for: kind,
          from: source,
          using: providerAdapter,
          into: PersistentCatalogImportSink(
            repository: repository, deferredStagingID: stagingID, scope: scope)
        )
        importedCount += report.importedCount
      }
      try Task.checkCancellation()
      let successfulAt = await clock.now()
      await onStage?(.committing)
      return try await repository.commitStagedReplacement(
        stagingID,
        successfulRefresh: CatalogRefreshMetadata(
          sourceID: source.id,
          lastAttemptedAt: attemptedAt,
          lastSuccessfulAt: successfulAt,
          lastCommittedItemCount: importedCount,
          lastResult: .success
        )
      )
    } catch {
      await repository.discardStaging(stagingID)
      throw error
    }
  }
}

extension CatalogRefreshService {
  private static func category(for error: any Error) -> CatalogRefreshResultCategory {
    if error is CancellationError { return .cancelled }
    if let error = error as? CatalogRefreshError { return error.category }
    if let error = error as? M3UAcquisitionError {
      switch error {
      case .invalidSourceConfiguration: return .invalidSource
      case .authenticationRejected: return .authenticationRejected
      case .timedOut: return .timeout
      case .emptyResponse, .responseTooLarge, .unsafeRedirect: return .malformedSource
      case .httpError, .transportUnavailable: return .networkFailure
      }
    }
    if let error = error as? ProviderAdapterError {
      switch error {
      case .invalidSourceConfiguration: return .invalidSource
      case .credentialUnavailable: return .credentialUnavailable
      case .authenticationRejected: return .authenticationRejected
      case .timedOut: return .timeout
      case .malformedResponse, .providerResponseInvalid: return .malformedSource
      case .transportUnavailable, .httpError: return .networkFailure
      }
    }
    if error is M3UParserError { return .malformedSource }
    if error is CatalogStoreError { return .persistenceFailure }
    return .persistenceFailure
  }

  private static func publicError(
    for category: CatalogRefreshResultCategory
  ) -> CatalogRefreshError {
    switch category {
    case .invalidSource: .invalidSource
    case .credentialUnavailable: .credentialUnavailable
    case .authenticationRejected: .authenticationRejected
    case .networkFailure: .networkFailure
    case .timeout: .timeout
    case .malformedSource: .malformedSource
    case .persistenceFailure: .persistenceFailure
    case .inProgress: .inProgress
    case .cancelled: .networkFailure
    case .success: .persistenceFailure
    }
  }
}
