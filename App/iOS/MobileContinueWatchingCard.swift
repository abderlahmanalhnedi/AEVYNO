import DesignSystem
import Domain
import Library
import SwiftUI

struct MobileContinueWatchingCard: View {
  let item: ContinueWatchingItemPresentation
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
      RemoteArtworkImageView(
        itemID: item.id, artworkURL: item.artworkURL, placeholderKind: placeholderKind,
        pixelWidth: 400, pixelHeight: 240, pipeline: artworkPipeline
      )
      .frame(width: 220, height: 124).clipShape(
        RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
      ProgressView(value: item.progressFraction).tint(AEVYNOColor.accent)
      Text(item.title).aevynoTypography(.cardTitle).lineLimit(1)
      Text(AppText.resumeFrom(item.position)).aevynoTypography(.metadata).foregroundStyle(
        AEVYNOColor.secondaryText)
    }
    .frame(width: 220, alignment: .leading)
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
