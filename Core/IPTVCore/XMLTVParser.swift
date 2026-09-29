import Domain
import Foundation

public enum XMLTVParserError: Error, Equatable, Sendable {
  case malformedDocument
  case invalidInput
  case cancelled
}

public struct XMLTVParseReport: Equatable, Sendable {
  public let programmeCount: Int
  public let skippedProgrammeCount: Int
  public let warnings: [String]

  public init(programmeCount: Int, skippedProgrammeCount: Int, warnings: [String]) {
    self.programmeCount = programmeCount
    self.skippedProgrammeCount = skippedProgrammeCount
    self.warnings = warnings
  }
}

/// SAX-style XMLTV parser: it retains only one programme's bounded text fields at a time.
public final class XMLTVParser: NSObject {
  public static let maximumFieldUTF8Length = 16_384
  public static let maximumWarnings = 32

  private var handler: ((EPGProgramme) throws -> Void)?
  private var failure: Error?
  private var current: Draft?
  private var textElement: String?
  private var text = ""
  private var textExceededLimit = false
  private var programmeCount = 0
  private var skippedCount = 0
  private var warnings: [String] = []

  public override init() {}

  @discardableResult
  public func parse(
    stream: InputStream, onProgramme: @escaping (EPGProgramme) throws -> Void
  ) throws -> XMLTVParseReport {
    reset(onProgramme)
    guard !Task.isCancelled else { throw XMLTVParserError.cancelled }
    let parser = Foundation.XMLParser(stream: stream)
    parser.delegate = self
    guard parser.parse() else {
      if Task.isCancelled { throw XMLTVParserError.cancelled }
      if let failure { throw failure }
      throw XMLTVParserError.malformedDocument
    }
    if Task.isCancelled { throw XMLTVParserError.cancelled }
    if let failure { throw failure }
    return XMLTVParseReport(
      programmeCount: programmeCount, skippedProgrammeCount: skippedCount, warnings: warnings)
  }

  private func reset(_ handler: @escaping (EPGProgramme) throws -> Void) {
    self.handler = handler
    failure = nil
    current = nil
    textElement = nil
    text = ""
    textExceededLimit = false
    programmeCount = 0
    skippedCount = 0
    warnings = []
  }

  private func warning(_ value: String) {
    if warnings.count < Self.maximumWarnings { warnings.append(value) }
  }

  private func finishProgramme() {
    defer { current = nil }
    guard let current else { return }
    guard !current.textExceededLimit else {
      skippedCount += 1
      warning("skipped-programme-text-too-long")
      return
    }
    guard let channel = EPGChannelIdentity(rawValue: current.channel),
      let start = XMLTVTimestamp.parse(current.start), let end = XMLTVTimestamp.parse(current.stop),
      let range = EPGTimeRange(start: start, end: end),
      let programme = EPGProgramme(
        channelID: channel, timeRange: range, title: current.title, subtitle: current.subtitle,
        description: current.description, category: current.category)
    else {
      skippedCount += 1
      warning("skipped-invalid-programme")
      return
    }
    do {
      try handler?(programme)
      programmeCount += 1
    } catch {
      failure = error
    }
  }

  private struct Draft {
    let channel: String
    let start: String
    let stop: String
    var title = ""
    var subtitle: String?
    var description: String?
    var category: String?
    var textExceededLimit = false
  }
}

extension XMLTVParser: XMLParserDelegate {
  public func parser(
    _ parser: Foundation.XMLParser, didStartElement elementName: String,
    namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]
  ) {
    guard !Task.isCancelled else {
      parser.abortParsing()
      return
    }
    textElement = nil
    text = ""
    textExceededLimit = false
    if elementName == "programme" {
      guard let channel = attributes["channel"], let start = attributes["start"],
        let stop = attributes["stop"]
      else {
        skippedCount += 1
        warning("skipped-programme-missing-required-attribute")
        return
      }
      current = Draft(channel: channel, start: start, stop: stop)
    } else if current != nil, Self.maximumLength(for: elementName) != nil {
      textElement = elementName
    }
  }

  public func parser(_ parser: Foundation.XMLParser, foundCharacters string: String) {
    guard let element = textElement, let maximum = Self.maximumLength(for: element), current != nil
    else { return }
    let remaining = maximum - text.utf8.count
    guard remaining >= string.utf8.count else {
      textExceededLimit = true
      return
    }
    text += string
  }

  public func parser(
    _ parser: Foundation.XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    guard var draft = current else { return }
    if elementName == "programme" {
      finishProgramme()
      return
    }
    guard textElement == elementName else { return }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if textExceededLimit { draft.textExceededLimit = true }
    switch elementName {
    case "title": draft.title = value
    case "sub-title": draft.subtitle = value
    case "desc": draft.description = value
    // XMLTV permits multiple categories. The domain has one category field, so retain the first
    // non-empty value rather than making outcome depend on element order after that point.
    case "category" where draft.category == nil && !value.isEmpty: draft.category = value
    default: break
    }
    current = draft
    textElement = nil
    text = ""
    textExceededLimit = false
  }

  public func parser(_ parser: Foundation.XMLParser, parseErrorOccurred parseError: Error) {
    if failure == nil { failure = XMLTVParserError.malformedDocument }
  }

  private static func maximumLength(for element: String) -> Int? {
    switch element {
    case "title": 4_096
    case "sub-title", "desc", "category": maximumFieldUTF8Length
    default: nil
    }
  }
}

public enum XMLTVTimestamp {
  /// Parses YYYYMMDDhhmm[ss] plus Z or ±HHMM. Timezone-free input is rejected deliberately.
  public static func parse(_ value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^(\d{12}(?:\d{2})?)(Z|[+-]\d{4})$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
      let dateRange = Range(match.range(at: 1), in: trimmed),
      let zoneRange = Range(match.range(at: 2), in: trimmed)
    else { return nil }
    let digits = String(trimmed[dateRange])
    let zone = String(trimmed[zoneRange])
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = digits.count == 14 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
    if zone == "Z" {
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
    } else {
      let sign = zone.first == "+" ? 1 : -1
      guard let hours = Int(zone.dropFirst().prefix(2)), let minutes = Int(zone.suffix(2)),
        hours <= 23, minutes <= 59
      else { return nil }
      formatter.timeZone = TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
    return formatter.date(from: digits)
  }
}
