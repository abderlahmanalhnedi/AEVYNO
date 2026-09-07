import Domain
import Foundation

public struct SyntheticCatalogFixture: Sendable {
  public enum Scale: Int, CaseIterable, Sendable {
    case tenThousand = 10_000
    case fiftyThousand = 50_000
    case oneHundredThousand = 100_000
  }

  public let scale: Scale
  public let seed: UInt64

  public init(scale: Scale, seed: UInt64 = 0xAE_71_90) {
    self.scale = scale
    self.seed = seed
  }

  public var count: Int { scale.rawValue }

  public func item(at index: Int) -> MediaItem? {
    guard (0..<count).contains(index) else { return nil }

    let value = mixedValue(for: index)
    let kind = MediaKind.allFixtureCases[Int(value % 3)]
    let theme = ArtworkTheme.allCases[Int((value >> 8) % UInt64(ArtworkTheme.allCases.count))]
    let serial = String(format: "%05d", index + 1)

    return MediaItem(
      id: MediaItem.ID(rawValue: "stress-\(scale.rawValue)-\(index)"),
      title: "Synthetic Field \(serial)",
      subtitle: subtitle(for: kind, value: value),
      kind: kind,
      artworkTheme: theme,
      progress: index.isMultiple(of: 7) ? Double(value % 90 + 5) / 100 : nil,
      facts: ["Fixture", "Index \(index)", "Seed \(seed)"],
      summary:
        "Deterministic synthetic catalog entry \(serial), generated for large-list UI and query profiling without remote media or metadata."
    )
  }

  public func items(in range: Range<Int>) -> [MediaItem] {
    let lowerBound = max(0, range.lowerBound)
    let upperBound = min(count, range.upperBound)
    guard lowerBound < upperBound else { return [] }
    return (lowerBound..<upperBound).compactMap(item(at:))
  }

  public func homeSnapshot(itemsPerSection: Int = 120) -> [HomeSection] {
    let boundedCount = min(max(itemsPerSection, 1), 400)
    let stride = max(count / HomeSectionKind.allCases.count, boundedCount)

    return HomeSectionKind.allCases.enumerated().map { sectionIndex, kind in
      let start = min(sectionIndex * stride, count - boundedCount)
      return HomeSection(
        id: kind,
        title: kind.displayTitle,
        items: items(in: start..<(start + boundedCount))
      )
    }
  }

  private func mixedValue(for index: Int) -> UInt64 {
    var value = UInt64(index) &+ seed &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  private func subtitle(for kind: MediaKind, value: UInt64) -> String {
    switch kind {
    case .movie:
      return "Synthetic film · \(80 + value % 61) min"
    case .series:
      return "Synthetic series · Season \(1 + value % 8)"
    case .liveChannel:
      return "Live fixture · Channel \(1 + value % 300)"
    }
  }
}

public struct SyntheticLargeCatalogHomeRepository: HomeRepository {
  private let fixture: SyntheticCatalogFixture
  private let itemsPerSection: Int

  public init(
    scale: SyntheticCatalogFixture.Scale = .tenThousand,
    itemsPerSection: Int = 160,
    seed: UInt64 = 0xAE_71_90
  ) {
    fixture = SyntheticCatalogFixture(scale: scale, seed: seed)
    self.itemsPerSection = itemsPerSection
  }

  public func fetchHomeSections() async throws -> [HomeSection] {
    await Task.yield()
    try Task.checkCancellation()
    return fixture.homeSnapshot(itemsPerSection: itemsPerSection)
  }
}

extension MediaKind {
  fileprivate static let allFixtureCases: [MediaKind] = [.movie, .series, .liveChannel]
}

extension HomeSectionKind {
  fileprivate var displayTitle: String {
    switch self {
    case .continueWatching: return "Continue Watching"
    case .movies: return "Movies"
    case .series: return "Series"
    case .liveTV: return "Live TV"
    case .favorites: return "Favorites"
    }
  }
}
