import CloudSync
import Domain
import Foundation
import Persistence
import Testing

@Suite("Favorite continuity", .serialized)
struct FavoriteSyncTests {
  @Test("Durable local add, remove, reopen, and deterministic ordering")
  func durableLocalState() async throws {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("favorites.json")
    let repository = FileFavoriteRepository(url: url)
    try await repository.add(Favorite(mediaID: "z", updatedAt: .distantPast))
    try await repository.add(Favorite(mediaID: "a", updatedAt: .distantPast))
    #expect(try await repository.allFavorites().map(\.mediaID) == ["a", "z"])
    try await repository.remove(mediaID: "z")
    let reopened = FileFavoriteRepository(url: url)
    #expect(try await reopened.allFavorites().map(\.mediaID) == ["a"])
  }

  @Test("Duplicate adds and removes are idempotent")
  func idempotency() async throws {
    let local = MemoryFavorites()
    let coordinator = makeCoordinator(local: local, cloud: FakeFavoriteCloud())
    let repository = LocalFirstCloudFavoriteRepository(
      localRepository: local, coordinator: coordinator)
    let favorite = Favorite(mediaID: "media", updatedAt: .distantPast)
    try await repository.add(favorite)
    try await repository.add(favorite)
    #expect(try await repository.allFavorites() == [favorite])
    try await repository.remove(mediaID: "media")
    try await repository.remove(mediaID: "media")
    #expect(try await repository.allFavorites().isEmpty)
  }

  @Test("Tombstone defeats stale add and a later re-add advances the version")
  func tombstoneAndRefavorite() throws {
    let add = record(removed: false, revision: 1, id: "old-add")
    let remove = record(removed: true, revision: 2, id: "remove")
    #expect(try FavoriteConflictResolver.resolve(add, remove) == remove)
    #expect(try FavoriteConflictResolver.resolve(remove, add) == remove)
    let simultaneousAdd = record(removed: false, revision: 2, id: "same-generation-add")
    #expect(try FavoriteConflictResolver.resolve(simultaneousAdd, remove) == remove)
    let refavorite = record(removed: false, revision: 3, id: "intentional-later-add")
    #expect(try FavoriteConflictResolver.resolve(remove, refavorite) == refavorite)
  }

  @Test("Offline and account-unavailable writes preserve local intent and publish on reconnect")
  func reconnect() async throws {
    let local = MemoryFavorites()
    let cloud = FakeFavoriteCloud(availability: .noAccount)
    let coordinator = makeCoordinator(local: local, cloud: cloud)
    let repository = LocalFirstCloudFavoriteRepository(
      localRepository: local, coordinator: coordinator)
    try await repository.add(Favorite(mediaID: "media", updatedAt: .distantPast))
    await coordinator.synchronize()
    #expect(try await repository.favorite(for: "media") != nil)
    #expect(await coordinator.status == .unavailable(.noAccount))
    await cloud.setAvailability(.available)
    await coordinator.synchronize()
    #expect(await cloud.saved.map(\.mediaID) == ["media"])
  }

  @Test("Cloud failures and stale sync generation cannot erase local favorites")
  func failureAndStaleGeneration() async throws {
    let favorite = Favorite(mediaID: "media", updatedAt: .distantPast)
    let local = MemoryFavorites(values: [favorite])
    let cloud = FakeFavoriteCloud(error: .networkUnavailable)
    let coordinator = makeCoordinator(local: local, cloud: cloud, attempts: 1)
    await coordinator.synchronize()
    #expect(await local.favorite(for: "media") == favorite)
    #expect(await coordinator.status == .failed)
    await coordinator.cancelSynchronization()
    #expect(await local.favorite(for: "media") == favorite)
  }

  @Test("Cloud model contains stable identity and operation metadata only")
  func cloudModelPrivacyBoundary() {
    let encoded = String(
      data: try! JSONEncoder().encode(record(removed: false, revision: 1, id: "op")),
      encoding: .utf8)!
    #expect(!encoded.contains("url"))
    #expect(!encoded.contains("credential"))
    #expect(!encoded.contains("artwork"))
  }

  private func makeCoordinator(local: MemoryFavorites, cloud: FakeFavoriteCloud, attempts: Int = 3)
    -> FavoriteSyncCoordinator
  {
    FavoriteSyncCoordinator(
      localRepository: local, cloudStore: cloud, stateStore: MemoryFavoriteState(),
      retryPolicy: .init(maximumAttempts: attempts, initialDelay: 0))
  }
  private func record(removed: Bool, revision: UInt64, id: String) -> CloudFavoriteRecord {
    .init(
      mediaID: "media", isRemoved: removed, updatedAt: .distantPast, logicalRevision: revision,
      operationID: id)
  }
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

private actor MemoryFavorites: FavoriteRepository {
  var values: [String: Favorite]
  init(values: [Favorite] = []) {
    self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.mediaID, $0) })
  }
  func favorite(for mediaID: String) -> Favorite? { values[mediaID] }
  func allFavorites() -> [Favorite] { values.values.sorted { $0.mediaID < $1.mediaID } }
  func add(_ favorite: Favorite) { values[favorite.mediaID] = favorite }
  func remove(mediaID: String) { values.removeValue(forKey: mediaID) }
}

private actor MemoryFavoriteState: FavoriteSyncStateStore {
  var value = FavoriteSyncSnapshot()
  func load() -> FavoriteSyncSnapshot { value }
  func save(_ snapshot: FavoriteSyncSnapshot) { value = snapshot }
}

private actor FakeFavoriteCloud: CloudFavoriteStore {
  var availability: CloudAccountAvailability
  var error: CloudProgressStoreError?
  var saved: [CloudFavoriteRecord] = []
  init(availability: CloudAccountAvailability = .available, error: CloudProgressStoreError? = nil) {
    self.availability = availability
    self.error = error
  }
  func setAvailability(_ value: CloudAccountAvailability) { availability = value }
  func accountAvailability() -> CloudAccountAvailability { availability }
  func fetchChanges(since: Data?) throws -> CloudFavoriteChangeBatch {
    if let error { throw error }
    return .init(records: [], changeToken: Data("token".utf8))
  }
  func save(_ records: [CloudFavoriteRecord]) throws -> [CloudFavoriteRecord] {
    if let error { throw error }
    saved += records
    return records
  }
}
