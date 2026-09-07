import SwiftUI

public enum AEVYNOSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 20
    public static let lg: CGFloat = 32
    public static let xl: CGFloat = 48
    public static let xxl: CGFloat = 72
}

public enum AEVYNOCornerRadius {
    public static let card: CGFloat = 20
    public static let panel: CGFloat = 28
}

public enum AEVYNOColor {
    public static let background = Color(red: 0.025, green: 0.035, blue: 0.065)
    public static let surface = Color.white.opacity(0.09)
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.68)
    public static let accent = Color(red: 0.47, green: 0.86, blue: 0.93)
}

public enum AEVYNOTypographyRole {
    case hero
    case sectionTitle
    case cardTitle
    case metadata
    case status

    fileprivate var font: Font {
        switch self {
        case .hero:
            return .system(.largeTitle, design: .rounded, weight: .bold)
        case .sectionTitle:
            return .system(.title2, design: .rounded, weight: .semibold)
        case .cardTitle:
            return .system(.headline, design: .rounded, weight: .semibold)
        case .metadata:
            return .system(.subheadline, design: .rounded, weight: .medium)
        case .status:
            return .system(.body, design: .rounded, weight: .regular)
        }
    }
}

public extension View {
    func aevynoTypography(_ role: AEVYNOTypographyRole) -> some View {
        font(role.font)
    }
}
