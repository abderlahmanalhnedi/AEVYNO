import Foundation

/// An opaque XMLTV channel identifier. Persistence scopes it by source configuration ID.
public struct EPGChannelIdentity: Codable, Hashable, Sendable, RawRepresentable {
  public let rawValue: String

  public init?(rawValue: String) {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.utf8.count <= 512, !value.contains("\0") else { return nil }
    self.rawValue = value
  }
}

public struct EPGTimeRange: Codable, Equatable, Sendable {
  public let start: Date
  public let end: Date

  public init?(start: Date, end: Date) {
    guard end > start else { return nil }
    self.start = start
    self.end = end
  }

  public func contains(_ instant: Date) -> Bool { start <= instant && instant < end }
}

public struct EPGProgramme: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let channelID: EPGChannelIdentity
  public let timeRange: EPGTimeRange
  public let title: String
  public let subtitle: String?
  public let description: String?
  public let category: String?

  public init?(
    channelID: EPGChannelIdentity, timeRange: EPGTimeRange, title: String, subtitle: String? = nil,
    description: String? = nil, category: String? = nil
  ) {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.utf8.count <= 4_096 else { return nil }
    self.channelID = channelID
    self.timeRange = timeRange
    self.title = normalized
    self.subtitle = Self.normalized(subtitle)
    self.description = Self.normalized(description)
    self.category = Self.normalized(category)
    id =
      "\(channelID.rawValue)|\(timeRange.start.timeIntervalSince1970)|\(timeRange.end.timeIntervalSince1970)|\(normalized)"
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : String(trimmed.prefix(16_384))
  }
}

public struct EPGNowNextPresentation: Equatable, Sendable {
  public let now: EPGProgramme?
  public let next: EPGProgramme?

  public init(now: EPGProgramme?, next: EPGProgramme?) {
    self.now = now
    self.next = next
  }
}
