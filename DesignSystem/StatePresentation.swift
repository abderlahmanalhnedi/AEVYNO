import SwiftUI

public struct LoadingPlaceholder: View {
  public init() {}

  public var body: some View {
    RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous)
      .fill(AEVYNOColor.surface)
      .overlay(alignment: .bottomLeading) {
        VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
          Capsule().fill(Color.white.opacity(0.14)).frame(width: 150, height: 14)
          Capsule().fill(Color.white.opacity(0.08)).frame(width: 95, height: 10)
        }
        .padding(AEVYNOSpacing.md)
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

public struct StatusPanel: View {
  private let symbolName: String
  private let title: String
  private let message: String
  private let actionTitle: String?
  private let actionAccessibilityHint: String?
  private let action: (() -> Void)?

  public init(
    symbolName: String,
    title: String,
    message: String,
    actionTitle: String? = nil,
    actionAccessibilityHint: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.symbolName = symbolName
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
    self.actionAccessibilityHint = actionAccessibilityHint
    self.action = action
  }

  public var body: some View {
    VStack(spacing: AEVYNOSpacing.md) {
      Image(systemName: symbolName)
        .font(.system(size: 42, weight: .semibold))
        .foregroundStyle(AEVYNOColor.accent)
        .accessibilityHidden(true)

      Text(title)
        .aevynoTypography(.sectionTitle)
        .foregroundStyle(AEVYNOColor.primaryText)

      Text(message)
        .aevynoTypography(.status)
        .foregroundStyle(AEVYNOColor.secondaryText)
        .multilineTextAlignment(.center)

      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .tint(AEVYNOColor.accent)
          .accessibilityIdentifier("home.retry")
          .accessibilityHint(actionAccessibilityHint ?? "")
      }
    }
    .padding(AEVYNOSpacing.xl)
    .frame(maxWidth: 620)
    .background(AEVYNOColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
    .accessibilityElement(children: .contain)
  }
}
