import Foundation

public struct MediaItem: Identifiable, Hashable, Sendable {
  public struct ID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }
  }

  public let id: ID
  public let title: String
  public let subtitle: String
  public let kind: MediaKind
  public let artworkTheme: ArtworkTheme
  public let progress: Double?
  public let facts: [String]
  public let summary: String

  public init(
    id: ID,
    title: String,
    subtitle: String,
    kind: MediaKind,
    artworkTheme: ArtworkTheme,
    progress: Double? = nil,
    facts: [String] = [],
    summary: String = "A synthetic AEVYNO preview created for interface testing."
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.kind = kind
    self.artworkTheme = artworkTheme
    self.progress = progress.map { min(max($0, 0), 1) }
    self.facts = facts
    self.summary = summary
  }
}

public enum MediaKind: String, Hashable, Codable, Sendable {
  case movie
  case series
  case liveChannel
}

public enum ArtworkTheme: String, CaseIterable, Hashable, Codable, Sendable {
  case aurora
  case ember
  case lagoon
  case meadow
  case midnight
  case solar
}
