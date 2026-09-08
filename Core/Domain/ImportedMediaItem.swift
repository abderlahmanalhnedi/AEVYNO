import CryptoKit
import Foundation

public struct ImportedMediaItem: Identifiable, Hashable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public struct ID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(
      sourceID: SourceConfiguration.ID,
      stableKey: String,
      occurrence: Int
    ) {
      var input = Data(sourceID.rawValue.uuidString.lowercased().utf8)
      input.append(0)
      input.append(contentsOf: stableKey.utf8)
      input.append(0)
      input.append(contentsOf: String(occurrence).utf8)

      let digest = SHA256.hash(data: input)
      let hexadecimalDigits = Array("0123456789abcdef".utf8)
      var encodedDigest: [UInt8] = []
      encodedDigest.reserveCapacity(SHA256.Digest.byteCount * 2)
      for byte in digest {
        encodedDigest.append(hexadecimalDigits[Int(byte >> 4)])
        encodedDigest.append(hexadecimalDigits[Int(byte & 0x0F)])
      }
      self.init(rawValue: String(decoding: encodedDigest, as: UTF8.self))
    }

    public var description: String { rawValue }
  }

  public let id: ID
  public let sourceID: SourceConfiguration.ID
  public let title: String
  public let mediaURL: URL
  public let groupTitle: String?
  public let artworkURL: URL?
  public let tvgID: String?
  public let tvgName: String?
  public let duration: TimeInterval?

  public init(
    id: ID,
    sourceID: SourceConfiguration.ID,
    title: String,
    mediaURL: URL,
    groupTitle: String? = nil,
    artworkURL: URL? = nil,
    tvgID: String? = nil,
    tvgName: String? = nil,
    duration: TimeInterval? = nil
  ) {
    self.id = id
    self.sourceID = sourceID
    self.title = title
    self.mediaURL = mediaURL
    self.groupTitle = groupTitle
    self.artworkURL = artworkURL
    self.tvgID = tvgID
    self.tvgName = tvgName
    self.duration = duration
  }

  public var description: String {
    "ImportedMediaItem(id: \(id), sourceID: \(sourceID.rawValue.uuidString), "
      + "mediaURL: <redacted-url>, artworkURL: \(artworkURL == nil ? "absent" : "<redacted-url>"))"
  }

  public var debugDescription: String { description }
}
