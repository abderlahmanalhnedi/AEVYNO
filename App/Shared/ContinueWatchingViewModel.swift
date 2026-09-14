import Library
import Observation

@MainActor
@Observable
final class ContinueWatchingViewModel {
  typealias ServiceFactory = @Sendable () async throws -> any ContinueWatchingServing

  private let serviceFactory: ServiceFactory
  private var revisionTask: Task<Void, Never>?
  private var service: (any ContinueWatchingServing)?
  private(set) var items: [ContinueWatchingItemPresentation] = []

  init(serviceFactory: @escaping ServiceFactory) {
    self.serviceFactory = serviceFactory
  }

  func reload() async {
    do {
      let service = try await resolvedService()
      items = try await service.items()
    } catch is CancellationError {
      return
    } catch {
      // Continue Watching is supplementary: preserve a usable library if it cannot load.
      items = []
    }
  }

  private func resolvedService() async throws -> any ContinueWatchingServing {
    if let service { return service }
    let service = try await serviceFactory()
    self.service = service
    revisionTask = Task { [weak self, service] in
      let revisions = await service.revisions()
      for await _ in revisions {
        guard !Task.isCancelled, let self else { return }
        await self.reload()
      }
    }
    return service
  }
}

actor EmptyContinueWatchingService: ContinueWatchingServing {
  func items() -> [ContinueWatchingItemPresentation] { [] }
  func revisions() -> AsyncStream<UInt64> { AsyncStream { $0.finish() } }
}
