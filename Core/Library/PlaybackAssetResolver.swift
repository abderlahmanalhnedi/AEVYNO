import Domain
import Foundation
import Playback

/// Resolves one committed catalog identity to a short-lived player asset without exposing URLs to UI.
public struct ProductionPlaybackAssetResolver: PlaybackAssetResolving, Sendable {
  private let catalog: any CatalogLibraryQuerying

  public init(catalog: any CatalogLibraryQuerying) {
    self.catalog = catalog
  }

  public func availability(for mediaID: String) async -> PlaybackAvailability {
    do {
      guard let item = try await catalog.item(id: mediaID) else {
        return .unavailable(.itemUnavailable)
      }
      return availability(for: item)
    } catch is CancellationError {
      return .unavailable(.itemUnavailable)
    } catch {
      return .unavailable(.sourceUnavailable)
    }
  }

  public func resolve(mediaID: String) async throws -> PlaybackAsset {
    try Task.checkCancellation()
    let item: CatalogItem
    do {
      guard let resolved = try await catalog.item(id: mediaID) else {
        throw PlaybackFailure.itemUnavailable
      }
      item = resolved
    } catch is CancellationError {
      throw CancellationError()
    } catch let failure as PlaybackFailure {
      throw failure
    } catch {
      throw PlaybackFailure.sourceUnavailable
    }

    guard availability(for: item) == .playable else {
      throw PlaybackFailure.unsupported
    }
    guard
      let mediaURL = item.mediaURL,
      let scheme = mediaURL.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      mediaURL.host != nil
    else {
      throw PlaybackFailure.mediaUnavailable
    }
    return PlaybackAsset(
      mediaID: item.id,
      title: item.title,
      catalogKind: item.scope.kind,
      mediaURL: mediaURL
    )
  }

  private func availability(for item: CatalogItem) -> PlaybackAvailability {
    switch (item.scope.origin, item.scope.kind) {
    case (.m3u, .unspecified):
      return item.mediaURL == nil ? .unavailable(.mediaUnavailable) : .playable
    case (.xtream, .live), (.xtream, .vod), (.xtream, .series):
      // The persisted provider contract does not yet contain a reviewed playback path/container.
      return .unavailable(.unsupported)
    default:
      return .unavailable(.unsupported)
    }
  }
}
