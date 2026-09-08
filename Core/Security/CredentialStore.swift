import Domain
import Foundation

public protocol CredentialStore: Sendable {
  func store(_ credential: SourceCredential, for reference: CredentialReference) async throws
  func credential(for reference: CredentialReference) async throws -> SourceCredential?
  func update(_ credential: SourceCredential, for reference: CredentialReference) async throws
  func deleteCredential(for reference: CredentialReference) async throws
}

public enum CredentialStoreError: Error, Equatable, Sendable, LocalizedError,
  CustomStringConvertible
{
  case credentialAlreadyExists
  case credentialNotFound
  case invalidConfiguration
  case corruptedData
  case unavailable
  case accessDenied
  case operationFailed

  public var errorDescription: String? {
    switch self {
    case .credentialAlreadyExists:
      return "A credential already exists for this source."
    case .credentialNotFound:
      return "The credential could not be found."
    case .invalidConfiguration:
      return "Secure credential storage is not configured correctly."
    case .corruptedData:
      return "The stored credential could not be read."
    case .unavailable:
      return "Secure credential storage is currently unavailable."
    case .accessDenied:
      return "Access to secure credential storage was denied."
    case .operationFailed:
      return "The secure credential operation failed."
    }
  }

  public var description: String {
    errorDescription ?? "The secure credential operation failed."
  }
}
