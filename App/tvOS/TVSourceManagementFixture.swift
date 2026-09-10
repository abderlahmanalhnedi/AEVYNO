import Domain
import Foundation
import Library

actor TVSourceManagementFixture: SourceManaging, RefreshScheduling {
  private static let seededID = SourceConfiguration.ID(
    rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1))
  )

  private var sources: [ManagedSource]
  private let connectionFails: Bool

  nonisolated static func editorDraft(arguments: [String]) -> SourceDraft? {
    if arguments.contains("--ui-source-draft-xtream") {
      return SourceDraft(
        displayName: "Synthetic Source",
        kind: .xtreamCompatible,
        endpoint: "https://example.invalid/provider",
        isEnabled: true,
        credential: .replace(username: "synthetic-user", secret: "synthetic-secret")
      )
    }
    if arguments.contains("--ui-source-draft-m3u") {
      return SourceDraft(
        displayName: "Synthetic Playlist",
        kind: .m3u,
        endpoint: "https://example.invalid/playlist.m3u",
        isEnabled: true,
        credential: .none
      )
    }
    return nil
  }

  init(arguments: [String]) {
    connectionFails = arguments.contains("--ui-source-connection-failure")
    if arguments.contains("--ui-source-seeded"),
      let url = URL(string: "https://example.invalid/provider"),
      let endpoint = try? SourceEndpoint(url: url)
    {
      let policy: RefreshPolicy =
        if arguments.contains("--ui-source-policy-6h") {
          .automatic(.every6Hours)
        } else if arguments.contains("--ui-source-policy-12h") {
          .automatic(.every12Hours)
        } else if arguments.contains("--ui-source-policy-daily") {
          .automatic(.daily)
        } else {
          .manualOnly
        }
      sources = [
        ManagedSource(
          configuration: SourceConfiguration(
            id: Self.seededID,
            displayName: "Demo Source",
            kind: .xtreamCompatible,
            endpoint: endpoint,
            credentialReference: CredentialReference(
              rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1))),
            isEnabled: !arguments.contains("--ui-source-disabled"),
            refreshPolicy: policy
          ),
          refreshMetadata: nil
        )
      ]
    } else {
      sources = []
    }
  }

  func listSources() async throws -> [ManagedSource] { sources }

  func source(id: SourceConfiguration.ID) async throws -> ManagedSource? {
    sources.first { $0.id == id }
  }

  func validateDraft(_ draft: SourceDraft, editing sourceID: SourceConfiguration.ID?) async
    -> [SourceValidationIssue]
  {
    var issues: [SourceValidationIssue] = []
    if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(field: .displayName, reason: .required))
    }
    guard let components = URLComponents(string: draft.endpoint),
      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
      components.host?.isEmpty == false,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil
    else {
      issues.append(.init(field: .endpoint, reason: .invalidURL))
      return issues
    }
    if draft.kind == .xtreamCompatible,
      case .replace(let username, let secret) = draft.credential
    {
      if username.isEmpty { issues.append(.init(field: .username, reason: .required)) }
      if secret.isEmpty { issues.append(.init(field: .credential, reason: .required)) }
    }
    return issues
  }

  func createSource(from draft: SourceDraft) async throws -> SourceConfiguration {
    let id = SourceConfiguration.ID(
      rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2))
    )
    let configuration = try configuration(id: id, draft: draft, existingReference: nil)
    sources.append(ManagedSource(configuration: configuration, refreshMetadata: nil))
    return configuration
  }

  func updateSource(id: SourceConfiguration.ID, from draft: SourceDraft) async throws
    -> SourceConfiguration
  {
    guard let index = sources.firstIndex(where: { $0.id == id }) else {
      throw SourceManagementError.sourceNotFound
    }
    let updated = try configuration(
      id: id,
      draft: draft,
      existingReference: sources[index].configuration.credentialReference
    )
    sources[index] = ManagedSource(
      configuration: updated,
      refreshMetadata: sources[index].refreshMetadata
    )
    return updated
  }

  func deleteSource(id: SourceConfiguration.ID) async throws {
    sources.removeAll { $0.id == id }
  }

  func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async throws {
    guard let index = sources.firstIndex(where: { $0.id == id }) else {
      throw SourceManagementError.sourceNotFound
    }
    let source = sources[index]
    let configuration = source.configuration
    sources[index] = ManagedSource(
      configuration: SourceConfiguration(
        id: configuration.id,
        displayName: configuration.displayName,
        kind: configuration.kind,
        endpoint: configuration.endpoint,
        credentialReference: configuration.credentialReference,
        isEnabled: isEnabled,
        refreshPolicy: configuration.refreshPolicy
      ),
      refreshMetadata: source.refreshMetadata
    )
  }

  func testConnection(
    _ draft: SourceDraft,
    editing sourceID: SourceConfiguration.ID?
  ) async throws -> SourceConnectionReport {
    if connectionFails { throw SourceManagementError.authenticationRejected }
    return SourceConnectionReport(kind: draft.kind)
  }

  func refreshNow(
    id: SourceConfiguration.ID,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> CatalogRefreshReport {
    await onStage?(.validating)
    await onStage?(.acquiring)
    await onStage?(.committing)
    await onStage?(.completed)
    return CatalogRefreshReport(sourceID: id, committedItemCount: 12, completedAt: Date())
  }

  func evaluateAndRefreshDueSources() async throws -> RefreshSchedulingCycleReport {
    RefreshSchedulingCycleReport(outcomes: [], nextEligibleAt: nil)
  }

  func nextEligibleDate() async throws -> Date? { nil }

  private func configuration(
    id: SourceConfiguration.ID,
    draft: SourceDraft,
    existingReference: CredentialReference?
  ) throws -> SourceConfiguration {
    guard let url = URL(string: draft.endpoint) else {
      throw SourceManagementError.invalidInput([
        SourceValidationIssue(field: .endpoint, reason: .invalidURL)
      ])
    }
    let endpoint = try SourceEndpoint(url: url)
    let reference =
      draft.kind == .xtreamCompatible ? (existingReference ?? CredentialReference()) : nil
    return SourceConfiguration(
      id: id,
      displayName: draft.displayName,
      kind: draft.kind,
      endpoint: endpoint,
      credentialReference: reference,
      isEnabled: draft.isEnabled,
      refreshPolicy: draft.refreshPolicy
    )
  }
}
