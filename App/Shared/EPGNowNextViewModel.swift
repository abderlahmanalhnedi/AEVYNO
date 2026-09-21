import Domain
import Foundation
import Library
import Observation

enum EPGPresentationError: Error { case unavailable }

@MainActor
@Observable
final class EPGNowNextViewModel {
  typealias ServiceFactory = @Sendable () async throws -> any EPGPresenting

  private let itemID: String
  private let serviceFactory: ServiceFactory
  private(set) var presentation = EPGNowNextPresentation(now: nil, next: nil)

  init(itemID: String, serviceFactory: @escaping ServiceFactory) {
    self.itemID = itemID
    self.serviceFactory = serviceFactory
  }

  func load() async {
    do {
      let service = try await serviceFactory()
      presentation = try await service.nowNext(for: itemID, at: Date())
    } catch {
      // EPG is an optional local enrichment; details remain available without it.
      presentation = EPGNowNextPresentation(now: nil, next: nil)
    }
  }
}
