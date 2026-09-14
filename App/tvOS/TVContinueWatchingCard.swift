import DesignSystem
import Domain
import Library
import SwiftUI

struct TVContinueWatchingCard: View {
  let item: ContinueWatchingItemPresentation
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      RemoteArtworkImageView(
        itemID: item.id, artworkURL: item.artworkURL, placeholderKind: placeholderKind,
        pixelWidth: 560, pixelHeight: 336, pipeline: artworkPipeline
      )
      .frame(height: 168)
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
      ProgressView(value: item.progressFraction).tint(AEVYNOColor.accent)
      Text(item.title).aevynoTypography(.cardTitle).lineLimit(1)
      Text(AppText.resumeFrom(item.position)).aevynoTypography(.metadata).foregroundStyle(
        AEVYNOColor.secondaryText)
    }
    .frame(width: 280, alignment: .leading).padding(AEVYNOSpacing.sm).aevynoCardSurface()
    .accessibilityElement(children: .ignore).accessibilityLabel(item.title)
    .accessibilityValue(
      "\(AppText.progressAccessibilityValue(item.progressFraction)). \(AppText.resumeFrom(item.position))"
    )
  }

  private var placeholderKind: CatalogArtworkPlaceholderKind {
    switch item.mediaKind {
    case .vod: .movie
    case .series: .series
    case .live: .live
    case .unspecified: .playlist
    }
  }
}
