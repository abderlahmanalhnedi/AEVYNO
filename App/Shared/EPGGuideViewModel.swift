import Domain
import Foundation
import Library
import Observation

enum EPGGuideTimeNavigationAction: Hashable {
  case previous
  case now
  case next
}

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
  private(set) var interval: EPGGuideInterval?
  private(set) var catalogOffset = 0
  private(set) var focusChannelID: String?
  private(set) var timeNavigationAction: EPGGuideTimeNavigationAction?

  init(sourceID: SourceConfiguration.ID, serviceFactory: @escaping ServiceFactory) {
    self.sourceID = sourceID
    self.serviceFactory = serviceFactory
  }

  func load(at now: Date = Date(), offset: Int = 0) async {
    await load(
      interval: EPGGuideInterval.initial(at: now), offset: offset, focusChannelID: nil,
      timeNavigationAction: nil)
  }

  func previousWindow(focusing channelID: String? = nil) async {
    guard let interval else { return }
    await load(
      interval: interval.shifted(byWindowCount: -1), offset: catalogOffset,
      focusChannelID: channelID,
      timeNavigationAction: .previous)
  }

  func nextWindow(focusing channelID: String? = nil) async {
    guard let interval else { return }
    await load(
      interval: interval.shifted(byWindowCount: 1), offset: catalogOffset,
      focusChannelID: channelID,
      timeNavigationAction: .next)
  }

  func jumpToNow(at now: Date = Date(), focusing channelID: String? = nil) async {
    let nowInterval = EPGGuideInterval.initial(at: now)
    guard interval != nowInterval else { return }
    await load(
      interval: nowInterval, offset: catalogOffset, focusChannelID: channelID,
      timeNavigationAction: .now)
  }

  private func load(
    interval: EPGGuideInterval, offset: Int, focusChannelID: String?,
    timeNavigationAction: EPGGuideTimeNavigationAction?
  ) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let service = try await serviceFactory()
      health = try await service.health(sourceID: sourceID)
      guide = try await service.guide(sourceID: sourceID, interval: interval, offset: offset)
      self.interval = interval
      catalogOffset = offset
      self.focusChannelID = focusChannelID
      self.timeNavigationAction = timeNavigationAction
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
    guard let interval else { return }
    await load(interval: interval, offset: offset, focusChannelID: nil, timeNavigationAction: nil)
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
