import SwiftUI

public struct AEVYNOCardSurface: ViewModifier {
  public init() {}

  public func body(content: Content) -> some View {
    content
      .background(AEVYNOColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
  }
}

extension View {
  public func aevynoCardSurface() -> some View {
    modifier(AEVYNOCardSurface())
  }
}

#if os(tvOS)
  public struct AEVYNOTVFocusTreatment: ViewModifier {
    private let isFocused: Bool
    private let reduceMotion: Bool

    public init(isFocused: Bool, reduceMotion: Bool) {
      self.isFocused = isFocused
      self.reduceMotion = reduceMotion
    }

    public func body(content: Content) -> some View {
      content
        .overlay {
          RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous)
            .stroke(
              isFocused ? Color.white.opacity(0.92) : AEVYNOColor.hairline,
              lineWidth: isFocused ? 4 : 1)
        }
        .scaleEffect(isFocused ? 1.025 : 1)
        .shadow(color: isFocused ? Color.black.opacity(0.55) : .clear, radius: 22, y: 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
  }

  extension View {
    public func aevynoTVFocusTreatment(isFocused: Bool, reduceMotion: Bool) -> some View {
      modifier(AEVYNOTVFocusTreatment(isFocused: isFocused, reduceMotion: reduceMotion))
    }
  }
#endif
