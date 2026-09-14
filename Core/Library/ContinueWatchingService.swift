import Domain
import Foundation
import Playback

/// Safe, bounded presentation state for media that can resume from local progress.
public struct ContinueWatchingItemPresentation: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let mediaKind: CatalogMediaKind
  public let artworkURL: URL?
  public let progressFraction: Double
  public let position: TimeInterval
  public let duration: TimeInterval

  public init(
    id: String, title: String, mediaKind: CatalogMediaKind, artworkURL: URL?,
    progressFraction: Double, position: TimeInterval, duration: TimeInterval
  ) {
    self.id = id
    self.title = title
    self.mediaKind = mediaKind
    self.artworkURL = artworkURL
    self.progressFraction = progressFraction
    self.position = position
    self.duration = duration
  }
}

public protocol ContinueWatchingServing: Sendable {
  func items() async throws -> [ContinueWatchingItemPresentation]
  func revisions() async -> AsyncStream<UInt64>
}

/// Joins durable local progress to exact committed catalog records without exposing playback data.
public actor ProductionContinueWatchingService: ContinueWatchingServing {
  public static let defaultMaximumItems = 20

  private let catalog: any CatalogLibraryQuerying
  private let progressRepository: any WatchProgressRepository
  private let maximumItems: Int
  private let revisionCenter: LibraryRevisionCenter

  public init(
    catalog: any CatalogLibraryQuerying,
    progressRepository: any WatchProgressRepository,
    maximumItems: Int = defaultMaximumItems,
    revisionCenter: LibraryRevisionCenter = LibraryRevisionCenter()
  ) {
    self.catalog = catalog
    self.progressRepository = progressRepository
    self.maximumItems = min(max(maximumItems, 1), Self.defaultMaximumItems)
    self.revisionCenter = revisionCenter
  }

  public func revisions() async -> AsyncStream<UInt64> { await revisionCenter.stream() }

  public func items() async throws -> [ContinueWatchingItemPresentation] {
    let progress: [WatchProgress]
    do {
      progress = try await progressRepository.allProgress()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // A temporary local-store failure must not make catalog browsing unusable.
      return []
    }

    let candidates =
      progress
      .filter(Self.isResumable)
      .sorted {
        if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
        return $0.mediaID < $1.mediaID
      }

    var result: [ContinueWatchingItemPresentation] = []
    result.reserveCapacity(min(candidates.count, maximumItems))
    for record in candidates where result.count < maximumItems {
      try Task.checkCancellation()
      guard let item = try? await catalog.item(id: record.mediaID) else { continue }
      guard item.scope.kind != .live else { continue }
      guard
        let position = PlaybackCompletionPolicy.clampedResumePosition(
          record.position, duration: record.duration
        )
      else { continue }
      result.append(
        ContinueWatchingItemPresentation(
          id: item.id,
          title: item.title,
          mediaKind: item.scope.kind,
          artworkURL: item.artworkURL,
          progressFraction: min(max(position / record.duration, 0), 1),
          position: position,
          duration: record.duration
        ))
    }
    return result
  }

  private static func isResumable(_ progress: WatchProgress) -> Bool {
    !progress.isCompleted
      && progress.position.isFinite && progress.position >= 0
      && progress.duration.isFinite && progress.duration > 0
      && progress.position < progress.duration
  }
}
