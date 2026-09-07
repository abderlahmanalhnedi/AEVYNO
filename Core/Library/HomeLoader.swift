import Domain
import Foundation

public enum HomeLoadState: Equatable, Sendable {
    case loading
    case loaded([HomeSection])
    case empty
    case failure(HomeDisplayError)
}

public struct HomeDisplayError: Error, Equatable, Sendable {
    public let title: String
    public let message: String

    public init(
        title: String = "Home is unavailable",
        message: String = "Please try loading the preview again."
    ) {
        self.title = title
        self.message = message
    }
}

public struct HomeLoader: Sendable {
    private let fetchHomeSections: FetchHomeSections

    public init(fetchHomeSections: FetchHomeSections) {
        self.fetchHomeSections = fetchHomeSections
    }

    public func load() async -> HomeLoadState {
        do {
            let sections = try await fetchHomeSections()
            return sections.isEmpty ? .empty : .loaded(sections)
        } catch {
            return .failure(HomeDisplayError())
        }
    }
}
