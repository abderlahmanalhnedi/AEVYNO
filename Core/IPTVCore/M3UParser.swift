import Foundation

public struct M3UParsedEntry: Hashable, Sendable {
  public let title: String
  public let mediaURL: URL
  public let groupTitle: String?
  public let artworkURL: URL?
  public let tvgID: String?
  public let tvgName: String?
  public let duration: TimeInterval?

  public init(
    title: String,
    mediaURL: URL,
    groupTitle: String? = nil,
    artworkURL: URL? = nil,
    tvgID: String? = nil,
    tvgName: String? = nil,
    duration: TimeInterval? = nil
  ) {
    self.title = title
    self.mediaURL = mediaURL
    self.groupTitle = groupTitle
    self.artworkURL = artworkURL
    self.tvgID = tvgID
    self.tvgName = tvgName
    self.duration = duration
  }
}

public enum M3UParserWarning: String, CaseIterable, Hashable, Sendable {
  case invalidArtworkURL
  case invalidMediaURL
  case malformedExtendedInfo
  case missingMediaURL
  case unsupportedMediaURLScheme
}

public struct M3UParseReport: Equatable, Sendable {
  public let parsedCount: Int
  public let skippedCount: Int
  public let warningCounts: [M3UParserWarning: Int]

  public init(
    parsedCount: Int,
    skippedCount: Int,
    warningCounts: [M3UParserWarning: Int]
  ) {
    self.parsedCount = parsedCount
    self.skippedCount = skippedCount
    self.warningCounts = warningCounts
  }

  public var warningCount: Int {
    warningCounts.values.reduce(0, +)
  }
}

public enum M3UParserError: Error, Equatable, Sendable {
  case invalidUTF8(line: Int)
  case noPlayableEntries(report: M3UParseReport)
}

public struct M3UParser: Sendable {
  public init() {}

  public func parse<Lines: AsyncSequence>(
    lines: Lines,
    onEntry: (M3UParsedEntry) async throws -> Void
  ) async throws -> M3UParseReport where Lines.Element == String {
    var iterator = lines.makeAsyncIterator()
    var pendingEntry: PendingEntry?
    var parsedCount = 0
    var skippedCount = 0
    var warningCounts: [M3UParserWarning: Int] = [:]
    var lineNumber = 0

    func record(_ warning: M3UParserWarning) {
      warningCounts[warning, default: 0] += 1
    }

    func skipPendingEntry(missingURL: Bool) {
      guard pendingEntry != nil else {
        return
      }
      skippedCount += 1
      if missingURL, case .metadata = pendingEntry {
        record(.missingMediaURL)
      }
      pendingEntry = nil
    }

    while let rawLine = try await iterator.next() {
      try Task.checkCancellation()
      lineNumber += 1

      var line = rawLine
      if lineNumber == 1, line.first == "\u{FEFF}" {
        line.removeFirst()
      }
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if trimmedLine.isEmpty {
        continue
      }

      if trimmedLine.uppercased().hasPrefix("#EXTM3U") {
        skipPendingEntry(missingURL: true)
        continue
      }

      if trimmedLine.uppercased().hasPrefix("#EXTINF") {
        skipPendingEntry(missingURL: true)
        if let metadata = parseExtendedInfo(trimmedLine) {
          pendingEntry = .metadata(metadata)
        } else {
          record(.malformedExtendedInfo)
          pendingEntry = .malformed
        }
        continue
      }

      if trimmedLine.hasPrefix("#") {
        continue
      }

      switch pendingEntry {
      case .malformed:
        skippedCount += 1
        pendingEntry = nil

      case .metadata(let metadata):
        pendingEntry = nil
        guard let mediaURL = validHTTPURL(trimmedLine, invalidWarning: &warningCounts) else {
          skippedCount += 1
          continue
        }

        let artworkURL = validArtworkURL(
          metadata.attributes["tvg-logo"],
          warningCounts: &warningCounts
        )
        let tvgName = nonempty(metadata.attributes["tvg-name"])
        let title = nonempty(metadata.title) ?? tvgName ?? fallbackTitle(for: mediaURL)
        let entry = M3UParsedEntry(
          title: title,
          mediaURL: mediaURL,
          groupTitle: nonempty(metadata.attributes["group-title"]),
          artworkURL: artworkURL,
          tvgID: nonempty(metadata.attributes["tvg-id"]),
          tvgName: tvgName,
          duration: metadata.duration
        )
        try await onEntry(entry)
        parsedCount += 1

      case nil:
        guard let mediaURL = validHTTPURL(trimmedLine, invalidWarning: &warningCounts) else {
          skippedCount += 1
          continue
        }
        try await onEntry(
          M3UParsedEntry(title: fallbackTitle(for: mediaURL), mediaURL: mediaURL)
        )
        parsedCount += 1
      }
    }

    skipPendingEntry(missingURL: true)
    try Task.checkCancellation()
    let report = M3UParseReport(
      parsedCount: parsedCount,
      skippedCount: skippedCount,
      warningCounts: warningCounts
    )
    guard parsedCount > 0 else {
      throw M3UParserError.noPlayableEntries(report: report)
    }
    return report
  }
}

extension M3UParser {
  fileprivate enum PendingEntry {
    case malformed
    case metadata(ExtendedInfo)
  }

  fileprivate struct ExtendedInfo {
    let duration: TimeInterval?
    let attributes: [String: String]
    let title: String
  }

  fileprivate func parseExtendedInfo(_ line: String) -> ExtendedInfo? {
    guard
      let colonIndex = line.firstIndex(of: ":"),
      let commaIndex = firstUnquotedComma(in: line, after: colonIndex)
    else {
      return nil
    }

    let metadataStart = line.index(after: colonIndex)
    let metadata = line[metadataStart..<commaIndex]
      .trimmingCharacters(in: .whitespaces)
    let durationEnd = metadata.firstIndex(where: { $0.isWhitespace }) ?? metadata.endIndex
    guard let rawDuration = Double(metadata[..<durationEnd]) else {
      return nil
    }

    let attributes = parseAttributes(String(metadata[durationEnd...]))
    let titleStart = line.index(after: commaIndex)
    let title = line[titleStart...].trimmingCharacters(in: .whitespaces)

    return ExtendedInfo(
      duration: rawDuration >= 0 ? rawDuration : nil,
      attributes: attributes,
      title: title
    )
  }

  fileprivate func firstUnquotedComma(in line: String, after index: String.Index) -> String.Index? {
    var cursor = line.index(after: index)
    var isQuoted = false
    var isEscaped = false

    while cursor < line.endIndex {
      let character = line[cursor]
      if character == "\\", isQuoted, !isEscaped {
        isEscaped = true
      } else {
        if character == "\"", !isEscaped {
          isQuoted.toggle()
        } else if character == ",", !isQuoted {
          return cursor
        }
        isEscaped = false
      }
      cursor = line.index(after: cursor)
    }
    return nil
  }

  fileprivate func parseAttributes(_ text: String) -> [String: String] {
    var attributes: [String: String] = [:]
    var cursor = text.startIndex

    while cursor < text.endIndex {
      skipWhitespace(in: text, cursor: &cursor)
      let keyStart = cursor
      while cursor < text.endIndex, !text[cursor].isWhitespace, text[cursor] != "=" {
        cursor = text.index(after: cursor)
      }
      let key = text[keyStart..<cursor].lowercased()
      skipWhitespace(in: text, cursor: &cursor)

      guard !key.isEmpty, cursor < text.endIndex, text[cursor] == "=" else {
        skipToken(in: text, cursor: &cursor)
        continue
      }

      cursor = text.index(after: cursor)
      skipWhitespace(in: text, cursor: &cursor)
      let value: String
      if cursor < text.endIndex, text[cursor] == "\"" {
        value = parseQuotedValue(in: text, cursor: &cursor)
      } else {
        let valueStart = cursor
        skipToken(in: text, cursor: &cursor)
        value = String(text[valueStart..<cursor])
      }
      attributes[key] = value
    }

    return attributes
  }

  fileprivate func parseQuotedValue(in text: String, cursor: inout String.Index) -> String {
    cursor = text.index(after: cursor)
    var value = ""
    var isEscaped = false

    while cursor < text.endIndex {
      let character = text[cursor]
      cursor = text.index(after: cursor)
      if character == "\"", !isEscaped {
        break
      }
      if character == "\\", !isEscaped {
        isEscaped = true
        continue
      }
      value.append(character)
      isEscaped = false
    }
    return value
  }

  fileprivate func skipWhitespace(in text: String, cursor: inout String.Index) {
    while cursor < text.endIndex, text[cursor].isWhitespace {
      cursor = text.index(after: cursor)
    }
  }

  fileprivate func skipToken(in text: String, cursor: inout String.Index) {
    while cursor < text.endIndex, !text[cursor].isWhitespace {
      cursor = text.index(after: cursor)
    }
  }

  fileprivate func validHTTPURL(
    _ value: String,
    invalidWarning warningCounts: inout [M3UParserWarning: Int]
  ) -> URL? {
    guard let url = URL(string: value, encodingInvalidCharacters: false) else {
      warningCounts[.invalidMediaURL, default: 0] += 1
      return nil
    }
    guard
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      url.host != nil
    else {
      warningCounts[.unsupportedMediaURLScheme, default: 0] += 1
      return nil
    }
    return url
  }

  fileprivate func validArtworkURL(
    _ value: String?,
    warningCounts: inout [M3UParserWarning: Int]
  ) -> URL? {
    guard let value = nonempty(value) else {
      return nil
    }
    guard
      let url = URL(string: value, encodingInvalidCharacters: false),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      url.host != nil
    else {
      warningCounts[.invalidArtworkURL, default: 0] += 1
      return nil
    }
    return url
  }

  fileprivate func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }

  fileprivate func fallbackTitle(for url: URL) -> String {
    let lastPathComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    return nonempty(lastPathComponent) ?? "Untitled"
  }
}
