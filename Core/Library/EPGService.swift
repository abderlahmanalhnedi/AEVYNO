import Domain
import Foundation
import Persistence

/// Safe Now/Next presentation boundary. SwiftUI never sees SQLite or provider identifiers.
public protocol EPGPresenting: Sendable {
  func nowNext(for catalogItemID: String, at instant: Date) async throws -> EPGNowNextPresentation
}

/// Catalog-to-EPG join implementation behind the presentation boundary.
public actor ProductionEPGService: EPGPresenting {
  private let catalog: any CatalogQueryRepository
  private let epg: any EPGQueryRepository

  public init(catalog: any CatalogQueryRepository, epg: any EPGQueryRepository) {
    self.catalog = catalog
    self.epg = epg
  }

  public func nowNext(for catalogItemID: String, at instant: Date) async throws
    -> EPGNowNextPresentation
  {
    guard let item = try await catalog.item(id: catalogItemID), let channelID = item.epgChannelID
    else {
      return EPGNowNextPresentation(now: nil, next: nil)
    }
    return try await epg.nowNext(sourceID: item.scope.sourceID, channelID: channelID, at: instant)
  }
}
