import DesignSystem
import Domain
import SwiftUI

enum TVMediaCardFamily: Equatable {
  case landscape
  case poster
  case live

  var artworkSize: CGSize {
    switch self {
    case .landscape: return CGSize(width: 390, height: 220)
    case .poster: return CGSize(width: 238, height: 357)
    case .live: return CGSize(width: 350, height: 197)
    }
  }
}

struct TVMediaCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let item: MediaItem
  let family: TVMediaCardFamily
  let isFocused: Bool
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      artwork

      Text(item.title)
        .aevynoTypography(.cardTitle)
        .foregroundStyle(AEVYNOColor.primaryText)
        .lineLimit(1)

      Text(item.subtitle)
        .aevynoTypography(.metadata)
        .foregroundStyle(isFocused ? Color.white.opacity(0.82) : AEVYNOColor.secondaryText)
        .lineLimit(1)
    }
    .frame(width: family.artworkSize.width, alignment: .leading)
    .padding(AEVYNOSpacing.sm)
    .aevynoCardSurface()
    .aevynoTVFocusTreatment(isFocused: isFocused, reduceMotion: reduceMotion)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.title)
    .accessibilityValue(accessibilityValue)
  }

  private var artwork: some View {
    ArtworkImageView(
      request: ArtworkRequest(
        itemID: item.id,
        theme: item.artworkTheme,
        kind: item.kind,
        pixelWidth: Int(family.artworkSize.width * 2),
        pixelHeight: Int(family.artworkSize.height * 2)
      ),
      pipeline: artworkPipeline
    )
    .frame(width: family.artworkSize.width, height: family.artworkSize.height)
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
    .overlay(alignment: .topLeading) {
      if family == .live {
        Text("LIVE")
          .aevynoTypography(.eyebrow)
          .foregroundStyle(.white)
          .padding(.horizontal, AEVYNOSpacing.sm)
          .padding(.vertical, AEVYNOSpacing.xs)
          .background(Color.black.opacity(0.7), in: Capsule())
          .padding(AEVYNOSpacing.sm)
          .accessibilityHidden(true)
      }
    }
    .overlay(alignment: .bottom) {
      if let progress = item.progress {
        ProgressView(value: progress)
          .tint(AEVYNOColor.accent)
          .background(Color.black.opacity(0.35))
          .padding(.horizontal, AEVYNOSpacing.sm)
          .padding(.bottom, AEVYNOSpacing.sm)
          .accessibilityHidden(true)
      }
    }
  }

  private var accessibilityValue: String {
    var values = [item.subtitle]
    if family == .live { values.append("Live") }
    if let progress = item.progress {
      values.append("\(Int(progress * 100)) percent complete")
    }
    return values.joined(separator: ", ")
  }
}

struct TVMediaButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.84 : 1)
  }
}
