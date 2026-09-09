import AEVYNOSecurity
import Domain
import Foundation
import IPTVCore
import Library
import Persistence
import Testing

@Suite("Source management and validation", .serialized)
struct SourceManagementServiceTests {
  @Test("Source registry persists deterministic CRUD order and enabled state across reopen")
  func sourceRegistryCRUDAndReopen() async throws {
    let fixture = try SourceRegistryFixture()
    defer { try? fixture.remove() }
    let repository = FileSourceRepository(url: fixture.url)
    let first = try makeM3USource(name: "First")
    let second = try makeXtreamSource(name: "Second")

    try await repository.create(first)
    try await repository.create(second)
    try await repository.setEnabled(false, id: first.id)
    let renamed = SourceConfiguration(
      id: second.id,
      displayName: "Renamed",
      kind: second.kind,
      endpoint: second.endpoint,
      credentialReference: second.credentialReference,
      isEnabled: second.isEnabled
    )
    try await repository.update(renamed)

    let reopened = FileSourceRepository(url: fixture.url)
    let sources = try await reopened.listSources()
    #expect(sources.map(\.id) == [first.id, second.id])
    #expect(sources.map(\.displayName) == ["First", "Renamed"])
    #expect(sources.first?.isEnabled == false)
    try await reopened.delete(id: first.id)
    #expect(try await reopened.listSources().map(\.id) == [second.id])
  }

  @Test("Malformed and unsupported source registries fail without destructive reset")
  func malformedRegistryIsPreserved() async throws {
    let fixture = try SourceRegistryFixture()
    defer { try? fixture.remove() }
    let malformed = Data("not-json-synthetic".utf8)
    try malformed.write(to: fixture.url)
    let repository = FileSourceRepository(url: fixture.url)
    await #expect(throws: SourceRepositoryError.corruptedStore) {
      _ = try await repository.listSources()
    }
    #expect(try Data(contentsOf: fixture.url) == malformed)

    let unsupported = Data("{\"schemaVersion\":99,\"sources\":[]}".utf8)
    try unsupported.write(to: fixture.url, options: .atomic)
    let unsupportedRepository = FileSourceRepository(url: fixture.url)
    await #expect(throws: SourceRepositoryError.unsupportedSchema) {
      _ = try await unsupportedRepository.listSources()
    }
    #expect(try Data(contentsOf: fixture.url) == unsupported)
  }

  @Test("Local validation returns field-safe errors and keeps M3U query URLs unsupported")
  func localValidation() async throws {
    let context = makeContext()
    let issues = await context.service.validateDraft(
      SourceDraft(
        displayName: " ",
        kind: .xtreamCompatible,
        endpoint: "ftp://user:secret@example.invalid/list?token=secret#fragment",
        credential: .replace(username: "", secret: "")
      ),
      editing: nil
    )
    #expect(issues.contains(.init(field: .displayName, reason: .required)))
    #expect(issues.contains(.init(field: .endpoint, reason: .unsupportedScheme)))
    #expect(issues.contains(.init(field: .endpoint, reason: .forbiddenURLComponents)))
    #expect(issues.contains(.init(field: .username, reason: .required)))
    #expect(issues.contains(.init(field: .credential, reason: .required)))
    #expect(!String(describing: issues).contains("secret"))

    let m3uIssues = await context.service.validateDraft(
      SourceDraft(
        displayName: "Playlist",
        kind: .m3u,
        endpoint: "https://example.invalid/list.m3u?token=synthetic",
        credential: .none
      ),
      editing: nil
    )
    #expect(m3uIssues == [.init(field: .endpoint, reason: .forbiddenURLComponents)])
  }

  @Test("Xtream create stores only a credential reference and list returns the source")
  func createAndListXtreamSource() async throws {
    let context = makeContext()
    let draft = xtreamDraft(secret: "synthetic-private-password")

    let created = try await context.service.createSource(from: draft)

    #expect(created.displayName == "Synthetic Provider")
    let reference = try #require(created.credentialReference)
    #expect(await context.credentials.value(reference)?.secret == "synthetic-private-password")
    #expect(try await context.service.listSources().map(\.id) == [created.id])
    #expect(!String(describing: created).contains("synthetic-private-password"))
  }

  @Test("Create compensates metadata failure and does not persist after Keychain failure")
  func createCompensation() async throws {
    let metadataFailure = makeContext(sourceFailure: .create)
    await #expect(throws: SourceManagementError.persistenceFailure) {
      try await metadataFailure.service.createSource(from: xtreamDraft())
    }
    #expect(await metadataFailure.credentials.count == 0)
    #expect(await metadataFailure.credentials.deleteCallCount == 1)
    #expect(await metadataFailure.sources.values.isEmpty)

    let keychainFailure = makeContext(credentialFailure: .store)
    await #expect(throws: SourceManagementError.secureStorageFailure) {
      try await keychainFailure.service.createSource(from: xtreamDraft())
    }
    #expect(await keychainFailure.sources.values.isEmpty)
    #expect(await keychainFailure.credentials.count == 0)
  }

  @Test("Edit preserves identity, skips unchanged credentials, and rolls replacement back")
  func editIdentityAndCredentialLifecycle() async throws {
    let context = makeContext()
    let created = try await context.service.createSource(from: xtreamDraft(secret: "old-secret"))
    let reference = try #require(created.credentialReference)
    let writesAfterCreate = await context.credentials.writeCallCount

    let renamed = try await context.service.updateSource(
      id: created.id,
      from: SourceDraft(
        displayName: "Renamed Provider",
        kind: .xtreamCompatible,
        endpoint: "https://example.invalid/new-path",
        credential: .unchanged
      )
    )
    #expect(renamed.id == created.id)
    #expect(await context.credentials.writeCallCount == writesAfterCreate)

    let replaced = try await context.service.updateSource(
      id: created.id,
      from: xtreamDraft(secret: "current-secret")
    )
    #expect(replaced.id == created.id)
    #expect(replaced.credentialReference == reference)
    #expect(await context.credentials.value(reference)?.secret == "current-secret")

    await context.sources.setFailure(.update)
    await #expect(throws: SourceManagementError.persistenceFailure) {
      try await context.service.updateSource(
        id: created.id,
        from: xtreamDraft(secret: "replacement-secret")
      )
    }
    #expect(await context.credentials.value(reference)?.secret == "current-secret")
    #expect(await context.sources.values.first?.displayName == "Synthetic Provider")
  }

  @Test("Temporary Xtream validation cleans credentials for every terminal outcome")
  func temporaryCredentialCleanup() async throws {
    let outcomes: [(ManagementProviderAdapter.Behavior, SourceManagementError?)] = [
      (.success, nil),
      (.failure(.authenticationRejected), .authenticationRejected),
      (.failure(.transportUnavailable), .unreachableProvider),
      (.failure(.timedOut), .timeout),
      (.failure(.malformedResponse), .malformedSource),
    ]

    for (behavior, expected) in outcomes {
      let context = makeContext(providerBehavior: behavior)
      do {
        _ = try await context.service.testConnection(xtreamDraft(), editing: nil)
        #expect(expected == nil)
      } catch let error as SourceManagementError {
        #expect(error == expected)
      }
      #expect(await context.credentials.count == 0)
      #expect(await context.credentials.deleteCallCount == 1)
      #expect(await context.catalog.beginCount == 0)
    }

    let cancelled = makeContext(providerBehavior: .cancelled)
    await #expect(throws: CancellationError.self) {
      try await cancelled.service.testConnection(xtreamDraft(), editing: nil)
    }
    #expect(await cancelled.credentials.count == 0)
    #expect(await cancelled.credentials.deleteCallCount == 1)
  }

  @Test("M3U connection testing parses without staging or committing catalog data")
  func m3uConnectionValidation() async throws {
    let validData = Data(
      "#EXTM3U\n#EXTINF:-1,Synthetic\nhttps://example.invalid/live.ts\n".utf8)
    let valid = makeContext(m3uBehavior: .response(status: 200, data: validData))
    let report = try await valid.service.testConnection(m3uDraft(), editing: nil)
    #expect(report.kind == .m3u)
    #expect(await valid.catalog.beginCount == 0)

    let malformedData = Data("#EXTM3U\nnot-a-url\n".utf8)
    let malformed = makeContext(m3uBehavior: .response(status: 200, data: malformedData))
    await #expect(throws: SourceManagementError.malformedSource) {
      try await malformed.service.testConnection(m3uDraft(), editing: nil)
    }

    let unavailable = makeContext(m3uBehavior: .failure(URLError(.cannotConnectToHost)))
    await #expect(throws: SourceManagementError.unreachableProvider) {
      try await unavailable.service.testConnection(m3uDraft(), editing: nil)
    }
  }

  @Test("Enable and disable preserve identity, credential, and committed catalog")
  func enabledStatePreservesOwnedData() async throws {
    let context = makeContext()
    let created = try await context.service.createSource(from: xtreamDraft())
    let reference = try #require(created.credentialReference)

    try await context.service.setEnabled(false, id: created.id)
    #expect(try await context.service.source(id: created.id)?.configuration.isEnabled == false)
    #expect(await context.credentials.value(reference) != nil)
    #expect(await context.catalog.deleteCallCount == 0)

    try await context.service.setEnabled(true, id: created.id)
    #expect(try await context.service.source(id: created.id)?.configuration.isEnabled == true)
    #expect(try await context.service.source(id: created.id)?.configuration.id == created.id)
  }

  @Test("Delete removes source-owned state last and leaves an unrelated source untouched")
  func deleteSuccess() async throws {
    let context = makeContext()
    let first = try await context.service.createSource(from: xtreamDraft(name: "First"))
    let second = try await context.service.createSource(from: xtreamDraft(name: "Second"))
    let firstReference = try #require(first.credentialReference)
    let secondReference = try #require(second.credentialReference)
    await context.catalog.seedOwnedData(for: first.id)
    await context.catalog.seedOwnedData(for: second.id)
    await context.operations.reset()

    try await context.service.deleteSource(id: first.id)

    #expect(
      await context.operations.values == [
        .sourceRead, .credentialRead, .sourceDelete, .credentialDelete, .catalogDelete,
      ])
    #expect(try await context.service.listSources().map(\.id) == [second.id])
    #expect(await context.credentials.value(firstReference) == nil)
    #expect(await context.credentials.value(secondReference) != nil)
    #expect(await context.catalog.containsCatalog(for: first.id) == false)
    #expect(await context.catalog.metadataValue(for: first.id) == nil)
    #expect(await context.catalog.containsCatalog(for: second.id))
    #expect(await context.catalog.metadataValue(for: second.id) != nil)
  }

  @Test("Source metadata delete failure leaves every owned store unchanged")
  func sourceDeleteFailure() async throws {
    let context = makeContext()
    let source = try await context.service.createSource(from: xtreamDraft())
    let unrelated = try await context.service.createSource(from: xtreamDraft(name: "Unrelated"))
    let reference = try #require(source.credentialReference)
    let unrelatedReference = try #require(unrelated.credentialReference)
    await context.catalog.seedOwnedData(for: source.id)
    await context.catalog.seedOwnedData(for: unrelated.id)
    await context.sources.setFailure(.delete)
    await context.operations.reset()

    await #expect(throws: SourceManagementError.persistenceFailure) {
      try await context.service.deleteSource(id: source.id)
    }
    #expect(await context.operations.values == [.sourceRead, .credentialRead, .sourceDelete])
    #expect(await context.sources.values == [source, unrelated])
    #expect(await context.credentials.value(reference) != nil)
    #expect(await context.credentials.value(unrelatedReference) != nil)
    #expect(await context.catalog.containsCatalog(for: source.id))
    #expect(await context.catalog.metadataValue(for: source.id) != nil)
    #expect(await context.catalog.containsCatalog(for: unrelated.id))
    #expect(await context.catalog.metadataValue(for: unrelated.id) != nil)
  }

  @Test("Credential delete failure restores source metadata without touching catalog state")
  func credentialDeleteFailure() async throws {
    let context = makeContext(credentialFailure: .delete)
    let source = try await context.service.createSource(from: xtreamDraft())
    let reference = try #require(source.credentialReference)
    await context.catalog.seedOwnedData(for: source.id)
    await context.operations.reset()

    await #expect(throws: SourceManagementError.cleanupFailure) {
      try await context.service.deleteSource(id: source.id)
    }
    #expect(
      await context.operations.values == [
        .sourceRead, .credentialRead, .sourceDelete, .credentialDelete, .sourceCreate,
      ])
    #expect(await context.sources.values == [source])
    #expect(await context.credentials.value(reference) != nil)
    #expect(await context.catalog.containsCatalog(for: source.id))
    #expect(await context.catalog.metadataValue(for: source.id) != nil)
  }

  @Test("Catalog delete failure restores credentials and source metadata")
  func catalogDeleteFailure() async throws {
    let context = makeContext(catalogDeleteBehavior: .failure)
    let source = try await context.service.createSource(from: xtreamDraft())
    let reference = try #require(source.credentialReference)
    await context.catalog.seedOwnedData(for: source.id)
    await context.operations.reset()

    await #expect(throws: SourceManagementError.cleanupFailure) {
      try await context.service.deleteSource(id: source.id)
    }
    #expect(
      await context.operations.values == [
        .sourceRead, .credentialRead, .sourceDelete, .credentialDelete, .catalogDelete,
        .credentialStore, .sourceCreate,
      ])
    #expect(await context.sources.values == [source])
    #expect(await context.credentials.value(reference) != nil)
    #expect(await context.catalog.containsCatalog(for: source.id))
    #expect(await context.catalog.metadataValue(for: source.id) != nil)
  }

  @Test("A failed delete restoration is reported as a compensation failure")
  func deleteCompensationFailure() async throws {
    let context = makeContext(catalogDeleteBehavior: .failure)
    let source = try await context.service.createSource(from: xtreamDraft())
    await context.catalog.seedOwnedData(for: source.id)
    await context.sources.setFailure(.create)
    await context.operations.reset()

    await #expect(throws: SourceManagementError.compensationFailure) {
      try await context.service.deleteSource(id: source.id)
    }
    #expect(await context.catalog.containsCatalog(for: source.id))
    #expect(await context.catalog.metadataValue(for: source.id) != nil)
  }

  @Test("Credential-free source deletion skips Keychain and still deletes catalog last")
  func deleteSourceWithoutCredential() async throws {
    let context = makeContext()
    let source = try await context.service.createSource(from: m3uDraft())
    await context.catalog.seedOwnedData(for: source.id)
    await context.operations.reset()

    try await context.service.deleteSource(id: source.id)

    #expect(await context.operations.values == [.sourceRead, .sourceDelete, .catalogDelete])
    #expect(await context.credentials.readCallCount == 0)
    #expect(await context.credentials.deleteCallCount == 0)
    #expect(await context.sources.values.isEmpty)
    #expect(await context.catalog.containsCatalog(for: source.id) == false)
    #expect(await context.catalog.metadataValue(for: source.id) == nil)
  }

  @Test("Cancellation at final catalog cleanup restores earlier deletions")
  func deleteCancellationCompensates() async throws {
    let context = makeContext(catalogDeleteBehavior: .cancelled)
    let source = try await context.service.createSource(from: xtreamDraft())
    let reference = try #require(source.credentialReference)
    await context.catalog.seedOwnedData(for: source.id)

    await #expect(throws: SourceManagementError.cleanupFailure) {
      try await context.service.deleteSource(id: source.id)
    }
    #expect(await context.sources.values == [source])
    #expect(await context.credentials.value(reference) != nil)
    #expect(await context.catalog.containsCatalog(for: source.id))
    #expect(await context.catalog.metadataValue(for: source.id) != nil)
  }

  @Test("Manual refresh delegates to durable refresh and exposes lifecycle stages")
  func refreshNowDelegation() async throws {
    let body = Data("#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one.ts\n".utf8)
    let context = makeContext(m3uBehavior: .response(status: 200, data: body))
    let source = try await context.service.createSource(from: m3uDraft())
    let recorder = ManagementStageRecorder()

    let report = try await context.service.refreshNow(id: source.id) { stage in
      await recorder.record(stage)
    }

    #expect(report.sourceID == source.id)
    #expect(report.committedItemCount == 1)
    #expect(
      await recorder.values == [
        .validating, .acquiring, .parsingOrDecoding, .staging, .committing, .completed,
      ])
    #expect(await context.catalog.beginCount == 1)
  }
}

private enum ManagementOperation: Equatable, Sendable {
  case sourceRead
  case sourceCreate
  case sourceDelete
  case credentialRead
  case credentialStore
  case credentialDelete
  case catalogDelete
}

private actor ManagementOperationRecorder {
  private(set) var values: [ManagementOperation] = []

  func record(_ operation: ManagementOperation) {
    values.append(operation)
  }

  func reset() {
    values = []
  }
}

private struct ManagementContext {
  let service: SourceManagementService
  let sources: ManagementSourceRepository
  let credentials: ManagementCredentialStore
  let catalog: ManagementCatalogRepository
  let operations: ManagementOperationRecorder
}

private func makeContext(
  sourceFailure: ManagementSourceRepository.Operation? = nil,
  credentialFailure: ManagementCredentialStore.Operation? = nil,
  providerBehavior: ManagementProviderAdapter.Behavior = .success,
  m3uBehavior: ManagementM3UTransport.Behavior = .response(
    status: 200,
    data: Data("#EXTM3U\nhttps://example.invalid/default.ts\n".utf8)
  ),
  catalogDeleteBehavior: ManagementCatalogRepository.DeleteBehavior = .success
) -> ManagementContext {
  let operations = ManagementOperationRecorder()
  let sources = ManagementSourceRepository(failure: sourceFailure, operations: operations)
  let credentials = ManagementCredentialStore(failure: credentialFailure, operations: operations)
  let catalog = ManagementCatalogRepository(
    deleteBehavior: catalogDeleteBehavior,
    operations: operations
  )
  let provider = ManagementProviderAdapter(behavior: providerBehavior)
  let acquisition = M3UAcquisitionService(transport: ManagementM3UTransport(behavior: m3uBehavior))
  let refresh = CatalogRefreshService(
    repository: catalog,
    m3uAcquisition: acquisition,
    providerAdapter: provider
  )
  let service = SourceManagementService(
    sourceRepository: sources,
    credentialStore: credentials,
    catalogRepository: catalog,
    providerAdapter: provider,
    m3uAcquisition: acquisition,
    refreshService: refresh
  )
  return ManagementContext(
    service: service,
    sources: sources,
    credentials: credentials,
    catalog: catalog,
    operations: operations
  )
}

private func xtreamDraft(
  name: String = "Synthetic Provider",
  secret: String = "synthetic-secret"
) -> SourceDraft {
  SourceDraft(
    displayName: name,
    kind: .xtreamCompatible,
    endpoint: "https://example.invalid/provider",
    credential: .replace(username: "synthetic-user", secret: secret)
  )
}

private func m3uDraft() -> SourceDraft {
  SourceDraft(
    displayName: "Synthetic Playlist",
    kind: .m3u,
    endpoint: "https://example.invalid/list.m3u",
    credential: .none
  )
}

private func makeM3USource(name: String) throws -> SourceConfiguration {
  SourceConfiguration(
    displayName: name,
    kind: .m3u,
    endpoint: try SourceEndpoint(url: #require(URL(string: "https://example.invalid/list.m3u")))
  )
}

private func makeXtreamSource(name: String) throws -> SourceConfiguration {
  SourceConfiguration(
    displayName: name,
    kind: .xtreamCompatible,
    endpoint: try SourceEndpoint(url: #require(URL(string: "https://example.invalid/provider"))),
    credentialReference: CredentialReference()
  )
}

private struct SourceRegistryFixture {
  let directory: URL
  let url: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "aevyno-source-registry-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    url = directory.appendingPathComponent("sources.json")
  }

  func remove() throws {
    try FileManager.default.removeItem(at: directory)
  }
}

private actor ManagementSourceRepository: SourceRepository {
  enum Operation: Sendable { case create, update, delete, setEnabled, read }

  private(set) var values: [SourceConfiguration] = []
  private var failure: Operation?
  private let operations: ManagementOperationRecorder

  init(failure: Operation? = nil, operations: ManagementOperationRecorder) {
    self.failure = failure
    self.operations = operations
  }

  func setFailure(_ failure: Operation?) { self.failure = failure }

  func listSources() async throws -> [SourceConfiguration] {
    if failure == .read { throw SourceRepositoryError.unavailable }
    return values
  }

  func source(id: SourceConfiguration.ID) async throws -> SourceConfiguration? {
    await operations.record(.sourceRead)
    if failure == .read { throw SourceRepositoryError.unavailable }
    return values.first { $0.id == id }
  }

  func create(_ source: SourceConfiguration) async throws {
    await operations.record(.sourceCreate)
    if failure == .create { throw SourceRepositoryError.writeFailed }
    values.append(source)
  }

  func update(_ source: SourceConfiguration) async throws {
    if failure == .update { throw SourceRepositoryError.writeFailed }
    guard let index = values.firstIndex(where: { $0.id == source.id }) else {
      throw SourceRepositoryError.sourceNotFound
    }
    values[index] = source
  }

  func delete(id: SourceConfiguration.ID) async throws {
    await operations.record(.sourceDelete)
    if failure == .delete { throw SourceRepositoryError.writeFailed }
    values.removeAll { $0.id == id }
  }

  func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async throws {
    if failure == .setEnabled { throw SourceRepositoryError.writeFailed }
    guard let source = values.first(where: { $0.id == id }) else {
      throw SourceRepositoryError.sourceNotFound
    }
    try await update(
      SourceConfiguration(
        id: source.id,
        displayName: source.displayName,
        kind: source.kind,
        endpoint: source.endpoint,
        credentialReference: source.credentialReference,
        isEnabled: isEnabled
      )
    )
  }
}

private actor ManagementCredentialStore: CredentialStore {
  enum Operation: Sendable { case store, read, update, delete }

  private var storage: [CredentialReference: SourceCredential] = [:]
  private let failure: Operation?
  private let operations: ManagementOperationRecorder
  private(set) var writeCallCount = 0
  private(set) var readCallCount = 0
  private(set) var deleteCallCount = 0

  init(failure: Operation? = nil, operations: ManagementOperationRecorder) {
    self.failure = failure
    self.operations = operations
  }

  var count: Int { storage.count }
  func value(_ reference: CredentialReference) -> SourceCredential? { storage[reference] }

  func store(_ credential: SourceCredential, for reference: CredentialReference) async throws {
    await operations.record(.credentialStore)
    writeCallCount += 1
    if failure == .store { throw CredentialStoreError.unavailable }
    storage[reference] = credential
  }

  func credential(for reference: CredentialReference) async throws -> SourceCredential? {
    await operations.record(.credentialRead)
    readCallCount += 1
    if failure == .read { throw CredentialStoreError.unavailable }
    return storage[reference]
  }

  func update(_ credential: SourceCredential, for reference: CredentialReference) async throws {
    writeCallCount += 1
    if failure == .update { throw CredentialStoreError.unavailable }
    storage[reference] = credential
  }

  func deleteCredential(for reference: CredentialReference) async throws {
    await operations.record(.credentialDelete)
    deleteCallCount += 1
    if failure == .delete { throw CredentialStoreError.unavailable }
    storage[reference] = nil
  }
}

private actor ManagementCatalogRepository: CatalogRefreshRepository {
  enum DeleteBehavior: Sendable {
    case success
    case failure
    case cancelled
  }

  private(set) var beginCount = 0
  private(set) var deleteCallCount = 0
  private let deleteBehavior: DeleteBehavior
  private let operations: ManagementOperationRecorder
  private var stagedCounts: [UUID: Int] = [:]
  private var catalogSourceIDs: Set<SourceConfiguration.ID> = []
  private var metadata: [SourceConfiguration.ID: CatalogRefreshMetadata] = [:]

  init(deleteBehavior: DeleteBehavior, operations: ManagementOperationRecorder) {
    self.deleteBehavior = deleteBehavior
    self.operations = operations
  }

  func seedOwnedData(for sourceID: SourceConfiguration.ID) {
    catalogSourceIDs.insert(sourceID)
    metadata[sourceID] = CatalogRefreshMetadata(
      sourceID: sourceID,
      lastAttemptedAt: Date(timeIntervalSince1970: 1_000),
      lastSuccessfulAt: Date(timeIntervalSince1970: 1_000),
      lastCommittedItemCount: 1,
      lastResult: .success
    )
  }

  func containsCatalog(for sourceID: SourceConfiguration.ID) -> Bool {
    catalogSourceIDs.contains(sourceID)
  }

  func metadataValue(for sourceID: SourceConfiguration.ID) -> CatalogRefreshMetadata? {
    metadata[sourceID]
  }

  func beginStaging(in scope: CatalogScope) async throws -> UUID {
    try await beginStaging(in: [scope])
  }

  func beginStaging(in scopes: [CatalogScope]) async throws -> UUID {
    beginCount += 1
    let id = UUID()
    stagedCounts[id] = 0
    return id
  }

  func stage(
    items: [CatalogItem],
    categories: [CatalogCategory],
    in stagingID: UUID
  ) async throws {
    stagedCounts[stagingID, default: 0] += items.count
  }

  func commitStagedReplacement(_ stagingID: UUID) async throws {
    stagedCounts[stagingID] = nil
  }

  func commitStagedReplacement(
    _ stagingID: UUID,
    successfulRefresh refreshMetadata: CatalogRefreshMetadata
  ) async throws -> Int {
    let count = stagedCounts.removeValue(forKey: stagingID) ?? 0
    metadata[refreshMetadata.sourceID] = CatalogRefreshMetadata(
      sourceID: refreshMetadata.sourceID,
      lastAttemptedAt: refreshMetadata.lastAttemptedAt,
      lastSuccessfulAt: refreshMetadata.lastSuccessfulAt,
      lastCommittedItemCount: count,
      lastResult: .success
    )
    return count
  }

  func discardStaging(_ stagingID: UUID) async { stagedCounts[stagingID] = nil }

  func deleteCatalog(sourceID: SourceConfiguration.ID) async throws {
    await operations.record(.catalogDelete)
    deleteCallCount += 1
    switch deleteBehavior {
    case .success:
      break
    case .failure:
      throw CatalogStoreError.writeFailed
    case .cancelled:
      throw CancellationError()
    }
    catalogSourceIDs.remove(sourceID)
    metadata[sourceID] = nil
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

  func refreshMetadata(for sourceID: SourceConfiguration.ID) async throws
    -> CatalogRefreshMetadata?
  {
    metadata[sourceID]
  }
}

private struct ManagementProviderAdapter: ProviderAdapter {
  enum Behavior: Sendable {
    case success
    case failure(ProviderAdapterError)
    case cancelled
  }

  private let behavior: Behavior
  init(behavior: Behavior) { self.behavior = behavior }

  func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    switch behavior {
    case .success:
      return ProviderAccountSnapshot()
    case .failure(let error):
      throw error
    case .cancelled:
      throw CancellationError()
    }
  }

  func categories(
    for kind: ProviderMediaKind,
    source: SourceConfiguration
  ) async throws -> ProviderCategoryResult {
    ProviderCategoryResult(categories: [], receivedCount: 0, skippedCount: 0)
  }

  func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    ProviderCatalogReport(receivedCount: 0, normalizedCount: 0, skippedCount: 0)
  }
}

private struct ManagementM3UTransport: M3UAcquisitionTransport {
  enum Behavior: @unchecked Sendable {
    case response(status: Int, data: Data)
    case failure(any Error)
  }

  let behavior: Behavior

  func data(for request: URLRequest, maximumByteCount: Int) async throws
    -> (Data, HTTPURLResponse)
  {
    switch behavior {
    case .response(let status, let data):
      let response = try #require(
        HTTPURLResponse(
          url: request.url ?? URL(fileURLWithPath: "/"),
          statusCode: status,
          httpVersion: nil,
          headerFields: nil
        )
      )
      return (data, response)
    case .failure(let error):
      throw error
    }
  }
}

private actor ManagementStageRecorder {
  private(set) var values: [CatalogRefreshStage] = []
  func record(_ value: CatalogRefreshStage) { values.append(value) }
}
