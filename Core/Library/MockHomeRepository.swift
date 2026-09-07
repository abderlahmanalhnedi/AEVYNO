import Domain
import Foundation

public struct MockHomeRepository: HomeRepository {
    private let sections: [HomeSection]

    public init(sections: [HomeSection] = MockHomeRepository.previewSections) {
        self.sections = sections
    }

    public func fetchHomeSections() async throws -> [HomeSection] {
        sections
    }

    public static let previewSections: [HomeSection] = [
        HomeSection(
            id: .continueWatching,
            title: "Continue Watching",
            items: [
                item("continue-orbit", "Orbit Archive 17", "42 min remaining", .series, .aurora, 0.58),
                item("continue-harbor", "Harbor Study 08", "18 min remaining", .movie, .lagoon, 0.73),
                item("continue-cinder", "Cinder Atlas 04", "Episode 4", .series, .ember, 0.31)
            ]
        ),
        HomeSection(
            id: .movies,
            title: "Movies",
            items: [
                item("movie-vector", "Silent Vector 29", "Science fiction", .movie, .midnight),
                item("movie-meadow", "Meadow Signal 12", "Drama", .movie, .meadow),
                item("movie-solar", "Solar Cartography 06", "Documentary", .movie, .solar),
                item("movie-lagoon", "Lagoon Transit 31", "Adventure", .movie, .lagoon)
            ]
        ),
        HomeSection(
            id: .series,
            title: "Series",
            items: [
                item("series-aurora", "Aurora Index 23", "Season 1", .series, .aurora),
                item("series-ember", "Ember District 14", "Season 2", .series, .ember),
                item("series-midnight", "Midnight Survey 05", "Limited series", .series, .midnight)
            ]
        ),
        HomeSection(
            id: .liveTV,
            title: "Live TV",
            items: [
                item("live-field", "Field Notes Live", "Now: Studio Session", .liveChannel, .meadow),
                item("live-horizon", "Horizon Desk", "Now: Evening Brief", .liveChannel, .solar),
                item("live-current", "Current Lab", "Now: Design Review", .liveChannel, .lagoon)
            ]
        ),
        HomeSection(
            id: .favorites,
            title: "Favorites",
            items: [
                item("favorite-compass", "Compass Room 09", "Saved series", .series, .aurora),
                item("favorite-afterglow", "Afterglow File 18", "Saved movie", .movie, .ember),
                item("favorite-relay", "Relay Studio", "Saved channel", .liveChannel, .midnight)
            ]
        )
    ]

    private static func item(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ kind: MediaKind,
        _ theme: ArtworkTheme,
        _ progress: Double? = nil
    ) -> MediaItem {
        MediaItem(
            id: MediaItem.ID(rawValue: id),
            title: title,
            subtitle: subtitle,
            kind: kind,
            artworkTheme: theme,
            progress: progress
        )
    }
}
