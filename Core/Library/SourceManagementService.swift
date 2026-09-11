import AEVYNOSecurity
import Domain
import Foundation
import IPTVCore
import Persistence

public struct SourceDraft: Equatable, Sendable {
  public enum CredentialInput: Equatable, Sendable {
    case none
    case unchanged
    case replace(username: String, secret: String)
  }

  public var displayName: String
  public var kind: SourceKind
  public var endpoint: String
  public var isEnabled: Bool
  public var refreshPolicy: RefreshPolicy
  public var credential: CredentialInput

  public init(
    displayName: String = "",
    kind: SourceKind = .xtreamCompatible,
    endpoint: String = "",
    isEnabled: Bool = true,
    refreshPolicy: RefreshPolicy = .manualOnly,
    credential: CredentialInput = .none
  ) {
    self.displayName = displayName
    self.kind = kind
    self.endpoint = endpoint
    self.isEnabled = isEnabled
    self.refreshPolicy = refreshPolicy
    self.credential = credential
  }
}

public enum SourceValidationField: String, CaseIterable, Sendable {
  case displayName
  case sourceKind
  case endpoint
  case username
  case credential
}

public enum SourceValidationReason: String, Sendable {
  case required
  case tooLong
  case invalidURL
  case unsupportedScheme
  case missingHost
  case forbiddenURLComponents
  case credentialReplacementRequired
  case sourceKindCannotChange
}

public struct SourceValidationIssue: Equatable, Sendable {
  public let field: SourceValidationField
  public let reason: SourceValidationReason

  public init(field: SourceValidationField, reason: SourceValidationReason) {
    self.field = field
    self.reason = reason
  }
}

public struct ManagedSource: Equatable, Sendable, Identifiable {
  public let configuration: SourceConfiguration
  public let refreshMetadata: CatalogRefreshMetadata?

  public init(
    configuration: SourceConfiguration,
    refreshMetadata: CatalogRefreshMetadata?
  ) {
    self.configuration = configuration
    self.refreshMetadata = refreshMetadata
  }

  public var id: SourceConfiguration.ID { configuration.id }
}

public struct SourceConnectionReport: Equatable, Sendable {
  public let kind: SourceKind

  public init(kind: SourceKind) {
    self.kind = kind
  }
}

public enum SourceManagementError: Error, Equatable, Sendable {
  case invalidInput([SourceValidationIssue])
  case sourceNotFound
  case credentialUnavailable
  case authenticationRejected
  case timeout
  case unreachableProvider
  case malformedSource
  case persistenceFailure
  case secureStorageFailure
  case compensationFailure
  case cleanupFailure
  case inProgress
}

public protocol SourceManaging: Sendable {
  func listSources() async throws -> [ManagedSource]
  func source(id: SourceConfiguration.ID) async throws -> ManagedSource?
  func validateDraft(_ draft: SourceDraft, editing sourceID: SourceConfiguration.ID?) async
    -> [SourceValidationIssue]
  func createSource(from draft: SourceDraft) async throws -> SourceConfiguration
  func updateSource(id: SourceConfiguration.ID, from draft: SourceDraft) async throws
    -> SourceConfiguration
  func deleteSource(id: SourceConfiguration.ID) async throws
  func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async throws
  func testConnection(_ draft: SourceDraft, editing sourceID: SourceConfiguration.ID?) async throws
    -> SourceConnectionReport
  func refreshNow(
    id: SourceConfiguration.ID,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> CatalogRefreshReport
}

public struct ProductionSourceServices: Sendable {
  public let sourceManagement: SourceManagementService
  public let refreshScheduling: RefreshSchedulingService
  public let productionLibrary: ProductionLibraryService

  public init(
    sourceManagement: SourceManagementService,
    refreshScheduling: RefreshSchedulingService,
    productionLibrary: ProductionLibraryService
  ) {
    self.sourceManagement = sourceManagement
    self.refreshScheduling = refreshScheduling
    self.productionLibrary = productionLibrary
  }
}

/// Provider-neutral application workflow boundary for source metadata, credentials and catalogs.
public actor SourceManagementService: SourceManaging {
  public static let maximumDisplayNameLength = 120
  public static let maximumEndpointLength = 4_096
  public static let maximumUsernameLength = 1_024
  public static let maximumSecretLength = 4_096

  private let sourceRepository: any SourceRepository
  private let credentialStore: any CredentialStore
  private let catalogRepository: any CatalogRefreshRepository
  private let providerAdapter: any ProviderAdapter
  private let m3uAcquisition: M3UAcquisitionService
  private let m3uParser: M3UParser
  private let refreshService: CatalogRefreshService

  public init(
    sourceRepository: any SourceRepository,
    credentialStore: any CredentialStore,
    catalogRepository: any CatalogRefreshRepository,
    providerAdapter: any ProviderAdapter,
    m3uAcquisition: M3UAcquisitionService,
    m3uParser: M3UParser = M3UParser(),
    refreshService: CatalogRefreshService
  ) {
    self.sourceRepository = sourceRepository
    self.credentialStore = credentialStore
    self.catalogRepository = catalogRepository
    self.providerAdapter = providerAdapter
    self.m3uAcquisition = m3uAcquisition
    self.m3uParser = m3uParser
    self.refreshService = refreshService
  }

  public static func openDefault() async throws -> SourceManagementService {
    try await openDefaultServices().sourceManagement
  }

  public static func openDefaultServices() async throws -> ProductionSourceServices {
    let sourceRepository = try FileSourceRepository.openDefault()
    let credentialStore = KeychainCredentialStore()
    let catalogRepository = try await SQLiteCatalogStore.openDefault()
    let providerAdapter = XtreamProviderAdapter(credentialStore: credentialStore)
    let m3uAcquisition = M3UAcquisitionService()
    let revisionCenter = LibraryRevisionCenter()
    let refreshService = CatalogRefreshService(
      repository: catalogRepository,
      m3uAcquisition: m3uAcquisition,
      providerAdapter: providerAdapter,
      onCommit: { sourceID in await revisionCenter.publish(sourceID: sourceID) }
    )
    let sourceManagement = SourceManagementService(
      sourceRepository: sourceRepository,
      credentialStore: credentialStore,
      catalogRepository: catalogRepository,
      providerAdapter: providerAdapter,
      m3uAcquisition: m3uAcquisition,
      refreshService: refreshService
    )
    let refreshScheduling = RefreshSchedulingService(
      sourceRepository: sourceRepository,
      metadataRepository: catalogRepository,
      refreshService: refreshService
    )
    let productionLibrary = ProductionLibraryService(
      catalog: CatalogLibraryService(repository: catalogRepository),
      sourceService: sourceManagement,
      revisionCenter: revisionCenter
    )
    return ProductionSourceServices(
      sourceManagement: sourceManagement,
      refreshScheduling: refreshScheduling,
      productionLibrary: productionLibrary
    )
  }

  public func listSources() async throws -> [ManagedSource] {
    let sources: [SourceConfiguration]
    do {
      sources = try await sourceRepository.listSources()
    } catch {
      throw SourceManagementError.persistenceFailure
    }

    var managed: [ManagedSource] = []
    managed.reserveCapacity(sources.count)
    for source in sources {
      try Task.checkCancellation()
      let metadata: CatalogRefreshMetadata?
      do {
        metadata = try await catalogRepository.refreshMetadata(for: source.id)
      } catch {
        throw SourceManagementError.persistenceFailure
      }
      managed.append(ManagedSource(configuration: source, refreshMetadata: metadata))
    }
    return managed
  }

  public func source(id: SourceConfiguration.ID) async throws -> ManagedSource? {
    let configuration: SourceConfiguration?
    do {
      configuration = try await sourceRepository.source(id: id)
    } catch {
      throw SourceManagementError.persistenceFailure
    }
    guard let configuration else { return nil }
    do {
      return ManagedSource(
        configuration: configuration,
        refreshMetadata: try await catalogRepository.refreshMetadata(for: id)
      )
    } catch {
      throw SourceManagementError.persistenceFailure
    }
  }

  public func validateDraft(
    _ draft: SourceDraft,
    editing sourceID: SourceConfiguration.ID? = nil
  ) async -> [SourceValidationIssue] {
    let existing = await existingSource(editingSourceID: sourceID)
    return Self.validationIssues(for: draft, existing: existing)
  }

  public func createSource(from draft: SourceDraft) async throws -> SourceConfiguration {
    let input = try validatedInput(draft, existing: nil)
    let sourceID = SourceConfiguration.ID()

    switch input.credential {
    case .replace(let username, let secret):
      let reference = CredentialReference()
      let credential = try makeCredential(username: username, secret: secret)
      do {
        try await credentialStore.store(credential, for: reference)
      } catch {
        throw SourceManagementError.secureStorageFailure
      }
      let source = input.configuration(id: sourceID, credentialReference: reference)
      do {
        try await sourceRepository.create(source)
        return source
      } catch {
        do {
          try await credentialStore.deleteCredential(for: reference)
        } catch {
          throw SourceManagementError.compensationFailure
        }
        throw SourceManagementError.persistenceFailure
      }

    case .none:
      let source = input.configuration(id: sourceID, credentialReference: nil)
      do {
        try await sourceRepository.create(source)
        return source
      } catch {
        throw SourceManagementError.persistenceFailure
      }

    case .unchanged:
      throw SourceManagementError.invalidInput([
        SourceValidationIssue(field: .credential, reason: .credentialReplacementRequired)
      ])
    }
  }

  public func updateSource(
    id: SourceConfiguration.ID,
    from draft: SourceDraft
  ) async throws -> SourceConfiguration {
    guard let existing = try await repositorySource(id) else {
      throw SourceManagementError.sourceNotFound
    }
    let input = try validatedInput(draft, existing: existing)

    switch input.credential {
    case .unchanged:
      let updated = input.configuration(
        id: existing.id,
        credentialReference: existing.credentialReference
      )
      do {
        try await sourceRepository.update(updated)
        return updated
      } catch {
        throw SourceManagementError.persistenceFailure
      }

    case .replace(let username, let secret):
      guard let reference = existing.credentialReference else {
        throw SourceManagementError.credentialUnavailable
      }
      let previous: SourceCredential
      do {
        guard let credential = try await credentialStore.credential(for: reference) else {
          throw SourceManagementError.credentialUnavailable
        }
        previous = credential
        try await credentialStore.update(
          makeCredential(username: username, secret: secret),
          for: reference
        )
      } catch let error as SourceManagementError {
        throw error
      } catch {
        throw SourceManagementError.secureStorageFailure
      }

      let updated = input.configuration(id: existing.id, credentialReference: reference)
      do {
        try await sourceRepository.update(updated)
        return updated
      } catch {
        do {
          try await credentialStore.update(previous, for: reference)
        } catch {
          throw SourceManagementError.compensationFailure
        }
        throw SourceManagementError.persistenceFailure
      }

    case .none:
      let updated = input.configuration(id: existing.id, credentialReference: nil)
      do {
        try await sourceRepository.update(updated)
        return updated
      } catch {
        throw SourceManagementError.persistenceFailure
      }
    }
  }

  public func deleteSource(id: SourceConfiguration.ID) async throws {
    guard let existing = try await repositorySource(id) else {
      throw SourceManagementError.sourceNotFound
    }

    let savedCredential: SourceCredential?
    do {
      if let reference = existing.credentialReference {
        guard let credential = try await credentialStore.credential(for: reference) else {
          throw SourceManagementError.credentialUnavailable
        }
        savedCredential = credential
      } else {
        savedCredential = nil
      }
    } catch let error as SourceManagementError {
      throw error
    } catch {
      throw SourceManagementError.credentialUnavailable
    }

    do {
      try Task.checkCancellation()
      try await sourceRepository.delete(id: id)
    } catch {
      throw SourceManagementError.persistenceFailure
    }

    if let reference = existing.credentialReference {
      do {
        try await credentialStore.deleteCredential(for: reference)
      } catch {
        do {
          try await sourceRepository.create(existing)
        } catch {
          throw SourceManagementError.compensationFailure
        }
        throw SourceManagementError.cleanupFailure
      }
    }

    do {
      try await catalogRepository.deleteCatalog(sourceID: id)
    } catch {
      var restorationFailed = false
      if let reference = existing.credentialReference, let savedCredential {
        do {
          try await credentialStore.store(savedCredential, for: reference)
        } catch {
          restorationFailed = true
        }
      }
      do {
        try await sourceRepository.create(existing)
      } catch {
        restorationFailed = true
      }
      if restorationFailed {
        throw SourceManagementError.compensationFailure
      }
      throw SourceManagementError.cleanupFailure
    }
  }

  public func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async throws {
    do {
      try await sourceRepository.setEnabled(isEnabled, id: id)
    } catch let error as SourceRepositoryError where error == .sourceNotFound {
      throw SourceManagementError.sourceNotFound
    } catch {
      throw SourceManagementError.persistenceFailure
    }
  }

  public func testConnection(
    _ draft: SourceDraft,
    editing sourceID: SourceConfiguration.ID? = nil
  ) async throws -> SourceConnectionReport {
    let existing = await existingSource(editingSourceID: sourceID)
    let input = try validatedInput(draft, existing: existing)
    let validationID = existing?.id ?? SourceConfiguration.ID()

    switch input.kind {
    case .xtreamCompatible:
      switch input.credential {
      case .replace(let username, let secret):
        let reference = CredentialReference()
        let credential = try makeCredential(username: username, secret: secret)
        do {
          try await credentialStore.store(credential, for: reference)
        } catch {
          throw SourceManagementError.secureStorageFailure
        }
        let temporarySource = input.configuration(
          id: validationID,
          credentialReference: reference,
          forceEnabled: true
        )
        do {
          _ = try await providerAdapter.discover(source: temporarySource)
          try await cleanupTemporaryCredential(reference)
          return SourceConnectionReport(kind: .xtreamCompatible)
        } catch {
          let originalError = error
          do {
            try await cleanupTemporaryCredential(reference)
          } catch {
            throw SourceManagementError.cleanupFailure
          }
          throw Self.mapConnectionError(originalError)
        }

      case .unchanged:
        guard let reference = existing?.credentialReference else {
          throw SourceManagementError.credentialUnavailable
        }
        let source = input.configuration(
          id: validationID,
          credentialReference: reference,
          forceEnabled: true
        )
        do {
          _ = try await providerAdapter.discover(source: source)
          return SourceConnectionReport(kind: .xtreamCompatible)
        } catch {
          throw Self.mapConnectionError(error)
        }

      case .none:
        throw SourceManagementError.credentialUnavailable
      }

    case .m3u:
      let source = input.configuration(
        id: validationID,
        credentialReference: nil,
        forceEnabled: true
      )
      do {
        let data = try await m3uAcquisition.acquire(from: source)
        _ = try await m3uParser.parse(lines: M3UDataLineSequence(data: data)) { _ in }
        return SourceConnectionReport(kind: .m3u)
      } catch {
        throw Self.mapConnectionError(error)
      }
    }
  }

  public func refreshNow(
    id: SourceConfiguration.ID,
    onStage: CatalogRefreshStageHandler? = nil
  ) async throws -> CatalogRefreshReport {
    guard let source = try await repositorySource(id) else {
      throw SourceManagementError.sourceNotFound
    }
    do {
      return try await refreshService.refresh(source, onStage: onStage)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as CatalogRefreshError {
      throw Self.mapRefreshError(error)
    } catch {
      throw SourceManagementError.persistenceFailure
    }
  }

  private func existingSource(_ id: SourceConfiguration.ID) async -> SourceConfiguration? {
    do { return try await sourceRepository.source(id: id) } catch { return nil }
  }

  private func repositorySource(_ id: SourceConfiguration.ID) async throws -> SourceConfiguration? {
    do {
      return try await sourceRepository.source(id: id)
    } catch {
      throw SourceManagementError.persistenceFailure
    }
  }

  private func existingSource(editingSourceID: SourceConfiguration.ID?) async
    -> SourceConfiguration?
  {
    guard let editingSourceID else { return nil }
    return await existingSource(editingSourceID)
  }

  private func validatedInput(
    _ draft: SourceDraft,
    existing: SourceConfiguration?
  ) throws -> ValidatedSourceInput {
    let issues = Self.validationIssues(for: draft, existing: existing)
    guard issues.isEmpty else { throw SourceManagementError.invalidInput(issues) }

    let endpointText = draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: endpointText), let endpoint = try? SourceEndpoint(url: url) else {
      throw SourceManagementError.invalidInput([
        SourceValidationIssue(field: .endpoint, reason: .invalidURL)
      ])
    }
    return ValidatedSourceInput(
      displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: draft.kind,
      endpoint: endpoint,
      isEnabled: draft.isEnabled,
      refreshPolicy: draft.refreshPolicy,
      credential: draft.credential
    )
  }

  private func makeCredential(username: String, secret: String) throws -> SourceCredential {
    do {
      return try SourceCredential(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
        secret: secret,
        secretKind: .password
      )
    } catch {
      throw SourceManagementError.invalidInput([
        SourceValidationIssue(field: .credential, reason: .required)
      ])
    }
  }

  private func cleanupTemporaryCredential(_ reference: CredentialReference) async throws {
    do {
      try await credentialStore.deleteCredential(for: reference)
    } catch {
      throw SourceManagementError.cleanupFailure
    }
  }
}

extension SourceManagementService {
  private static func validationIssues(
    for draft: SourceDraft,
    existing: SourceConfiguration?
  ) -> [SourceValidationIssue] {
    var issues: [SourceValidationIssue] = []
    let displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    if displayName.isEmpty {
      issues.append(.init(field: .displayName, reason: .required))
    } else if displayName.utf8.count > maximumDisplayNameLength {
      issues.append(.init(field: .displayName, reason: .tooLong))
    }

    if let existing, existing.kind != draft.kind {
      issues.append(.init(field: .sourceKind, reason: .sourceKindCannotChange))
    }

    let endpointText = draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    if endpointText.isEmpty {
      issues.append(.init(field: .endpoint, reason: .required))
    } else if endpointText.utf8.count > maximumEndpointLength {
      issues.append(.init(field: .endpoint, reason: .tooLong))
    } else if let components = URLComponents(string: endpointText) {
      if components.scheme?.lowercased() != "http" && components.scheme?.lowercased() != "https" {
        issues.append(.init(field: .endpoint, reason: .unsupportedScheme))
      } else if components.host?.isEmpty != false {
        issues.append(.init(field: .endpoint, reason: .missingHost))
      }
      if components.user != nil || components.password != nil || components.query != nil
        || components.fragment != nil
      {
        issues.append(.init(field: .endpoint, reason: .forbiddenURLComponents))
      }
    } else {
      issues.append(.init(field: .endpoint, reason: .invalidURL))
    }

    switch (draft.kind, draft.credential) {
    case (.xtreamCompatible, .replace(let username, let secret)):
      let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedUsername.isEmpty {
        issues.append(.init(field: .username, reason: .required))
      } else if trimmedUsername.utf8.count > maximumUsernameLength {
        issues.append(.init(field: .username, reason: .tooLong))
      }
      if secret.isEmpty {
        issues.append(.init(field: .credential, reason: .required))
      } else if secret.utf8.count > maximumSecretLength {
        issues.append(.init(field: .credential, reason: .tooLong))
      }
    case (.xtreamCompatible, .unchanged):
      if existing?.credentialReference == nil {
        issues.append(.init(field: .credential, reason: .credentialReplacementRequired))
      }
    case (.xtreamCompatible, .none):
      issues.append(.init(field: .credential, reason: .credentialReplacementRequired))
    case (.m3u, .none):
      break
    case (.m3u, .unchanged):
      if existing == nil {
        issues.append(.init(field: .credential, reason: .credentialReplacementRequired))
      }
    case (.m3u, .replace):
      issues.append(.init(field: .credential, reason: .credentialReplacementRequired))
    }
    return issues
  }

  private static func mapConnectionError(_ error: any Error) -> any Error {
    if error is CancellationError { return CancellationError() }
    if let error = error as? ProviderAdapterError {
      switch error {
      case .invalidSourceConfiguration: return SourceManagementError.invalidInput([])
      case .credentialUnavailable: return SourceManagementError.credentialUnavailable
      case .authenticationRejected: return SourceManagementError.authenticationRejected
      case .timedOut: return SourceManagementError.timeout
      case .transportUnavailable, .httpError: return SourceManagementError.unreachableProvider
      case .malformedResponse, .providerResponseInvalid:
        return SourceManagementError.malformedSource
      }
    }
    if let error = error as? M3UAcquisitionError {
      switch error {
      case .invalidSourceConfiguration: return SourceManagementError.invalidInput([])
      case .authenticationRejected: return SourceManagementError.authenticationRejected
      case .timedOut: return SourceManagementError.timeout
      case .transportUnavailable, .httpError: return SourceManagementError.unreachableProvider
      case .emptyResponse, .responseTooLarge, .unsafeRedirect:
        return SourceManagementError.malformedSource
      }
    }
    if error is M3UParserError { return SourceManagementError.malformedSource }
    return SourceManagementError.unreachableProvider
  }

  private static func mapRefreshError(_ error: CatalogRefreshError) -> SourceManagementError {
    switch error {
    case .invalidSource: .invalidInput([])
    case .credentialUnavailable: .credentialUnavailable
    case .authenticationRejected: .authenticationRejected
    case .networkFailure: .unreachableProvider
    case .timeout: .timeout
    case .malformedSource: .malformedSource
    case .persistenceFailure: .persistenceFailure
    case .inProgress: .inProgress
    }
  }
}

private struct ValidatedSourceInput {
  let displayName: String
  let kind: SourceKind
  let endpoint: SourceEndpoint
  let isEnabled: Bool
  let refreshPolicy: RefreshPolicy
  let credential: SourceDraft.CredentialInput

  func configuration(
    id: SourceConfiguration.ID,
    credentialReference: CredentialReference?,
    forceEnabled: Bool = false
  ) -> SourceConfiguration {
    SourceConfiguration(
      id: id,
      displayName: displayName,
      kind: kind,
      endpoint: endpoint,
      credentialReference: credentialReference,
      isEnabled: forceEnabled ? true : isEnabled,
      refreshPolicy: refreshPolicy
    )
  }
}
