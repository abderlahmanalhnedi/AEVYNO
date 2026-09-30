import Domain
import Foundation
import Persistence

/// Safe Now/Next presentation boundary. SwiftUI never sees SQLite or provider identifiers.
public protocol EPGPresenting: Sendable {
  func nowNext(for catalogItemID: String, at instant: Date) async throws -> EPGNowNextPresentation
  func guide(
    sourceID: SourceConfiguration.ID, interval: EPGGuideInterval, offset: Int
  ) async throws -> EPGGuidePresentation
  func health(sourceID: SourceConfiguration.ID) async throws -> EPGHealth
}

/// Catalog-to-EPG join implementation behind the presentation boundary.
public actor ProductionEPGService: EPGPresenting {
  public static let guideChannelPageSize = 40
  private let catalog: any CatalogQueryRepository
  private let epg: any EPGQueryRepository
  private let sources: (any SourceRepository)?

  public init(
    catalog: any CatalogQueryRepository, epg: any EPGQueryRepository,
    sources: (any SourceRepository)? = nil
  ) {
    self.catalog = catalog
    self.epg = epg
    self.sources = sources
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

  /// Reads one deterministic committed catalog page and one indexed EPG interval query. The
  /// catalog's encrypted XMLTV anchor is never returned to SwiftUI.
  public func guide(
    sourceID: SourceConfiguration.ID, interval: EPGGuideInterval, offset: Int = 0
  ) async throws -> EPGGuidePresentation {
    try Task.checkCancellation()
    guard offset >= 0 else { throw EPGStoreError.invalidInput }
    let candidates = try await catalog.items(
      matching: CatalogFilter(sourceID: sourceID),
      page: CatalogPage(limit: Self.guideChannelPageSize, offset: offset))
    let mapped = candidates.compactMap { item -> (CatalogItem, EPGChannelIdentity)? in
      guard let channel = item.epgChannelID else { return nil }
      return (item, channel)
    }
    let programmes = try await epg.programmes(
      sourceID: sourceID, channelIDs: mapped.map(\.1), interval: interval)
    let byChannel = Dictionary(grouping: programmes, by: \.channelID)
    let channels = mapped.map { item, channel in
      EPGGuideChannel(
        id: item.id, title: item.title,
        programmes: byChannel[channel] ?? [])
    }
    return EPGGuidePresentation(
      interval: interval, channels: channels,
      nextOffset: candidates.count == Self.guideChannelPageSize ? offset + candidates.count : nil)
  }

  public func health(sourceID: SourceConfiguration.ID) async throws -> EPGHealth {
    guard let configuration = try await sources?.source(id: sourceID),
      configuration.kind == .m3u, configuration.epgConfiguration != nil
    else {
      return EPGHealth(configured: false)
    }
    guard let stored = try await epg.health(sourceID: sourceID) else {
      return EPGHealth(configured: true)
    }
    return EPGHealth(
      configured: true, lastAttemptedAt: stored.lastAttemptedAt,
      lastSuccessfulAt: stored.lastSuccessfulAt,
      lastCommittedProgrammeCount: stored.lastCommittedProgrammeCount,
      coverageStartAt: stored.coverageStartAt, coverageEndAt: stored.coverageEndAt,
      lastResult: stored.lastResult, lastFailureCategory: stored.lastFailureCategory)
  }
}
