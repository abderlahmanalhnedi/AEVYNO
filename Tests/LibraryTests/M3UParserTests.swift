import Foundation
import IPTVCore
import Testing

@Test("Extended M3U supports BOM, CRLF, quoted attributes, whitespace, and title commas")
func extendedM3USyntaxIsParsed() async throws {
  let playlist = """
    \u{FEFF}#EXTM3U\r
    \r
      # a synthetic comment\r
    #EXTINF :123.5 tvg-id = "channel-1" tvg-name="World News" tvg-logo="https://example.invalid/logo.png" group-title = "News and Events" unknown-key="ignored",World, International\r
      https://example.invalid/live/world%2Ffeed.m3u8?quality=high&mode=live  \r
    """

  let result = try await parse(playlist)
  let entry = try #require(result.entries.first)

  #expect(result.entries.count == 1)
  #expect(result.report.parsedCount == 1)
  #expect(result.report.skippedCount == 0)
  #expect(result.report.warningCount == 0)
  #expect(entry.title == "World, International")
  #expect(entry.tvgID == "channel-1")
  #expect(entry.tvgName == "World News")
  #expect(entry.groupTitle == "News and Events")
  #expect(entry.duration == 123.5)
  #expect(entry.artworkURL?.absoluteString == "https://example.invalid/logo.png")
  #expect(
    entry.mediaURL.absoluteString
      == "https://example.invalid/live/world%2Ffeed.m3u8?quality=high&mode=live"
  )
}

@Test("Basic M3U URLs and missing optional metadata remain importable")
func basicM3UAndMissingMetadataAreParsed() async throws {
  let playlist = """
    # a plain M3U comment

    https://example.invalid/live/plain-channel.ts
    #EXTINF:-1 tvg-name="Fallback Name",   
    https://example.invalid/live/fallback.ts
    #EXTINF:0,Explicit Name
    https://example.invalid/vod/movie.m3u8
    """

  let result = try await parse(playlist)

  #expect(result.entries.map(\.title) == ["plain-channel.ts", "Fallback Name", "Explicit Name"])
  #expect(result.entries[0].duration == nil)
  #expect(result.entries[1].duration == nil)
  #expect(result.entries[2].duration == 0)
  #expect(result.entries.allSatisfy { $0.groupTitle == nil && $0.tvgID == nil })
  #expect(result.report == M3UParseReport(parsedCount: 3, skippedCount: 0, warningCounts: [:]))
}

@Test("Malformed entries are skipped with bounded warning summaries")
func malformedEntriesDoNotDestroyValidEntries() async throws {
  let playlist = """
    #EXTM3U
    #EXTINF:not-a-duration,Broken metadata
    https://example.invalid/live/discarded.ts
    #EXTINF:-1,Missing media URL
    #EXTINF:-1 tvg-logo="file:///tmp/logo.png",Valid after missing URL
    https://example.invalid/live/valid.ts
    ftp://example.invalid/live/unsupported.ts
    %not-a-url
    """

  let result = try await parse(playlist)

  #expect(result.entries.count == 1)
  #expect(result.entries[0].title == "Valid after missing URL")
  #expect(result.entries[0].artworkURL == nil)
  #expect(result.report.parsedCount == 1)
  #expect(result.report.skippedCount == 4)
  #expect(result.report.warningCounts[.malformedExtendedInfo] == 1)
  #expect(result.report.warningCounts[.missingMediaURL] == 1)
  #expect(result.report.warningCounts[.invalidArtworkURL] == 1)
  #expect(result.report.warningCounts[.unsupportedMediaURLScheme] == 1)
  #expect(result.report.warningCounts[.invalidMediaURL] == 1)
}

@Test("An EXTINF without a following media URL is reported and not emitted")
func missingFinalMediaURLIsSkipped() async throws {
  let playlist = """
    #EXTM3U
    https://example.invalid/live/valid.ts
    #EXTINF:-1,Missing URL
    # trailing comment
    """

  let result = try await parse(playlist)

  #expect(result.entries.count == 1)
  #expect(result.report.skippedCount == 1)
  #expect(result.report.warningCounts == [.missingMediaURL: 1])
}

@Test("A document without a playable HTTP entry fails with a safe report")
func documentWithoutPlayableEntriesFails() async {
  let lines = M3UDataLineSequence(
    data: Data("#EXTM3U\n#EXTINF:-1,Missing\n".utf8)
  )

  await #expect(
    throws: M3UParserError.noPlayableEntries(
      report: M3UParseReport(
        parsedCount: 0,
        skippedCount: 1,
        warningCounts: [.missingMediaURL: 1]
      )
    )
  ) {
    try await M3UParser().parse(lines: lines) { _ in }
  }
}

@Test("Invalid UTF-8 fails with only a line number")
func invalidUTF8FailsSafely() async {
  let data = Data([0x23, 0x45, 0x58, 0x54, 0x4D, 0x33, 0x55, 0x0A, 0xFF, 0x0A])

  await #expect(throws: M3UParserError.invalidUTF8(line: 2)) {
    try await M3UParser().parse(lines: M3UDataLineSequence(data: data)) { _ in }
  }
}

private func parse(_ playlist: String) async throws -> (
  entries: [M3UParsedEntry], report: M3UParseReport
) {
  var entries: [M3UParsedEntry] = []
  let report = try await M3UParser().parse(
    lines: M3UDataLineSequence(data: Data(playlist.utf8))
  ) { entry in
    entries.append(entry)
  }
  return (entries, report)
}
