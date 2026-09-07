import Domain
import Foundation

public protocol HomeRepository: Sendable {
    func fetchHomeSections() async throws -> [HomeSection]
}

public struct FetchHomeSections: Sendable {
    private let repository: any HomeRepository

    public init(repository: any HomeRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> [HomeSection] {
        try await repository.fetchHomeSections()
    }
}
