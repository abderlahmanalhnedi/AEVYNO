import Domain
import Foundation

public struct MockHomeRepository: HomeRepository {
  public enum Scenario: Sendable {
    case loaded
    case empty
    case failure
    case prolongedLoading
  }

  private let scenario: Scenario
  private let sections: [HomeSection]

  public init(
    sections: [HomeSection] = MockHomeRepository.previewSections,
    scenario: Scenario = .loaded
  ) {
    self.scenario = scenario
    self.sections = sections
  }

  public func fetchHomeSections() async throws -> [HomeSection] {
    switch scenario {
    case .loaded:
      return sections
    case .empty:
      return []
    case .failure:
      throw MockHomeFailure()
    case .prolongedLoading:
      try await Task.sleep(for: .seconds(60))
      return sections
    }
  }

  public static let previewSections: [HomeSection] = [
    HomeSection(
      id: .continueWatching,
      title: "Continue Watching",
      items: [
        item(
          "continue-orbit", "Orbit Archive 17", "42 min remaining", .series, .aurora, 0.58,
          ["2026", "Series", "51 min"],
          "A cartographer follows a repeating signal beyond the edge of a carefully mapped orbital archive."
        ),
        item(
          "continue-harbor", "Harbor Study 08", "18 min remaining", .movie, .lagoon, 0.73,
          ["2025", "Film", "1 hr 44 min"],
          "A quiet coastal study becomes a luminous record of movement, memory and changing tides."),
        item(
          "continue-cinder", "Cinder Atlas 04", "Episode 4", .series, .ember, 0.31,
          ["2026", "Series", "48 min"],
          "An archivist uncovers a hand-drawn atlas that seems to redraw the city each night."),
      ]
    ),
    HomeSection(
      id: .movies,
      title: "Movies",
      items: [
        item(
          "movie-vector", "Silent Vector 29", "Science fiction", .movie, .midnight, nil,
          ["2026", "PG", "1 hr 58 min"],
          "A research pilot traces a silent vector through a synthetic night sky and finds an unexpected second route home."
        ),
        item(
          "movie-meadow", "Meadow Signal 12", "Drama", .movie, .meadow, nil,
          ["2025", "PG", "1 hr 39 min"],
          "Two distant field stations communicate through patterns of light across an endless green plain."
        ),
        item(
          "movie-solar", "Solar Cartography 06", "Documentary", .movie, .solar, nil,
          ["2026", "G", "1 hr 22 min"],
          "An imagined expedition maps the textures, rhythms and quiet geometry of a miniature solar system."
        ),
        item(
          "movie-lagoon", "Lagoon Transit 31", "Adventure", .movie, .lagoon, nil,
          ["2024", "PG", "1 hr 47 min"],
          "A midnight transit across glasslike water leads a small crew toward a city that appears only at dawn."
        ),
      ]
    ),
    HomeSection(
      id: .series,
      title: "Series",
      items: [
        item(
          "series-aurora", "Aurora Index 23", "Season 1", .series, .aurora, nil,
          ["2026", "8 episodes", "Drama"],
          "A team of observers catalogs impossible colors appearing over a remote northern station."
        ),
        item(
          "series-ember", "Ember District 14", "Season 2", .series, .ember, nil,
          ["2025", "10 episodes", "Mystery"],
          "Neighbors rebuild an experimental district while tracing the source of a warm light beneath its streets."
        ),
        item(
          "series-midnight", "Midnight Survey 05", "Limited series", .series, .midnight, nil,
          ["2026", "6 episodes", "Documentary"],
          "A synthetic field journal follows six nights of careful observation in a city after dark."
        ),
      ]
    ),
    HomeSection(
      id: .liveTV,
      title: "Live TV",
      items: [
        item(
          "live-field", "Field Notes Live", "Now: Studio Session", .liveChannel, .meadow, nil,
          ["Live", "Arts", "All ages"],
          "A continuous synthetic studio feed featuring calm sessions with designers, makers and musicians."
        ),
        item(
          "live-horizon", "Horizon Desk", "Now: Evening Brief", .liveChannel, .solar, nil,
          ["Live", "Culture", "All ages"],
          "An original demonstration channel presenting concise fictional dispatches from across the horizon."
        ),
        item(
          "live-current", "Current Lab", "Now: Design Review", .liveChannel, .lagoon, nil,
          ["Live", "Design", "All ages"],
          "A fictional live lab where small teams review objects, spaces and interaction experiments."
        ),
      ]
    ),
    HomeSection(
      id: .favorites,
      title: "Favorites",
      items: [
        item(
          "favorite-compass", "Compass Room 09", "Saved series", .series, .aurora, nil,
          ["2025", "Series", "Adventure"],
          "Four travelers compare the rooms their compasses reveal at the center of a shifting landscape."
        ),
        item(
          "favorite-afterglow", "Afterglow File 18", "Saved movie", .movie, .ember, nil,
          ["2026", "Film", "1 hr 32 min"],
          "A conservator studies the color left behind by a vanished installation and the stories held within it."
        ),
        item(
          "favorite-relay", "Relay Studio", "Saved channel", .liveChannel, .midnight, nil,
          ["Live", "Studio", "All ages"],
          "A fictional channel carrying collaborative performances between small studios around the world."
        ),
      ]
    ),
  ]

  private static func item(
    _ id: String,
    _ title: String,
    _ subtitle: String,
    _ kind: MediaKind,
    _ theme: ArtworkTheme,
    _ progress: Double? = nil,
    _ facts: [String] = [],
    _ summary: String = "A synthetic AEVYNO preview created for interface testing."
  ) -> MediaItem {
    MediaItem(
      id: MediaItem.ID(rawValue: id),
      title: title,
      subtitle: subtitle,
      kind: kind,
      artworkTheme: theme,
      progress: progress,
      facts: facts,
      summary: summary
    )
  }
}

private struct MockHomeFailure: Error {}
