import Domain
import Foundation
import Library

/// Deterministic UI-only Now/Next data. It contains no provider URL, XMLTV payload, or credential.
enum TVEPGPresentationFixture {
  static func service() -> any EPGPresenting { Schedule() }

  private actor Schedule: EPGPresenting {
    func nowNext(for catalogItemID: String, at instant: Date) async throws
      -> EPGNowNextPresentation
    {
      guard catalogItemID == "live-1",
        let nowRange = EPGTimeRange(
          start: instant.addingTimeInterval(-60), end: instant.addingTimeInterval(60)),
        let nextRange = EPGTimeRange(
          start: instant.addingTimeInterval(60), end: instant.addingTimeInterval(120)),
        let channel = EPGChannelIdentity(rawValue: "synthetic-news"),
        let now = EPGProgramme(channelID: channel, timeRange: nowRange, title: "Morning Brief"),
        let next = EPGProgramme(channelID: channel, timeRange: nextRange, title: "Market Review")
      else { return EPGNowNextPresentation(now: nil, next: nil) }
      return EPGNowNextPresentation(now: now, next: next)
    }
  }
}
