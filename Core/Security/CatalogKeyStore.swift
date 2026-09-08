import CryptoKit
import Foundation
import Security

/// Separate from provider credentials. Deleting a source must never delete this shared catalog key.
public actor CatalogKeyStore {
  private let client: any KeychainClient
  private let service: String
  private let account = "catalog-reference-key-v1"

  public init(service: String = "com.aevyno.catalog-encryption") {
    self.service = service
    client = SystemKeychainClient()
  }

  init(service: String, client: any KeychainClient) {
    self.service = service
    self.client = client
  }

  public func key() throws -> SymmetricKey {
    guard !service.isEmpty else { throw CredentialStoreError.invalidConfiguration }
    try Task.checkCancellation()
    let result = client.read(service: service, account: account)
    if result.status == errSecSuccess {
      return try decode(result.data)
    }
    guard result.status == errSecItemNotFound else { throw CredentialStoreError.unavailable }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    let status = client.add(
      data: data, service: service, account: account, accessibility: .whenUnlockedThisDeviceOnly)
    if status == errSecDuplicateItem {
      let existing = client.read(service: service, account: account)
      guard existing.status == errSecSuccess else { throw CredentialStoreError.unavailable }
      return try decode(existing.data)
    }
    guard status == errSecSuccess else { throw CredentialStoreError.unavailable }
    return key
  }

  private func decode(_ data: Data?) throws -> SymmetricKey {
    guard let data, data.count == 32 else { throw CredentialStoreError.corruptedData }
    return SymmetricKey(data: data)
  }
}
