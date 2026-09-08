import Domain
import Foundation
import Security
import Testing

@testable import AEVYNOSecurity

@Test("In-memory credential store supports isolated CRUD behavior")
func inMemoryCredentialStoreCRUD() async throws {
  let store = InMemoryCredentialStore()
  let reference = CredentialReference()
  let initial = try SourceCredential(
    username: "synthetic-user",
    secret: "synthetic-password",
    secretKind: .password
  )
  let updated = try SourceCredential(
    secret: "synthetic-token",
    secretKind: .token
  )

  #expect(await store.credential(for: reference) == nil)
  try await store.store(initial, for: reference)
  #expect(await store.credential(for: reference) == initial)
  try await store.update(updated, for: reference)
  #expect(await store.credential(for: reference) == updated)
  await store.deleteCredential(for: reference)
  #expect(await store.credential(for: reference) == nil)
}

@Test("Keychain credential store performs CRUD through its system boundary")
func keychainCredentialStoreCRUD() async throws {
  let client = LockedKeychainClient()
  let store = KeychainCredentialStore(service: "com.aevyno.tests.credentials", client: client)
  let reference = CredentialReference(
    rawValue: try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000004"))
  )
  let initial = try SourceCredential(
    username: "synthetic-user",
    secret: "synthetic-password",
    secretKind: .password
  )
  let updated = try SourceCredential(
    username: "synthetic-user",
    secret: "synthetic-token",
    secretKind: .token
  )

  #expect(try await store.credential(for: reference) == nil)
  try await store.store(initial, for: reference)
  #expect(try await store.credential(for: reference) == initial)
  try await store.update(updated, for: reference)
  #expect(try await store.credential(for: reference) == updated)
  try await store.deleteCredential(for: reference)
  #expect(try await store.credential(for: reference) == nil)

  let observation = client.observation()
  #expect(observation.lastAccessibility == .whenUnlockedThisDeviceOnly)
  #expect(observation.lastService == "com.aevyno.tests.credentials")
  #expect(observation.lastAccount == reference.rawValue.uuidString.lowercased())
}

@Test("Keychain errors are normalized without exposing status values")
func keychainErrorsAreNormalized() async throws {
  let duplicateClient = LockedKeychainClient(addStatusOverride: errSecDuplicateItem)
  let duplicateStore = KeychainCredentialStore(
    service: "com.aevyno.tests.duplicate",
    client: duplicateClient
  )
  let credential = try SourceCredential(secret: "synthetic-secret", secretKind: .token)

  await #expect(throws: CredentialStoreError.credentialAlreadyExists) {
    try await duplicateStore.store(credential, for: CredentialReference())
  }
  #expect(!CredentialStoreError.credentialAlreadyExists.description.contains("-25299"))

  let unavailableClient = LockedKeychainClient(readStatusOverride: errSecNotAvailable)
  let unavailableStore = KeychainCredentialStore(
    service: "com.aevyno.tests.unavailable",
    client: unavailableClient
  )

  await #expect(throws: CredentialStoreError.unavailable) {
    _ = try await unavailableStore.credential(for: CredentialReference())
  }
  #expect(!CredentialStoreError.unavailable.description.contains(String(errSecNotAvailable)))
}

@Test("Credential diagnostics redact secret and username values")
func credentialDiagnosticsAreRedacted() throws {
  let username = "synthetic-private-user"
  let secret = "synthetic-private-secret"
  let credential = try SourceCredential(
    username: username,
    secret: secret,
    secretKind: .password
  )

  #expect(!credential.description.contains(username))
  #expect(!credential.description.contains(secret))
  #expect(credential.description.contains(SafeDiagnostics.redactionMarker))
  #expect(credential.debugDescription == credential.description)
}

@Test("Safe diagnostics redact exact secrets and credential-bearing URL components")
func safeDiagnosticsRemoveSensitiveValues() throws {
  let username = "synthetic-private-user"
  let secret = "synthetic-private-secret"
  let message = "Authentication failed for \(username) using \(secret)."
  let url = try #require(
    URL(
      string:
        "https://synthetic-user:synthetic-password@example.invalid/private/list?token=synthetic-token#fragment"
    )
  )

  let redactedMessage = SafeDiagnostics.redacting([username, secret], in: message)
  let sanitizedURL = SafeDiagnostics.sanitizedURL(url)

  #expect(!redactedMessage.contains(username))
  #expect(!redactedMessage.contains(secret))
  #expect(redactedMessage.contains(SafeDiagnostics.redactionMarker))
  #expect(sanitizedURL == "https://example.invalid/redacted?redacted")
  #expect(!sanitizedURL.contains("synthetic"))
  #expect(!sanitizedURL.contains("fragment"))
}

@Test("Credential store actor serializes concurrent access")
func credentialStoreSupportsConcurrentAccess() async throws {
  let client = LockedKeychainClient()
  let store = KeychainCredentialStore(service: "com.aevyno.tests.concurrent", client: client)
  let references = (0..<20).map { _ in CredentialReference() }

  try await withThrowingTaskGroup(of: Void.self) { group in
    for (index, reference) in references.enumerated() {
      group.addTask {
        let credential = try SourceCredential(
          secret: "synthetic-secret-\(index)",
          secretKind: .token
        )
        try await store.store(credential, for: reference)
      }
    }
    try await group.waitForAll()
  }

  for (index, reference) in references.enumerated() {
    let credential = try await store.credential(for: reference)
    #expect(credential?.secret == "synthetic-secret-\(index)")
  }
}

@Test("Catalog encryption key is stable, device-local and separate from source credentials")
func catalogKeyIsStableAndIsolated() async throws {
  let client = LockedKeychainClient()
  let keys = CatalogKeyStore(service: "com.aevyno.tests.catalog", client: client)
  let first = try await keys.key()
  let reopened = CatalogKeyStore(service: "com.aevyno.tests.catalog", client: client)
  #expect(try await reopened.key() == first)
  #expect(first.bitCount == 256)
  let observation = client.observation()
  #expect(observation.lastAccessibility == .whenUnlockedThisDeviceOnly)
  #expect(observation.lastAccount == "catalog-reference-key-v1")
  let credentials = KeychainCredentialStore(service: "com.aevyno.tests.credentials", client: client)
  let reference = CredentialReference()
  try await credentials.store(
    SourceCredential(secret: "synthetic", secretKind: .password), for: reference)
  try await credentials.deleteCredential(for: reference)
  #expect(try await keys.key() == first)
}

@Test("Unavailable or corrupt catalog Keychain data fails without replacing the key")
func catalogKeyFailures() async throws {
  let unavailable = CatalogKeyStore(
    service: "com.aevyno.tests.catalog",
    client: LockedKeychainClient(readStatusOverride: errSecNotAvailable))
  await #expect(throws: CredentialStoreError.unavailable) { try await unavailable.key() }
  let client = LockedKeychainClient()
  let service = "com.aevyno.tests.corrupt-catalog"
  _ = client.add(
    data: Data([1, 2, 3]), service: service, account: "catalog-reference-key-v1",
    accessibility: .whenUnlockedThisDeviceOnly)
  let corrupt = CatalogKeyStore(service: service, client: client)
  await #expect(throws: CredentialStoreError.corruptedData) { try await corrupt.key() }
  #expect(
    client.read(service: service, account: "catalog-reference-key-v1").data == Data([1, 2, 3]))
}

private actor InMemoryCredentialStore: CredentialStore {
  private var credentials: [CredentialReference: SourceCredential] = [:]

  func store(_ credential: SourceCredential, for reference: CredentialReference) throws {
    guard credentials[reference] == nil else {
      throw CredentialStoreError.credentialAlreadyExists
    }
    credentials[reference] = credential
  }

  func credential(for reference: CredentialReference) -> SourceCredential? {
    credentials[reference]
  }

  func update(_ credential: SourceCredential, for reference: CredentialReference) throws {
    guard credentials[reference] != nil else {
      throw CredentialStoreError.credentialNotFound
    }
    credentials[reference] = credential
  }

  func deleteCredential(for reference: CredentialReference) {
    credentials[reference] = nil
  }
}

private final class LockedKeychainClient: KeychainClient, @unchecked Sendable {
  struct Observation {
    let lastAccessibility: KeychainAccessibility?
    let lastService: String?
    let lastAccount: String?
  }

  private struct ItemKey: Hashable {
    let service: String
    let account: String
  }

  private let lock = NSLock()
  private let addStatusOverride: OSStatus?
  private let readStatusOverride: OSStatus?
  private var items: [ItemKey: Data] = [:]
  private var lastAccessibility: KeychainAccessibility?
  private var lastService: String?
  private var lastAccount: String?

  init(
    addStatusOverride: OSStatus? = nil,
    readStatusOverride: OSStatus? = nil
  ) {
    self.addStatusOverride = addStatusOverride
    self.readStatusOverride = readStatusOverride
  }

  func add(
    data: Data,
    service: String,
    account: String,
    accessibility: KeychainAccessibility
  ) -> OSStatus {
    lock.withLock {
      observe(service: service, account: account)
      lastAccessibility = accessibility
      if let addStatusOverride {
        return addStatusOverride
      }
      let key = ItemKey(service: service, account: account)
      guard items[key] == nil else {
        return errSecDuplicateItem
      }
      items[key] = data
      return errSecSuccess
    }
  }

  func read(service: String, account: String) -> KeychainReadResult {
    lock.withLock {
      observe(service: service, account: account)
      if let readStatusOverride {
        return KeychainReadResult(status: readStatusOverride, data: nil)
      }
      guard let data = items[ItemKey(service: service, account: account)] else {
        return KeychainReadResult(status: errSecItemNotFound, data: nil)
      }
      return KeychainReadResult(status: errSecSuccess, data: data)
    }
  }

  func update(data: Data, service: String, account: String) -> OSStatus {
    lock.withLock {
      observe(service: service, account: account)
      let key = ItemKey(service: service, account: account)
      guard items[key] != nil else {
        return errSecItemNotFound
      }
      items[key] = data
      return errSecSuccess
    }
  }

  func delete(service: String, account: String) -> OSStatus {
    lock.withLock {
      observe(service: service, account: account)
      let removed = items.removeValue(forKey: ItemKey(service: service, account: account))
      return removed == nil ? errSecItemNotFound : errSecSuccess
    }
  }

  func observation() -> Observation {
    lock.withLock {
      Observation(
        lastAccessibility: lastAccessibility,
        lastService: lastService,
        lastAccount: lastAccount
      )
    }
  }

  private func observe(service: String, account: String) {
    lastService = service
    lastAccount = account
  }
}
