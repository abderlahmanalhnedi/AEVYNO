import Foundation
import Library
import Observation

@MainActor @Observable
final class FavoritesViewModel {
  typealias ServiceFactory = @Sendable () async throws -> any FavoritesServing
  private let serviceFactory: ServiceFactory
  private var service: (any FavoritesServing)?
  private var revisionTask: Task<Void, Never>?
  private(set) var items: [FavoriteItemPresentation] = []
  init(serviceFactory: @escaping ServiceFactory) { self.serviceFactory = serviceFactory }
  func reload() async { do { items = try await resolved().items() } catch { items = [] } }
  func isFavorite(_ id: String) async -> Bool {
    (try? await resolved().isFavorite(mediaID: id)) ?? false
  }
  func toggle(_ id: String) async -> Bool? {
    do {
      let value = try await resolved().toggle(mediaID: id, at: .now)
      await reload()
      return value
    } catch { return nil }
  }
  private func resolved() async throws -> any FavoritesServing {
    if let service { return service }
    let value = try await serviceFactory()
    service = value
    revisionTask = Task { [weak self, value] in
      for await _ in await value.revisions() { await self?.reload() }
    }
    return value
  }
}

actor EmptyFavoritesService: FavoritesServing {
  func items() -> [FavoriteItemPresentation] { [] }
  func isFavorite(mediaID _: String) -> Bool { false }
  func toggle(mediaID _: String, at _: Date) -> Bool { false }
  func revisions() -> AsyncStream<UInt64> { AsyncStream { $0.finish() } }
}
