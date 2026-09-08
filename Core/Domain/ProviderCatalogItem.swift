import CryptoKit
import Foundation

public enum ProviderMediaKind: String, Codable, CaseIterable, Hashable, Sendable {
  case live
  case vod
  case series
}

public struct ProviderItemReference: Codable, Hashable, Sendable {
  public let kind: ProviderMediaKind
  public let providerID: String

  public init(kind: ProviderMediaKind, providerID: String) {
    self.kind = kind
    self.providerID = providerID
  }
}

public struct ProviderCategory: Identifiable, Codable, Hashable, Sendable {
  public struct ID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(
      sourceID: SourceConfiguration.ID,
      kind: ProviderMediaKind,
      providerID: String
    ) {
      self.init(
        rawValue: ProviderStableIdentity.digest(
          sourceID: sourceID,
          components: ["category", kind.rawValue, providerID]
        )
      )
    }
  }

  public let id: ID
  public let sourceID: SourceConfiguration.ID
  public let kind: ProviderMediaKind
  public let providerID: String
  public let title: String

  public init(
    id: ID,
    sourceID: SourceConfiguration.ID,
    kind: ProviderMediaKind,
    providerID: String,
    title: String
  ) {
    self.id = id
    self.sourceID = sourceID
    self.kind = kind
    self.providerID = providerID
    self.title = title
  }
}

public struct ProviderCatalogItem: Identifiable, Codable, Hashable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public struct ID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(
      sourceID: SourceConfiguration.ID,
      reference: ProviderItemReference
    ) {
      self.init(
        rawValue: ProviderStableIdentity.digest(
          sourceID: sourceID,
          components: ["item", reference.kind.rawValue, reference.providerID]
        )
      )
    }

    public var description: String { rawValue }
  }

  public let id: ID
  public let sourceID: SourceConfiguration.ID
  public let providerReference: ProviderItemReference
  public let title: String
  public let categoryID: ProviderCategory.ID?
  public let artworkURL: URL?

  public init(
    id: ID,
    sourceID: SourceConfiguration.ID,
    providerReference: ProviderItemReference,
    title: String,
    categoryID: ProviderCategory.ID? = nil,
    artworkURL: URL? = nil
  ) {
    self.id = id
    self.sourceID = sourceID
    self.providerReference = providerReference
    self.title = title
    self.categoryID = categoryID
    self.artworkURL = artworkURL
  }

  public var description: String {
    "ProviderCatalogItem(id: \(id), sourceID: \(sourceID.rawValue.uuidString), "
      + "kind: \(providerReference.kind.rawValue), artworkURL: "
      + "\(artworkURL == nil ? "absent" : "<redacted-url>"))"
  }

  public var debugDescription: String { description }
}

public struct ProviderAccountSnapshot: Codable, Equatable, Sendable {
  public let status: String?
  public let expiresAt: Date?
  public let isTrial: Bool?
  public let activeConnections: Int?
  public let maximumConnections: Int?
  public let allowedOutputFormats: [String]
  public let serverTimeZoneIdentifier: String?

  public init(
    status: String? = nil,
    expiresAt: Date? = nil,
    isTrial: Bool? = nil,
    activeConnections: Int? = nil,
    maximumConnections: Int? = nil,
    allowedOutputFormats: [String] = [],
    serverTimeZoneIdentifier: String? = nil
  ) {
    self.status = status
    self.expiresAt = expiresAt
    self.isTrial = isTrial
    self.activeConnections = activeConnections
    self.maximumConnections = maximumConnections
    self.allowedOutputFormats = allowedOutputFormats
    self.serverTimeZoneIdentifier = serverTimeZoneIdentifier
  }
}

private enum ProviderStableIdentity {
  static func digest(sourceID: SourceConfiguration.ID, components: [String]) -> String {
    var input = Data(sourceID.rawValue.uuidString.lowercased().utf8)
    for component in components {
      input.append(0)
      input.append(contentsOf: component.utf8)
    }

    let digest = SHA256.hash(data: input)
    let hexadecimalDigits = Array("0123456789abcdef".utf8)
    var encodedDigest: [UInt8] = []
    encodedDigest.reserveCapacity(SHA256.Digest.byteCount * 2)
    for byte in digest {
      encodedDigest.append(hexadecimalDigits[Int(byte >> 4)])
      encodedDigest.append(hexadecimalDigits[Int(byte & 0x0F)])
    }
    return String(decoding: encodedDigest, as: UTF8.self)
  }
}
