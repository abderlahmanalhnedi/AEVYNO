import DesignSystem
import SwiftUI

struct TVHomeLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AEVYNOSpacing.xl) {
            VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
                Text("AEVYNO")
                    .aevynoTypography(.hero)
                    .foregroundStyle(AEVYNOColor.primaryText)
                Text("Preparing your preview")
                    .aevynoTypography(.status)
                    .foregroundStyle(AEVYNOColor.secondaryText)
            }

            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
                    Capsule()
                        .fill(AEVYNOColor.surface)
                        .frame(width: 230, height: 24)

                    LazyHStack(spacing: AEVYNOSpacing.lg) {
                        ForEach(0..<4, id: \.self) { _ in
                            LoadingPlaceholder()
                                .frame(width: 344, height: 252)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AEVYNOSpacing.xxl)
        .padding(.vertical, AEVYNOSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("home.loading")
    }
}
