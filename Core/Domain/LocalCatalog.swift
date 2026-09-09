import Foundation

/// Catalog values are separate from the synthetic Phase 1 presentation model.
public enum CatalogOrigin: String, Codable, Sendable {
  case m3u
  case xtream
}

public enum CatalogMediaKind: String, Codable, Sendable {
  /// M3U does not reliably identify live/VOD/series; do not guess from duration or URL.
  case unspecified
  case live
  case vod
  case series

  public init(_ kind: ProviderMediaKind) {
    switch kind {
    case .live: self = .live
    case .vod: self = .vod
    case .series: self = .series
    }
  }
}

public struct CatalogScope: Hashable, Sendable {
  public let sourceID: SourceConfiguration.ID
  public let origin: CatalogOrigin
  public let kind: CatalogMediaKind

  public init(sourceID: SourceConfiguration.ID, origin: CatalogOrigin, kind: CatalogMediaKind) {
    self.sourceID = sourceID
    self.origin = origin
    self.kind = kind
  }
}

public struct CatalogCategory: Identifiable, Equatable, Sendable {
  public let id: String
  public let scope: CatalogScope
  public let title: String

  public init(id: String, scope: CatalogScope, title: String) {
    self.id = id
    self.scope = scope
    self.title = title
  }
}

/// A committed category plus its committed item count.
public struct CatalogCategorySummary: Equatable, Sendable {
  public let category: CatalogCategory
  public let itemCount: Int

  public init(category: CatalogCategory, itemCount: Int) {
    self.category = category
    self.itemCount = itemCount
  }
}

public struct CatalogItem: Identifiable, Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let id: String
  public let scope: CatalogScope
  public let title: String
  public let categoryID: String?
  public let artworkURL: URL?
  public let mediaURL: URL?
  public let providerReference: ProviderItemReference?

  public init(
    id: String, scope: CatalogScope, title: String, categoryID: String? = nil,
    artworkURL: URL? = nil, mediaURL: URL? = nil,
    providerReference: ProviderItemReference? = nil
  ) {
    self.id = id
    self.scope = scope
    self.title = title
    self.categoryID = categoryID
    self.artworkURL = artworkURL
    self.mediaURL = mediaURL
    self.providerReference = providerReference
  }

  public var description: String { "CatalogItem(references: <redacted>)" }
  public var debugDescription: String { description }
}
