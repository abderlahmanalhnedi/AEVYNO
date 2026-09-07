import DesignSystem
import SwiftUI

struct TVHomeLoadingView: View {
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.xl) {
        LoadingPlaceholder()
          .frame(height: 270)

        loadingRail(cardSize: CGSize(width: 390, height: 300))
        loadingRail(cardSize: CGSize(width: 238, height: 437))
      }
      .padding(.horizontal, AEVYNOSpacing.xxl)
      .padding(.vertical, AEVYNOSpacing.xl)
    }
    .scrollDisabled(true)
    .accessibilityIdentifier("home.loading")
    .accessibilityLabel("Loading Home preview")
  }

  private func loadingRail(cardSize: CGSize) -> some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      Capsule()
        .fill(AEVYNOColor.surface)
        .frame(width: 250, height: 28)

      LazyHStack(spacing: AEVYNOSpacing.lg) {
        ForEach(0..<5, id: \.self) { _ in
          LoadingPlaceholder()
            .frame(width: cardSize.width, height: cardSize.height)
        }
      }
    }
  }
}
