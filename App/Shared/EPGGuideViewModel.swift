import Domain
import Foundation
import Library
import Observation

@MainActor
@Observable
final class EPGGuideViewModel {
  typealias ServiceFactory = EPGNowNextViewModel.ServiceFactory

  private let sourceID: SourceConfiguration.ID
  private let serviceFactory: ServiceFactory
  private(set) var guide: EPGGuidePresentation?
  private(set) var isLoading = false
  private(set) var isUnavailable = false

  init(sourceID: SourceConfiguration.ID, serviceFactory: @escaping ServiceFactory) {
    self.sourceID = sourceID
    self.serviceFactory = serviceFactory
  }

  func load(at now: Date = Date(), offset: Int = 0) async {
    isLoading = true
    defer { isLoading = false }
    do {
      let service = try await serviceFactory()
      guide = try await service.guide(
        sourceID: sourceID, interval: EPGGuideInterval.initial(at: now), offset: offset)
      isUnavailable = false
    } catch is CancellationError {
      return
    } catch {
      guide = nil
      isUnavailable = true
    }
  }

  func loadNextPage() async {
    guard let offset = guide?.nextOffset else { return }
    await load(offset: offset)
  }
}
