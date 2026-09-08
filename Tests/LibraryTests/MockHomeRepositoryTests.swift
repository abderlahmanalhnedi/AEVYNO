import AEVYNOSecurity
import CloudSync
import DesignSystem
import Domain
import IPTVCore
import Library
import Persistence
import Playback
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
  #expect(firstLoad.flatMap(\.items).allSatisfy { !$0.facts.isEmpty && !$0.summary.isEmpty })
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
    await loader.load()
      == .failure(
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

@Test("Synthetic catalog supports deterministic 10k, 50k and 100k address spaces")
func syntheticCatalogIsDeterministicAtEachScale() {
  for scale in SyntheticCatalogFixture.Scale.allCases {
    let first = SyntheticCatalogFixture(scale: scale, seed: 42)
    let second = SyntheticCatalogFixture(scale: scale, seed: 42)

    #expect(first.count == scale.rawValue)
    #expect(first.item(at: 0) == second.item(at: 0))
    #expect(first.item(at: scale.rawValue - 1) == second.item(at: scale.rawValue - 1))
    #expect(first.item(at: -1) == nil)
    #expect(first.item(at: scale.rawValue) == nil)
  }
}

@Test("Synthetic catalog IDs are unique across every supported address space")
func syntheticCatalogIDsAreUniqueAcrossSupportedScales() throws {
  var ids = Set<MediaItem.ID>()
  ids.reserveCapacity(SyntheticCatalogFixture.Scale.allCases.reduce(0) { $0 + $1.rawValue })

  for scale in SyntheticCatalogFixture.Scale.allCases {
    let fixture = SyntheticCatalogFixture(scale: scale, seed: 42)
    for index in 0..<fixture.count {
      let item = try #require(fixture.item(at: index))
      #expect(ids.insert(item.id).inserted)
    }
  }

  #expect(ids.count == 160_000)
}

@Test("Large-catalog Home snapshot stays bounded and preserves stable IDs")
func syntheticCatalogHomeSnapshotIsBounded() {
  let fixture = SyntheticCatalogFixture(scale: .oneHundredThousand)
  let sections = fixture.homeSnapshot(itemsPerSection: 160)
  let items = sections.flatMap(\.items)

  #expect(sections.map(\.id) == HomeSectionKind.allCases)
  #expect(sections.allSatisfy { $0.items.count == 160 })
  #expect(items.count == 800)
  #expect(Set(items.map(\.id)).count == items.count)
}
