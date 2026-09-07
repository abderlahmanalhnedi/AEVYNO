import Foundation

public struct HomeSection: Identifiable, Hashable, Sendable {
    public let id: HomeSectionKind
    public let title: String
    public let items: [MediaItem]

    public init(id: HomeSectionKind, title: String, items: [MediaItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public enum HomeSectionKind: String, CaseIterable, Hashable, Codable, Sendable {
    case continueWatching
    case movies
    case series
    case liveTV
    case favorites
}
