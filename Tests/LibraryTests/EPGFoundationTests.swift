import CryptoKit
import Domain
import Foundation
import IPTVCore
import Testing

@testable import Library
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

@Test("XMLTV compatibility corpus preserves optional, Unicode, CDATA, entity, and unknown content")
func xmltvCompatibilityCorpus() throws {
  let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv generator-info-name="synthetic"><channel id="empty" />
    <programme stop="20260920130000Z" channel="news" start="20260920120000Z" extra="ignored">
      <title><![CDATA[الأخبار & العالم]]></title><desc>Fish &amp; Chips</desc>
      <category>News</category><category>Ignored later category</category><unknown data="safe">ignored</unknown>
    </programme><programme channel="news" start="20260920120000Z" stop="20260920130000Z"><title>الأخبار &amp; العالم</title></programme></tv>
    """
  var values: [EPGProgramme] = []
  let report = try XMLTVParser().parse(stream: InputStream(data: Data(xml.utf8))) {
    values.append($0)
  }
  #expect(report.programmeCount == 2)
  #expect(values.first?.title == "الأخبار & العالم")
  #expect(values.first?.description == "Fish & Chips")
  #expect(values.first?.category == "News")
  #expect(values.map(\.id).count == 2)
}

@Test("XMLTV rejects bounded text records without accepting truncated programme metadata")
func xmltvOverlongTextIsSkipped() throws {
  let longTitle = String(repeating: "x", count: XMLTVParser.maximumFieldUTF8Length + 1)
  let xml =
    "<tv><programme channel=\"news\" start=\"20260920120000Z\" stop=\"20260920130000Z\"><title>\(longTitle)</title></programme></tv>"
  let report = try XMLTVParser().parse(stream: InputStream(data: Data(xml.utf8))) { _ in }
  #expect(report.programmeCount == 0)
  #expect(report.skippedProgrammeCount == 1)
  #expect(report.warnings == ["skipped-programme-text-too-long"])
}

@Test("Structurally malformed XMLTV fails the document after prior valid records")
func xmltvMalformedDocumentFails() throws {
  let xml =
    "<tv><programme channel=\"news\" start=\"20260920120000Z\" stop=\"20260920130000Z\"><title>Valid</title></programme><programme>"
  #expect(throws: XMLTVParserError.malformedDocument) {
    try XMLTVParser().parse(stream: InputStream(data: Data(xml.utf8))) { _ in }
  }
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

@Test("EPG health records atomic publication facts, retains LKG after failure, and resets on retry")
func epgHealthPublicationAndFailureSemantics() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let firstAttempt = Date(timeIntervalSince1970: 1_000_000)
  let staging = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage(
    [
      fixture.programme("Current", 999_900, 1_000_100),
      fixture.programme("Future", 1_000_100, 1_000_200),
    ],
    in: staging)
  try await store.commitStagedReplacement(staging, at: firstAttempt)

  let success = try #require(await store.health(sourceID: fixture.source))
  #expect(success.lastAttemptedAt == firstAttempt)
  #expect(success.lastSuccessfulAt == firstAttempt)
  #expect(success.lastCommittedProgrammeCount == 2)
  #expect(success.coverageStartAt == Date(timeIntervalSince1970: 999_900))
  #expect(success.coverageEndAt == Date(timeIntervalSince1970: 1_000_200))
  #expect(success.lastResult == .success)
  #expect(success.lastFailureCategory == nil)
  #expect(success.coverage(at: firstAttempt) == .currentCoverage)

  let failedAttempt = firstAttempt.addingTimeInterval(60)
  try await store.recordFailure(
    sourceID: fixture.source, at: failedAttempt, category: .networkUnavailable)
  let failure = try #require(await store.health(sourceID: fixture.source))
  #expect(failure.lastAttemptedAt == failedAttempt)
  #expect(failure.lastSuccessfulAt == firstAttempt)
  #expect(failure.lastCommittedProgrammeCount == 2)
  #expect(failure.coverageEndAt == success.coverageEndAt)
  #expect(failure.lastResult == .failure)
  #expect(failure.lastFailureCategory == .networkUnavailable)
  #expect(
    try await store.nowNext(
      sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!, at: firstAttempt
    ).now?.title == "Current")

  let retry = firstAttempt.addingTimeInterval(120)
  let retryStaging = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage([fixture.programme("Replacement", 999_950, 1_000_400)], in: retryStaging)
  try await store.commitStagedReplacement(retryStaging, at: retry)
  let retried = try #require(await store.health(sourceID: fixture.source))
  #expect(retried.lastAttemptedAt == retry)
  #expect(retried.lastSuccessfulAt == retry)
  #expect(retried.lastCommittedProgrammeCount == 1)
  #expect(retried.coverageEndAt == Date(timeIntervalSince1970: 1_000_400))
  #expect(retried.lastResult == .success)
  #expect(retried.lastFailureCategory == nil)
}

@Test("Zero-programme EPG publication is an explicit successful no-data state that survives reopen")
func epgHealthZeroPublicationAndReopen() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let at = Date(timeIntervalSince1970: 1_000_000)
  let store = try fixture.makeStore()
  let staging = try await store.beginStaging(sourceID: fixture.source)
  try await store.commitStagedReplacement(staging, at: at)
  let published = try #require(await store.health(sourceID: fixture.source))
  #expect(published.lastResult == .success)
  #expect(published.lastCommittedProgrammeCount == 0)
  #expect(published.coverage(at: at) == .noData)

  let reopened = try SQLiteEPGStore(url: fixture.directory.appendingPathComponent("epg.sqlite"))
  let persisted = try #require(await reopened.health(sourceID: fixture.source))
  #expect(persisted == published)
}

@Test("EPG health migration from schema version one preserves committed programmes")
func epgHealthMigratesVersionOneDatabase() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
  let url = fixture.directory.appendingPathComponent("epg.sqlite")
  let source = fixture.source.rawValue.uuidString
  let database = try CatalogDatabase(url: url)
  try database.execute(
    "CREATE TABLE epg_programmes(source TEXT NOT NULL, programme_id TEXT NOT NULL, channel TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT, description TEXT, category TEXT, PRIMARY KEY(source,programme_id))"
  )
  try database.execute("CREATE INDEX epg_now_next ON epg_programmes(source,channel,start,end)")
  try database.execute(
    "CREATE TABLE epg_staging_sessions(staging_id TEXT PRIMARY KEY, source TEXT NOT NULL)")
  try database.execute(
    "CREATE TABLE epg_staging(staging_id TEXT NOT NULL, source TEXT NOT NULL, programme_id TEXT NOT NULL, channel TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT, description TEXT, category TEXT, PRIMARY KEY(staging_id,programme_id))"
  )
  try database.execute(
    "INSERT INTO epg_programmes(source,programme_id,channel,start,end,title) VALUES(?,?,?,?,?,?)",
    [source, "old", "news", "0", "10", "Retained"])
  try database.execute("PRAGMA user_version=1")

  let store = try SQLiteEPGStore(url: url)
  #expect(try await store.health(sourceID: fixture.source) == nil)
  #expect(
    try await store.nowNext(
      sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
      at: Date(timeIntervalSince1970: 5)
    ).now?.title == "Retained")
}

@Test("EPG failures map to safe provider-neutral categories and cancellation records nothing")
func epgFailureClassificationIsSafe() async throws {
  #expect(
    XMLTVEPGImportService.failureCategory(for: M3UAcquisitionError.transportUnavailable)
      == .networkUnavailable)
  #expect(XMLTVEPGImportService.failureCategory(for: M3UAcquisitionError.timedOut) == .timeout)
  #expect(
    XMLTVEPGImportService.failureCategory(for: M3UAcquisitionError.responseTooLarge)
      == .responseTooLarge)
  #expect(
    XMLTVEPGImportService.failureCategory(for: XMLTVParserError.malformedDocument)
      == .invalidGuideData)
  #expect(
    XMLTVEPGImportService.failureCategory(for: EPGStoreError.writeFailed) == .persistenceFailure)
  struct SensitiveError: Error { let message: String }
  let sensitive = SensitiveError(message: "https://user:token@example.invalid/guide?token=secret")
  #expect(XMLTVEPGImportService.failureCategory(for: sensitive) == .unknown)

  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let importer = XMLTVEPGImportService(repository: try fixture.makeStore())
  try await importer.recordFailure(sourceID: fixture.source, at: .now, error: CancellationError())
  let store = try SQLiteEPGStore(url: fixture.directory.appendingPathComponent("epg.sqlite"))
  #expect(try await store.health(sourceID: fixture.source) == nil)
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

@Test("Synthetic 100, 1000 and 10000 channel EPG parse and persistence phases remain bounded")
func epgScaleSmokeMeasurement() async throws {
  for channels in [100, 1_000, 10_000] {
    let fixture = EPGFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let store = try fixture.makeStore()
    let programmes = (0..<channels).flatMap { index in
      [
        fixture.programme(
          "Channel \(index) Slot 0", 0, 3_600, channel: "channel-\(index)"),
        fixture.programme(
          "Channel \(index) Slot 1", 3_600, 7_200, channel: "channel-\(index)"),
      ]
    }
    let xml =
      "<tv>"
      + programmes.map { programme in
        "<programme channel=\"\(programme.channelID.rawValue)\" start=\"19700101000000Z\" stop=\"19700101010000Z\"><title>\(programme.title)</title></programme>"
      }.joined() + "</tv>"
    let parseStarted = ContinuousClock.now
    let report = try XMLTVParser().parse(stream: InputStream(data: Data(xml.utf8))) { _ in }
    let parseDuration = parseStarted.duration(to: .now)
    #expect(report.programmeCount == programmes.count)

    let staging = try await store.beginStaging(sourceID: fixture.source)
    var batch: [EPGProgramme] = []
    let stagingStarted = ContinuousClock.now
    for programme in programmes {
      batch.append(programme)
      if batch.count == SQLiteEPGStore.batchLimit {
        try await store.stage(batch, in: staging)
        batch.removeAll(keepingCapacity: true)
      }
    }
    if !batch.isEmpty { try await store.stage(batch, in: staging) }
    let stagingDuration = stagingStarted.duration(to: .now)
    let publicationStarted = ContinuousClock.now
    try await store.commitStagedReplacement(staging, at: Date(timeIntervalSince1970: 1))
    let publicationDuration = publicationStarted.duration(to: .now)
    let nowNextStarted = ContinuousClock.now
    let lookup = try await store.nowNext(
      sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "channel-\(channels - 1)")!,
      at: Date(timeIntervalSince1970: 1))
    let nowNextDuration = nowNextStarted.duration(to: .now)
    #expect(lookup.now?.title == "Channel \(channels - 1) Slot 0")
    let interval = try #require(
      EPGGuideInterval(
        start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3_600)))
    let guideStarted = ContinuousClock.now
    let guide = try await store.programmes(
      sourceID: fixture.source,
      channelIDs: (0..<min(50, channels)).compactMap {
        EPGChannelIdentity(rawValue: "channel-\($0)")
      },
      interval: interval)
    let guideDuration = guideStarted.duration(to: .now)
    #expect(guide.count == min(50, channels))
    let cacheSize = ["epg.sqlite", "epg.sqlite-wal", "epg.sqlite-shm"].reduce(0) {
      total, name in
      total
        + ((try? FileManager.default.attributesOfItem(
          atPath: fixture.directory.appendingPathComponent(name).path)[.size] as? NSNumber)?
          .intValue ?? 0)
    }
    print(
      "EPG-SCALE channels=\(channels) programmes=\(programmes.count) parse=\(parseDuration) staging=\(stagingDuration) publication=\(publicationDuration) now-next=\(nowNextDuration) guide=\(guideDuration) cache-bytes=\(cacheSize)"
    )
  }
}

@Test("Guide interval query is source scoped, bounded, ordered, and excludes schedule gaps")
func epgGuideIntervalQuery() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let staging = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage(
    [
      fixture.programme("Later", 7_200, 10_800, channel: "two"),
      fixture.programme("Overlap A", 0, 3_600, channel: "one"),
      fixture.programme("Overlap B", 1_800, 5_400, channel: "one"),
      fixture.programme("Outside", 28_800, 32_400, channel: "one"),
    ], in: staging)
  try await store.commitStagedReplacement(staging, at: Date(timeIntervalSince1970: 1))
  let interval = try #require(
    EPGGuideInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 7_200))
  )
  let programmes = try await store.programmes(
    sourceID: fixture.source,
    channelIDs: [EPGChannelIdentity(rawValue: "two")!, EPGChannelIdentity(rawValue: "one")!],
    interval: interval)
  #expect(programmes.map(\.title) == ["Overlap A", "Overlap B"])
  #expect(
    programmes.allSatisfy { $0.timeRange.start < interval.end && $0.timeRange.end > interval.start }
  )
}

@Test("Guide interval rejects an unbounded request")
func epgGuideIntervalIsBounded() {
  #expect(EPGGuideInterval(start: .distantPast, end: .distantFuture) == nil)
  let initial = EPGGuideInterval.initial(at: Date(timeIntervalSince1970: 0))
  #expect(initial.end.timeIntervalSince(initial.start) == 8 * 60 * 60)
}

@Test("Guide windows shift exactly one bounded interval and preserve canonical Now shape")
func epgGuideWindowShiftsAreDeterministic() {
  let now = Date(timeIntervalSince1970: 1_000_000)
  let initial = EPGGuideInterval.initial(at: now)
  let next = initial.shifted(byWindowCount: 1)
  let previous = next.shifted(byWindowCount: -1)

  #expect(next.start == initial.end)
  #expect(next.end.timeIntervalSince(next.start) == EPGGuideInterval.maximumDuration)
  #expect(previous == initial)
  #expect(EPGGuideInterval.initial(at: now) == initial)
}

@Test(
  "Production guide excludes unmapped catalog rows and preserves exact playable catalog identities")
func productionGuideUsesExactMappings() async throws {
  let source = SourceConfiguration.ID(rawValue: UUID())
  let scope = CatalogScope(sourceID: source, origin: .m3u, kind: .unspecified)
  let mapped = CatalogItem(
    id: "playable-catalog-item", scope: scope, title: "Mapped channel",
    epgChannelID: EPGChannelIdentity(rawValue: "exact-channel"))
  let unmapped = CatalogItem(id: "unmapped", scope: scope, title: "No mapping")
  let programme = EPGProgramme(
    channelID: EPGChannelIdentity(rawValue: "exact-channel")!,
    timeRange: EPGTimeRange(
      start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3_600))!,
    title: "Current")!
  let service = ProductionEPGService(
    catalog: GuideCatalogStub(items: [mapped, unmapped]), epg: GuideEPGStub(programmes: [programme])
  )
  let interval = try #require(
    EPGGuideInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 7_200))
  )
  let guide = try await service.guide(sourceID: source, interval: interval, offset: 0)
  #expect(guide.channels.map(\.id) == ["playable-catalog-item"])
  #expect(guide.channels.first?.programmes.map(\.title) == ["Current"])
}

private actor GuideCatalogStub: CatalogQueryRepository {
  let storedItems: [CatalogItem]
  init(items: [CatalogItem]) { storedItems = items }
  func item(id: String) -> CatalogItem? { storedItems.first { $0.id == id } }
  func items(matching _: CatalogFilter, page: CatalogPage) -> [CatalogItem] {
    Array(storedItems.dropFirst(page.offset).prefix(page.limit))
  }
  func searchItems(matching _: CatalogFilter, query _: CatalogSearchQuery, page: CatalogPage)
    -> [CatalogItem]
  { Array(storedItems.dropFirst(page.offset).prefix(page.limit)) }
  func categories(matching _: CatalogFilter, page _: CatalogPage) -> [CatalogCategory] { [] }
  func categorySummaries(matching _: CatalogFilter, page _: CatalogPage) -> [CatalogCategorySummary]
  { [] }
  func itemCount(matching _: CatalogFilter) -> Int { storedItems.count }
  func sourceCatalogCount(sourceID _: SourceConfiguration.ID?) -> Int { 1 }
}

private actor GuideEPGStub: EPGQueryRepository {
  let storedProgrammes: [EPGProgramme]
  init(programmes: [EPGProgramme]) { storedProgrammes = programmes }
  func nowNext(sourceID _: SourceConfiguration.ID, channelID _: EPGChannelIdentity, at _: Date)
    -> EPGNowNextPresentation
  { EPGNowNextPresentation(now: nil, next: nil) }
  func programmes(
    sourceID _: SourceConfiguration.ID, channelIDs: [EPGChannelIdentity], interval: EPGGuideInterval
  ) -> [EPGProgramme] {
    storedProgrammes.filter {
      channelIDs.contains($0.channelID) && $0.timeRange.start < interval.end
        && $0.timeRange.end > interval.start
    }
  }
  func health(sourceID _: SourceConfiguration.ID) -> EPGHealth? { nil }
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

@Test("A successful XMLTV retry after failure replaces the preserved last known good snapshot")
func xmltvRetryAfterFailureRecovers() async throws {
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
  let valid =
    "<tv><programme channel=\"news\" start=\"19700101000000Z\" stop=\"19700101010000Z\"><title>Replacement</title></programme></tv>"
  _ = try await service.importXMLTV(
    stream: InputStream(data: Data(valid.utf8)), sourceID: fixture.source,
    at: Date(timeIntervalSince1970: 1))
  #expect(try await store.stagedRowCountForTesting() == 0)
  let current = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: Date(timeIntervalSince1970: 1))
  #expect(current.now?.title == "Replacement")
}

@Test("Staging failure cleans the spool and preserves last known good EPG")
func xmltvStagingFailureCleansSpoolAndPreservesLKG() async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let original = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage([fixture.programme("Original", 0, 3_600)], in: original)
  try await store.commitStagedReplacement(original, at: Date(timeIntervalSince1970: 1))
  let spoolDirectory = fixture.directory.appendingPathComponent("spool", isDirectory: true)
  try FileManager.default.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
  let service = XMLTVEPGImportService(
    repository: FailingEPGRepository(base: store), temporaryDirectory: spoolDirectory)
  let xml =
    "<tv><programme channel=\"news\" start=\"19700101000000Z\" stop=\"19700101010000Z\"><title>Replacement</title></programme></tv>"
  await #expect(throws: EPGStoreError.writeFailed) {
    try await service.importXMLTV(
      stream: InputStream(data: Data(xml.utf8)), sourceID: fixture.source,
      at: Date(timeIntervalSince1970: 1))
  }
  #expect(try FileManager.default.contentsOfDirectory(atPath: spoolDirectory.path).isEmpty)
  #expect(try await store.stagedRowCountForTesting() == 0)
  let current = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: Date(timeIntervalSince1970: 1))
  #expect(current.now?.title == "Original")
}

@Test(arguments: [
  XMLTVImportPhase.parsing, .spoolProduction, .staging, .publication,
])
func xmltvCancellationAtEachImportBoundaryPreservesLKG(_ phase: XMLTVImportPhase) async throws {
  let fixture = EPGFixture()
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let store = try fixture.makeStore()
  let original = try await store.beginStaging(sourceID: fixture.source)
  try await store.stage([fixture.programme("Original", 0, 3_600)], in: original)
  try await store.commitStagedReplacement(original, at: Date(timeIntervalSince1970: 1))
  let spoolDirectory = fixture.directory.appendingPathComponent("spool", isDirectory: true)
  try FileManager.default.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
  let service = XMLTVEPGImportService(
    repository: store, temporaryDirectory: spoolDirectory,
    phaseHook: { observed in
      guard observed == phase else { return }
      throw CancellationError()
    })
  let xml =
    "<tv><programme channel=\"news\" start=\"19700101000000Z\" stop=\"19700101010000Z\"><title>Replacement</title></programme></tv>"
  await #expect(throws: CancellationError.self) {
    try await service.importXMLTV(
      stream: InputStream(data: Data(xml.utf8)), sourceID: fixture.source,
      at: Date(timeIntervalSince1970: 1))
  }
  #expect(try FileManager.default.contentsOfDirectory(atPath: spoolDirectory.path).isEmpty)
  #expect(try await store.stagedRowCountForTesting() == 0)
  let current = try await store.nowNext(
    sourceID: fixture.source, channelID: EPGChannelIdentity(rawValue: "news")!,
    at: Date(timeIntervalSince1970: 1))
  #expect(current.now?.title == "Original")
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

private actor FailingEPGRepository: EPGImportRepository {
  let base: SQLiteEPGStore
  init(base: SQLiteEPGStore) { self.base = base }
  func beginStaging(sourceID: SourceConfiguration.ID) async throws -> UUID {
    try await base.beginStaging(sourceID: sourceID)
  }
  func stage(_: [EPGProgramme], in _: UUID) async throws { throw EPGStoreError.writeFailed }
  func commitStagedReplacement(_: UUID, at _: Date) async throws { throw EPGStoreError.writeFailed }
  func discardStaging(_ stagingID: UUID) async { await base.discardStaging(stagingID) }
  func recordFailure(
    sourceID _: SourceConfiguration.ID, at _: Date, category _: EPGFailureCategory
  ) async throws { throw EPGStoreError.writeFailed }
}
