import DesignSystem
import Domain
import Library
import SwiftUI

struct MobileFavoriteCard: View {
  let item: FavoriteItemPresentation
  let artworkPipeline: ArtworkImagePipeline
  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
      RemoteArtworkImageView(
        itemID: item.id, artworkURL: item.artworkURL, placeholderKind: kind,
        pixelWidth: 400, pixelHeight: 240, pipeline: artworkPipeline
      )
      .frame(width: 220, height: 124).clipShape(
        RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
      Text(item.title).aevynoTypography(.cardTitle).lineLimit(1)
    }.frame(width: 220, alignment: .leading).accessibilityElement(children: .ignore)
      .accessibilityLabel(item.title)
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
