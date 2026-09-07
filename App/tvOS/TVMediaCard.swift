import DesignSystem
import Domain
import SwiftUI

struct TVMediaCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: MediaItem
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
            ArtworkPlaceholder(theme: item.artworkTheme, kind: item.kind)
                .frame(width: 320, height: 180)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AEVYNOCornerRadius.card,
                        style: .continuous
                    )
                )
                .overlay(alignment: .bottom) {
                    if let progress = item.progress {
                        ProgressView(value: progress)
                            .tint(AEVYNOColor.accent)
                            .padding(.horizontal, AEVYNOSpacing.sm)
                            .padding(.bottom, AEVYNOSpacing.sm)
                            .accessibilityHidden(true)
                    }
                }

            Text(item.title)
                .aevynoTypography(.cardTitle)
                .foregroundStyle(AEVYNOColor.primaryText)
                .lineLimit(1)

            Text(item.subtitle)
                .aevynoTypography(.metadata)
                .foregroundStyle(AEVYNOColor.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
        .padding(AEVYNOSpacing.sm)
        .aevynoCardSurface()
        .aevynoTVFocusTreatment(isFocused: isFocused, reduceMotion: reduceMotion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let progress = item.progress else { return item.subtitle }
        return "\(item.subtitle), \(Int(progress * 100)) percent complete"
    }
}

struct TVMediaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
