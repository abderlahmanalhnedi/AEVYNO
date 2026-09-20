import DesignSystem
import Domain
import Library
import SwiftUI

struct TVFavoriteCard: View {
  let item: FavoriteItemPresentation
  let artworkPipeline: ArtworkImagePipeline
  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      RemoteArtworkImageView(
        itemID: item.id, artworkURL: item.artworkURL, placeholderKind: kind,
        pixelWidth: 560, pixelHeight: 336, pipeline: artworkPipeline
      )
      .frame(height: 168).clipShape(
        RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
      Text(item.title).aevynoTypography(.cardTitle).lineLimit(1)
    }.frame(width: 280, alignment: .leading).padding(AEVYNOSpacing.sm).aevynoCardSurface()
      .accessibilityElement(children: .ignore).accessibilityLabel(item.title)
  }
  private var kind: CatalogArtworkPlaceholderKind {
    switch item.mediaKind {
    case .vod: .movie
    case .series: .series
    case .live: .live
    case .unspecified: .playlist
    }
  }
}
