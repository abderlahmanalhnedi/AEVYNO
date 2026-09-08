import Foundation

public enum SourceKind: String, CaseIterable, Codable, Hashable, Sendable {
  case xtreamCompatible
  case m3u
}

public struct CredentialReference: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public init() {
    self.init(rawValue: UUID())
  }
}

public enum SourceEndpointError: Error, Equatable, Sendable {
  case absoluteHTTPURLRequired
  case containsSensitiveComponents
}

public struct SourceEndpoint: Codable, Hashable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let url: URL

  public init(url: URL) throws {
    guard
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      url.host != nil
    else {
      throw SourceEndpointError.absoluteHTTPURLRequired
    }

    guard
      url.user == nil,
      url.password == nil,
      url.query == nil,
      url.fragment == nil
    else {
      throw SourceEndpointError.containsSensitiveComponents
    }

    self.url = url
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(url: container.decode(URL.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(url)
  }

  public var description: String {
    "SourceEndpoint(scheme: \(url.scheme?.lowercased() ?? "absent"), host: present, "
      + "port: \(url.port == nil ? "absent" : "present"), path: redacted)"
  }

  public var debugDescription: String { description }
}

public struct SourceConfiguration: Identifiable, Codable, Hashable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public struct ID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
      self.rawValue = rawValue
    }

    public init() {
      self.init(rawValue: UUID())
    }
  }

  public let id: ID
  public let displayName: String
  public let kind: SourceKind
  public let endpoint: SourceEndpoint?
  public let credentialReference: CredentialReference?
  public let isEnabled: Bool

  public init(
    id: ID = ID(),
    displayName: String,
    kind: SourceKind,
    endpoint: SourceEndpoint? = nil,
    credentialReference: CredentialReference? = nil,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.displayName = displayName
    self.kind = kind
    self.endpoint = endpoint
    self.credentialReference = credentialReference
    self.isEnabled = isEnabled
  }

  public var description: String {
    "SourceConfiguration(id: \(id.rawValue.uuidString), kind: \(kind.rawValue), "
      + "endpoint: \(endpoint == nil ? "absent" : "present"), "
      + "credentialReference: \(credentialReference == nil ? "absent" : "present"), "
      + "isEnabled: \(isEnabled))"
  }

  public var debugDescription: String { description }
}
