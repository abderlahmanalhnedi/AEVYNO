import Domain
import Foundation
import Library

/// Deterministic UI-only Now/Next data. It contains no provider URL, XMLTV payload, or credential.
enum TVEPGPresentationFixture {
  static func service() -> any EPGPresenting { Schedule() }

  private actor Schedule: EPGPresenting {
    func health(sourceID _: SourceConfiguration.ID) async throws -> EPGHealth {
      EPGHealth(configured: true, lastCommittedProgrammeCount: 5)
    }

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

    func guide(
      sourceID _: SourceConfiguration.ID, interval: EPGGuideInterval, offset: Int
    ) async throws -> EPGGuidePresentation {
      let start = interval.start
      if offset == 40 {
        let channel = EPGChannelIdentity(rawValue: "synthetic-page")!
        let programmes = [
          EPGProgramme(
            channelID: channel,
            timeRange: EPGTimeRange(start: start, end: start.addingTimeInterval(3_600))!,
            title: "Page Two Brief")!,
          EPGProgramme(
            channelID: channel,
            timeRange: EPGTimeRange(
              start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(7_200))!,
            title: "Page Two Review")!,
        ]
        return EPGGuidePresentation(
          interval: interval,
          channels: [
            EPGGuideChannel(id: "live-page-1", title: "Page Two Channel", programmes: programmes)
          ],
          nextOffset: nil)
      }
      let channel = EPGChannelIdentity(rawValue: "synthetic-news")!
      let second = EPGChannelIdentity(rawValue: "synthetic-sport")!
      let playable = EPGChannelIdentity(rawValue: "synthetic-playable")!
      let channels = [
        EPGGuideChannel(
          id: "live-1", title: "World Desk",
          programmes: [
            EPGProgramme(
              channelID: channel,
              timeRange: EPGTimeRange(start: start, end: start.addingTimeInterval(3_600))!,
              title: "Morning Brief")!,
            EPGProgramme(
              channelID: channel,
              timeRange: EPGTimeRange(
                start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(7_200))!,
              title: "Market Review")!,
          ]),
        EPGGuideChannel(
          id: "live-2", title: "Arena Live",
          programmes: [
            EPGProgramme(
              channelID: second,
              timeRange: EPGTimeRange(start: start, end: start.addingTimeInterval(3_600))!,
              title: "Matchday")!,
            EPGProgramme(
              channelID: second,
              timeRange: EPGTimeRange(
                start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(7_200))!,
              title: "Highlights")!,
          ]),
        EPGGuideChannel(
          id: "m3u-1", title: "Movie Night Live",
          programmes: [
            EPGProgramme(
              channelID: playable,
              timeRange: EPGTimeRange(start: start, end: start.addingTimeInterval(3_600))!,
              title: "Playable Schedule")!
          ]),
      ]
      return EPGGuidePresentation(interval: interval, channels: channels, nextOffset: 40)
    }
  }
}
