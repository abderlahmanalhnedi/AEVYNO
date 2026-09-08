import Foundation

public enum CredentialSecretKind: String, Codable, Hashable, Sendable {
  case password
  case token
}

public enum SourceCredentialValidationError: Error, Equatable, Sendable, LocalizedError {
  case emptySecret

  public var errorDescription: String? {
    "A credential secret is required."
  }
}

public struct SourceCredential: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let username: String?
  public let secret: String
  public let secretKind: CredentialSecretKind

  public init(
    username: String? = nil,
    secret: String,
    secretKind: CredentialSecretKind
  ) throws {
    guard !secret.isEmpty else {
      throw SourceCredentialValidationError.emptySecret
    }

    self.username = username
    self.secret = secret
    self.secretKind = secretKind
  }

  public var description: String {
    "SourceCredential(username: \(username == nil ? "absent" : "present"), "
      + "secret: \(SafeDiagnostics.redactionMarker), kind: \(secretKind.rawValue))"
  }

  public var debugDescription: String { description }
}
