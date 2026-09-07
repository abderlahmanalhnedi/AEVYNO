import Domain
import SwiftUI

public struct ArtworkPlaceholder: View {
    private let theme: ArtworkTheme
    private let kind: MediaKind

    public init(theme: ArtworkTheme, kind: MediaKind) {
        self.theme = theme
        self.kind = kind
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 150, height: 150)
                .offset(x: 90, y: -45)

            Image(systemName: symbolName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
        }
    }

    private var symbolName: String {
        switch kind {
        case .movie:
            return "film.stack"
        case .series:
            return "rectangle.stack"
        case .liveChannel:
            return "dot.radiowaves.left.and.right"
        }
    }

    private var colors: [Color] {
        switch theme {
        case .aurora:
            return [Color.indigo, Color.cyan.opacity(0.8)]
        case .ember:
            return [Color(red: 0.35, green: 0.06, blue: 0.12), Color.orange]
        case .lagoon:
            return [Color(red: 0.02, green: 0.2, blue: 0.3), Color.teal]
        case .meadow:
            return [Color(red: 0.05, green: 0.22, blue: 0.14), Color.green.opacity(0.75)]
        case .midnight:
            return [Color(red: 0.04, green: 0.04, blue: 0.12), Color.purple.opacity(0.8)]
        case .solar:
            return [Color(red: 0.35, green: 0.16, blue: 0.02), Color.yellow.opacity(0.75)]
        }
    }
}
