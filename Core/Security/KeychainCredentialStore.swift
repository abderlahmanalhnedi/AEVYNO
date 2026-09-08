import Domain
import Foundation
import Security

public actor KeychainCredentialStore: CredentialStore {
  public static let defaultService = "com.aevyno.source-credentials"

  private let service: String
  private let client: any KeychainClient

  public init(service: String = KeychainCredentialStore.defaultService) {
    self.service = service
    client = SystemKeychainClient()
  }

  init(service: String, client: any KeychainClient) {
    self.service = service
    self.client = client
  }

  public func store(
    _ credential: SourceCredential,
    for reference: CredentialReference
  ) async throws {
    try validateConfiguration()
    let status = client.add(
      data: try encodedData(for: credential),
      service: service,
      account: account(for: reference),
      accessibility: .whenUnlockedThisDeviceOnly
    )
    guard status == errSecSuccess else {
      throw normalizedError(for: status)
    }
  }

  public func credential(for reference: CredentialReference) async throws -> SourceCredential? {
    try validateConfiguration()
    let result = client.read(
      service: service,
      account: account(for: reference)
    )

    if result.status == errSecItemNotFound {
      return nil
    }

    guard result.status == errSecSuccess else {
      throw normalizedError(for: result.status)
    }

    guard let data = result.data else {
      throw CredentialStoreError.corruptedData
    }

    return try decodedCredential(from: data)
  }

  public func update(
    _ credential: SourceCredential,
    for reference: CredentialReference
  ) async throws {
    try validateConfiguration()
    let status = client.update(
      data: try encodedData(for: credential),
      service: service,
      account: account(for: reference)
    )
    guard status == errSecSuccess else {
      throw normalizedError(for: status)
    }
  }

  public func deleteCredential(for reference: CredentialReference) async throws {
    try validateConfiguration()
    let status = client.delete(
      service: service,
      account: account(for: reference)
    )
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw normalizedError(for: status)
    }
  }

  private func validateConfiguration() throws {
    guard !service.isEmpty else {
      throw CredentialStoreError.invalidConfiguration
    }
  }

  private func account(for reference: CredentialReference) -> String {
    reference.rawValue.uuidString.lowercased()
  }

  private func encodedData(for credential: SourceCredential) throws -> Data {
    do {
      return try JSONEncoder().encode(
        CredentialPayload(
          username: credential.username,
          secret: credential.secret,
          secretKind: credential.secretKind
        )
      )
    } catch {
      throw CredentialStoreError.operationFailed
    }
  }

  private func decodedCredential(from data: Data) throws -> SourceCredential {
    do {
      let payload = try JSONDecoder().decode(CredentialPayload.self, from: data)
      return try SourceCredential(
        username: payload.username,
        secret: payload.secret,
        secretKind: payload.secretKind
      )
    } catch {
      throw CredentialStoreError.corruptedData
    }
  }

  private func normalizedError(for status: OSStatus) -> CredentialStoreError {
    switch status {
    case errSecDuplicateItem:
      return .credentialAlreadyExists
    case errSecItemNotFound:
      return .credentialNotFound
    case errSecNotAvailable, errSecInteractionNotAllowed:
      return .unavailable
    case errSecAuthFailed:
      return .accessDenied
    case errSecDecode:
      return .corruptedData
    default:
      return .operationFailed
    }
  }
}

private struct CredentialPayload: Codable {
  let username: String?
  let secret: String
  let secretKind: CredentialSecretKind
}

enum KeychainAccessibility: Equatable, Sendable {
  case whenUnlockedThisDeviceOnly
}

struct KeychainReadResult: Sendable {
  let status: OSStatus
  let data: Data?
}

protocol KeychainClient: Sendable {
  func add(
    data: Data,
    service: String,
    account: String,
    accessibility: KeychainAccessibility
  ) -> OSStatus
  func read(service: String, account: String) -> KeychainReadResult
  func update(data: Data, service: String, account: String) -> OSStatus
  func delete(service: String, account: String) -> OSStatus
}

struct SystemKeychainClient: KeychainClient {
  func add(
    data: Data,
    service: String,
    account: String,
    accessibility: KeychainAccessibility
  ) -> OSStatus {
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: accessibilityValue(for: accessibility),
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
      kSecValueData as String: data,
    ]
    return SecItemAdd(attributes as CFDictionary, nil)
  }

  func read(service: String, account: String) -> KeychainReadResult {
    let query: [String: Any] = baseQuery(service: service, account: account).merging([
      kSecReturnData as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]) { _, newValue in newValue }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return KeychainReadResult(status: status, data: result as? Data)
  }

  func update(data: Data, service: String, account: String) -> OSStatus {
    let attributes: [String: Any] = [kSecValueData as String: data]
    return SecItemUpdate(
      baseQuery(service: service, account: account) as CFDictionary,
      attributes as CFDictionary
    )
  }

  func delete(service: String, account: String) -> OSStatus {
    SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
  }

  private func baseQuery(service: String, account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }

  private func accessibilityValue(
    for accessibility: KeychainAccessibility
  ) -> CFString {
    switch accessibility {
    case .whenUnlockedThisDeviceOnly:
      return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
  }
}
