import DesignSystem
import SwiftUI

struct TVHomeHero: View {
  var body: some View {
    HStack(alignment: .bottom, spacing: AEVYNOSpacing.xl) {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
        Text(AppText.appName)
          .aevynoTypography(.eyebrow)
          .tracking(4)
          .foregroundStyle(AEVYNOColor.accent)

        Text(AppText.homeHeroTitle)
          .aevynoTypography(.hero)
          .foregroundStyle(AEVYNOColor.primaryText)

        Text(AppText.homeHeroSubtitle)
          .aevynoTypography(.status)
          .foregroundStyle(AEVYNOColor.secondaryText)
      }

      Spacer(minLength: AEVYNOSpacing.xl)

      ZStack {
        Circle()
          .fill(AEVYNOColor.accent.opacity(0.18))
          .frame(width: 210, height: 210)

        Circle()
          .strokeBorder(
            AngularGradient(
              colors: [
                AEVYNOColor.accent, .clear, AEVYNOColor.accentWarm, .clear, AEVYNOColor.accent,
              ],
              center: .center
            ),
            lineWidth: 3
          )
          .frame(width: 150, height: 150)

        Circle()
          .fill(Color.white.opacity(0.9))
          .frame(width: 18, height: 18)
          .offset(x: 62, y: -42)
      }
      .accessibilityHidden(true)
    }
    .padding(.horizontal, AEVYNOSpacing.xl)
    .padding(.vertical, AEVYNOSpacing.lg)
    .frame(maxWidth: .infinity, minHeight: 270, alignment: .leading)
    .background(
      LinearGradient(
        colors: [Color.white.opacity(0.07), AEVYNOColor.accent.opacity(0.025)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: AEVYNOCornerRadius.hero, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: AEVYNOCornerRadius.hero, style: .continuous)
        .stroke(AEVYNOColor.hairline, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(AppText.homeHeroAccessibilityLabel)
  }
}
