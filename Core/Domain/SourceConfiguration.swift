import Foundation

public enum SourceKind: String, CaseIterable, Codable, Hashable, Sendable {
  case xtreamCompatible
  case m3u
}

public enum RefreshCadence: String, CaseIterable, Codable, Hashable, Sendable {
  case every6Hours
  case every12Hours
  case daily

  public var duration: TimeInterval {
    switch self {
    case .every6Hours: 6 * 60 * 60
    case .every12Hours: 12 * 60 * 60
    case .daily: 24 * 60 * 60
    }
  }
}

public enum RefreshPolicy: Hashable, Sendable {
  case manualOnly
  case automatic(RefreshCadence)
}

extension RefreshPolicy: Codable {
  private enum CodingKeys: String, CodingKey {
    case mode
    case cadence
  }

  private enum Mode: String, Codable {
    case manualOnly
    case automatic
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Mode.self, forKey: .mode) {
    case .manualOnly:
      self = .manualOnly
    case .automatic:
      self = .automatic(try container.decode(RefreshCadence.self, forKey: .cadence))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .manualOnly:
      try container.encode(Mode.manualOnly, forKey: .mode)
    case .automatic(let cadence):
      try container.encode(Mode.automatic, forKey: .mode)
      try container.encode(cadence, forKey: .cadence)
    }
  }
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

public struct EPGConfiguration: Codable, Hashable, Sendable {
  public let endpoint: SourceEndpoint

  public init(endpoint: SourceEndpoint) { self.endpoint = endpoint }
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
  public let refreshPolicy: RefreshPolicy
  public let epgConfiguration: EPGConfiguration?

  public init(
    id: ID = ID(),
    displayName: String,
    kind: SourceKind,
    endpoint: SourceEndpoint? = nil,
    credentialReference: CredentialReference? = nil,
    isEnabled: Bool = true,
    refreshPolicy: RefreshPolicy = .manualOnly,
    epgConfiguration: EPGConfiguration? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.kind = kind
    self.endpoint = endpoint
    self.credentialReference = credentialReference
    self.isEnabled = isEnabled
    self.refreshPolicy = refreshPolicy
    self.epgConfiguration = epgConfiguration
  }

  public var description: String {
    "SourceConfiguration(id: \(id.rawValue.uuidString), kind: \(kind.rawValue), "
      + "endpoint: \(endpoint == nil ? "absent" : "present"), "
      + "credentialReference: \(credentialReference == nil ? "absent" : "present"), "
      + "isEnabled: \(isEnabled), refreshPolicy: \(refreshPolicy), epgConfiguration: \(epgConfiguration == nil ? "absent" : "present"))"
  }

  public var debugDescription: String { description }
}
