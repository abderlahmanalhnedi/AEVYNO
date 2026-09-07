import CloudSync
import DesignSystem
import Domain
import IPTVCore
import Library
import Persistence
import Playback
import Security
import Testing

@Test("All Phase 0 module boundaries compile and import")
func sharedModuleBoundariesImport() {
    #expect(Bool(true))
}

@Test("Mock Home content is deterministic and complete")
func mockHomeSectionsAreDeterministic() async throws {
    let repository = MockHomeRepository()

    let firstLoad = try await repository.fetchHomeSections()
    let secondLoad = try await repository.fetchHomeSections()

    #expect(firstLoad == secondLoad)
    #expect(firstLoad.map(\.id) == HomeSectionKind.allCases)
    #expect(firstLoad.allSatisfy { !$0.items.isEmpty })
    #expect(Set(firstLoad.flatMap(\.items).map(\.id)).count == firstLoad.flatMap(\.items).count)
}

@Test("Home loader resolves loaded and empty states")
func homeLoaderResolvesContentStates() async {
    let loaded = HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: MockHomeRepository())
    )
    let empty = HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: MockHomeRepository(sections: []))
    )

    #expect(await loaded.load() == .loaded(MockHomeRepository.previewSections))
    #expect(await empty.load() == .empty)
}

@Test("Home loader maps implementation errors to a safe display state")
func homeLoaderMapsErrors() async {
    let loader = HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: FailingHomeRepository())
    )

    #expect(
        await loader.load() == .failure(
            HomeDisplayError(
                title: "Home is unavailable",
                message: "Please try loading the preview again."
            )
        )
    )
}

private struct FailingHomeRepository: HomeRepository {
    func fetchHomeSections() async throws -> [HomeSection] {
        throw SyntheticFailure()
    }
}

private struct SyntheticFailure: Error {}
