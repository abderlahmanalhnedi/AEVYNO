import CryptoKit
import Domain
import Foundation
import IPTVCore
import Library
import Testing

@testable import Persistence

@Test("XMLTV SAX parser normalizes timezone-aware programmes without retaining a document DOM")
func xmltvParserNormalizesProgramme() throws {
  let xml = """
    <tv><channel id="news.us"><display-name>News</display-name></channel>
    <programme channel="news.us" start="20260920120000+0200" stop="20260920130000+0200">
    <title>News &amp; Weather</title><sub-title>Heute</sub-title><desc>العربية</desc><category>News</category>
    </programme></tv>
    """
  var programmes: [EPGProgramme] = []
  let report = try XMLTVParser().parse(stream: InputStream(data: Data(xml.utf8))) {
    programmes.append($0)
  }
  #expect(report.programmeCount == 1)
  #expect(programmes.first?.channelID.rawValue == "news.us")
  #expect(programmes.first?.title == "News & Weather")
  #expect(programmes.first?.description == "العربية")
  #expect(programmes.first?.timeRange.start == XMLTVTimestamp.parse("20260920100000Z"))
}

@Test("XMLTV timestamps require an explicit offset and preserve absolute instants")
func xmltvTimestampRules() {
  #expect(XMLTVTimestamp.parse("202609201200+0200") == XMLTVTimestamp.parse("202609201000Z"))
  #expect(XMLTVTimestamp.parse("202609201200-0200") == XMLTVTimestamp.parse("202609201400Z"))
  #expect(XMLTVTimestamp.parse("202609201200") == nil)
  #expect(XMLTVTimestamp.parse("bad") == nil)
}

@Test("Malformed XMLTV programmes are skipped while valid neighbours remain")
func xmltvMalformedProgrammeIsSkippable() throws {
  let xml = """
    <tv><programme channel="x" start="bad" stop="20260920130000Z"><title>Bad</title></programme>
    <programme channel="x" start="20260920120000Z" stop="20260920130000Z"><title>Good</title></programme></tv>
    """
  var values: [EPGProgramme] = []
  let report = try XMLTVParser().parse(stream: InputStream(data: Data(xml.utf8))) {
    values.append($0)
  }
  #expect(report.programmeCount == 1)
  #expect(report.skippedProgrammeCount == 1)
  #expect(values.map(\.title) == ["Good"])
}

struct EPGFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let source = SourceConfiguration.ID(rawValue: UUID())

  func makeStore() throws -> SQLiteEPGStore {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try SQLiteEPGStore(url: directory.appendingPathComponent("epg.sqlite"))
  }

  func programme(
    _ title: String, _ start: TimeInterval, _ end: TimeInterval, channel: String = "news"
  ) -> EPGProgramme {
    EPGProgramme(
      channelID: EPGChannelIdentity(rawValue: channel)!,
      timeRange: EPGTimeRange(
        start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))!,
      title: title)!
  }
}

@Test("EPG staging is invisible and Now Next has deterministic interval and overlap semantics")
func epgAtomicNowNext() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let channel = EPGChannelIdentity(rawValue: "news")!
  let staging = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage(
    [
      fixture.programme("Earlier overlap", 0, 20), fixture.programme("Now", 10, 30),
      fixture.programme("Next", 30, 60),
    ], in: staging)
  #expect(
    try await store.nowNext(
      sourceID: fixture.source, channelID: channel, at: Date(timeIntervalSince1970: 15)
    ).now == nil)
  try await store.commitStagedReplacement(staging, at: Date(timeIntervalSince1970: 15))
  let result = try await store.nowNext(
    sourceID: fixture.source, channelID: channel, at: Date(timeIntervalSince1970: 15))
  #expect(result.now?.title == "Now")
  #expect(result.next?.title == "Next")
  let boundary = try await store.nowNext(
    sourceID: fixture.source, channelID: channel, at: Date(timeIntervalSince1970: 30))
  #expect(boundary.now?.title == "Next")
}

@Test("M3U TVG ID survives encrypted catalog persistence and absent TVG ID remains unmapped")
func m3uMappingIsConservative() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let source = SourceConfiguration.ID(rawValue: UUID())
  let store = try await SQLiteCatalogStore(
    url: directory.appendingPathComponent("catalog.sqlite"),
    encryptionKey: SymmetricKey(size: .bits256))
  let playlist =
    "#EXTM3U\n#EXTINF:-1 tvg-id=\"news\",Mapped\nhttps://example.invalid/a\n#EXTINF:-1,Unmapped\nhttps://example.invalid/b\n"
  _ = try await M3UImportService().importPlaylist(
    lines: M3UDataLineSequence(data: Data(playlist.utf8)), sourceID: source,
    sink: PersistentCatalogImportSink(repository: store))
  let items = try await store.items(matching: CatalogFilter(), page: CatalogPage(limit: 2))
  #expect(items.first(where: { $0.title == "Mapped" })?.epgChannelID?.rawValue == "news")
  #expect(items.first(where: { $0.title == "Unmapped" })?.epgChannelID == nil)
  #expect(items.allSatisfy { $0.scope.kind == .unspecified })
}

@Test("Synthetic 100, 1000 and 10000 channel EPG imports retain bounded Now Next lookups")
func epgScaleSmokeMeasurement() async throws {
  for channels in [100, 1_000, 10_000] {
    let fixture = EPGFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let store = try fixture.makeStore()
    let started = ContinuousClock.now
    let staging = try await store.beginStaging(sourceID: fixture.source)
    var batch: [EPGProgramme] = []
    for index in 0..<channels {
      for slot in 0..<2 {
        batch.append(
          fixture.programme(
            "Channel \(index) Slot \(slot)", TimeInterval(slot * 3_600),
            TimeInterval((slot + 1) * 3_600), channel: "channel-\(index)"))
        if batch.count == SQLiteEPGStore.batchLimit {
          try await store.stage(batch, in: staging)
          batch.removeAll(keepingCapacity: true)
        }
      }
    }
    if !batch.isEmpty { try await store.stage(batch, in: staging) }
    try await store.commitStagedReplacement(staging, at: Date(timeIntervalSince1970: 1))
    let lookup = try await store.nowNext(
      sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "channel-\(channels - 1)")!,
      at: Date(timeIntervalSince1970: 1))
    #expect(lookup.now?.title == "Channel \(channels - 1) Slot 0")
    print(
      "EPG scale \(channels) channels / \(channels * 2) programmes: \(started.duration(to: .now))")
  }
}

@Test("XMLTV import stages bounded normalized rows and atomically replaces the source snapshot")
func xmltvImportPublishesAndCleansStaging() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let service = XMLTVEPGImportService(repository: store)
  let xml = """
    <tv><programme channel="news" start="19700101000000Z" stop="19700101010000Z"><title>Now</title></programme>
    <programme channel="news" start="19700101010000Z" stop="19700101020000Z"><title>Next</title></programme></tv>
    """
  let report = try await service.importXMLTV(
    stream: InputStream(data: Data(xml.utf8)), sourceID: fixture.source,
    at: Date(timeIntervalSince1970: 1))
  #expect(report.parsedProgrammeCount == 2)
  #expect(try await store.stagedRowCountForTesting() == 0)
  let value = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: Date(timeIntervalSince1970: 1))
  #expect(value.now?.title == "Now")
  #expect(value.next?.title == "Next")
}

@Test("Failed XMLTV import discards staging and preserves committed EPG")
func failedXMLTVImportPreservesCommittedEPG() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let original = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage([fixture.programme("Original", 0, 3_600)], in: original)
  try await store.commitStagedReplacement(original, at: Date(timeIntervalSince1970: 1))
  let service = XMLTVEPGImportService(repository: store)
  await #expect(throws: XMLTVParserError.self) {
    try await service.importXMLTV(
      stream: InputStream(data: Data("<tv><programme".utf8)), sourceID: fixture.source,
      at: Date(timeIntervalSince1970: 1))
  }
  #expect(try await store.stagedRowCountForTesting() == 0)
  let value = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: Date(timeIntervalSince1970: 1))
  #expect(value.now?.title == "Original")
}

@Test("Discard and reopen remove abandoned EPG staging rows without touching committed programmes")
func epgDiscardAndReopenCleanStaging() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let url = fixture.directory.appendingPathComponent("epg.sqlite")
  var store: SQLiteEPGStore? = try fixture.makeStore()
  let committed = try await store!.beginStaging(sourceID: fixture.source)
  try await store!.stage([fixture.programme("Committed", 0, 3_600)], in: committed)
  try await store!.commitStagedReplacement(committed, at: Date(timeIntervalSince1970: 1))
  let abandoned = try await store!.beginStaging(sourceID: fixture.source)
  try await store!.stage([fixture.programme("Abandoned", 3_600, 7_200)], in: abandoned)
  await store!.discardStaging(abandoned)
  #expect(try await store!.stagedRowCountForTesting() == 0)
  let interrupted = try await store!.beginStaging(sourceID: fixture.source)
  try await store!.stage([fixture.programme("Interrupted", 7_200, 10_800)], in: interrupted)
  store = nil
  let reopened = try SQLiteEPGStore(url: url)
  #expect(try await reopened.stagedRowCountForTesting() == 0)
  let value = try await reopened.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: Date(timeIntervalSince1970: 1))
  #expect(value.now?.title == "Committed")
}

@Test("Retention uses inclusive 24-hour past and 14-day future publication boundaries")
func epgRetentionBoundaries() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let now = Date(timeIntervalSince1970: 2_000_000)
  let staging = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage(
    [
      fixture.programme(
        "Past boundary", now.timeIntervalSince1970 - 86_401, now.timeIntervalSince1970 - 86_400),
      fixture.programme(
        "Future boundary", now.timeIntervalSince1970 + 14 * 86_400,
        now.timeIntervalSince1970 + 14 * 86_400 + 3_600),
      fixture.programme(
        "Too future", now.timeIntervalSince1970 + 14 * 86_400 + 1,
        now.timeIntervalSince1970 + 14 * 86_400 + 3_600),
    ], in: staging)
  try await store.commitStagedReplacement(staging, at: now)
  let past = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: now.addingTimeInterval(-86_400.5))
  #expect(past.now?.title == "Past boundary")
  let future = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: now.addingTimeInterval(14 * 86_400))
  #expect(future.now?.title == "Future boundary")
}

@Test("Now Next returns gaps, future-only, current-only, and stable overlap ties deterministically")
func epgNowNextEdgeSemantics() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let staging = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage(
    [
      fixture.programme("Tie B", 0, 20), fixture.programme("Tie A", 0, 20),
      fixture.programme("Later", 10, 30), fixture.programme("Future", 40, 50),
    ], in: staging)
  try await store.commitStagedReplacement(staging, at: Date(timeIntervalSince1970: 15))
  let channel = EPGChannelIdentity(rawValue: "news")!
  #expect(
    (try await store.nowNext(
      sourceID: fixture.source, channelID: channel, at: Date(timeIntervalSince1970: 15))).now?.title
      == "Later")
  let gap = try await store.nowNext(
    sourceID: fixture.source, channelID: channel, at: Date(timeIntervalSince1970: 35))
  #expect(gap.now == nil)
  #expect(gap.next?.title == "Future")
  let future = try await store.nowNext(
    sourceID: fixture.source, channelID: channel, at: Date(timeIntervalSince1970: 39))
  #expect(future.next?.title == "Future")
}
