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
  private(set) var health = EPGHealth(configured: false)
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
      health = try await service.health(sourceID: sourceID)
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

  var emptyStateTitle: String {
    health.configured ? AppText.guideEmptyTitle : AppText.guideNotConfiguredTitle
  }

  var emptyStateMessage: String {
    guard health.configured else { return AppText.guideNotConfiguredMessage }
    if health.coverage(at: Date()) == .expired { return AppText.guideExpiredMessage }
    return AppText.guideNotAvailableYetMessage
  }
}
