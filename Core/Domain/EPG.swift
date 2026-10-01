import Foundation

/// Safe, provider-neutral outcome of the latest attempted EPG refresh.
public enum EPGRefreshResult: String, Codable, Equatable, Sendable {
  case success
  case failure
}

/// Deliberately small diagnostics surface; it never carries an endpoint, provider, or parser detail.
public enum EPGFailureCategory: String, Codable, Equatable, Sendable {
  case networkUnavailable
  case timeout
  case responseTooLarge
  case invalidGuideData
  case persistenceFailure
  case unknown
}

public enum EPGCoverageState: Equatable, Sendable {
  case noData
  case futureOnly
  case currentCoverage
  case expired
}

/// Current local operational facts for one source's EPG cache, not a refresh history.
public struct EPGHealth: Equatable, Sendable {
  public let configured: Bool
  public let lastAttemptedAt: Date?
  public let lastSuccessfulAt: Date?
  public let lastCommittedProgrammeCount: Int
  public let coverageStartAt: Date?
  public let coverageEndAt: Date?
  public let lastResult: EPGRefreshResult?
  public let lastFailureCategory: EPGFailureCategory?

  public init(
    configured: Bool, lastAttemptedAt: Date? = nil, lastSuccessfulAt: Date? = nil,
    lastCommittedProgrammeCount: Int = 0, coverageStartAt: Date? = nil,
    coverageEndAt: Date? = nil, lastResult: EPGRefreshResult? = nil,
    lastFailureCategory: EPGFailureCategory? = nil
  ) {
    self.configured = configured
    self.lastAttemptedAt = lastAttemptedAt
    self.lastSuccessfulAt = lastSuccessfulAt
    self.lastCommittedProgrammeCount = lastCommittedProgrammeCount
    self.coverageStartAt = coverageStartAt
    self.coverageEndAt = coverageEndAt
    self.lastResult = lastResult
    self.lastFailureCategory = lastFailureCategory
  }

  public func coverage(at instant: Date) -> EPGCoverageState {
    guard lastCommittedProgrammeCount > 0, let coverageStartAt, let coverageEndAt else {
      return .noData
    }
    if coverageEndAt <= instant { return .expired }
    if coverageStartAt > instant { return .futureOnly }
    return .currentCoverage
  }
}

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

/// A bounded absolute-time window. Views format these UTC instants locally.
public struct EPGGuideInterval: Equatable, Sendable {
  public static let maximumDuration: TimeInterval = 8 * 60 * 60
  public let start: Date
  public let end: Date

  public init?(start: Date, end: Date) {
    guard end > start, end.timeIntervalSince(start) <= Self.maximumDuration else { return nil }
    self.start = start
    self.end = end
  }

  public static func initial(at now: Date) -> EPGGuideInterval {
    EPGGuideInterval(
      start: now.addingTimeInterval(-2 * 60 * 60), end: now.addingTimeInterval(6 * 60 * 60))!
  }

  /// Moves an already bounded window by whole Guide windows without consulting wall-clock time.
  public func shifted(byWindowCount count: Int) -> EPGGuideInterval {
    EPGGuideInterval(
      start: start.addingTimeInterval(Self.maximumDuration * Double(count)),
      end: end.addingTimeInterval(Self.maximumDuration * Double(count)))!
  }
}

/// Guide-safe channel data. `id` is the stable playable catalog identity, never an EPG ID.
public struct EPGGuideChannel: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let programmes: [EPGProgramme]

  public init(id: String, title: String, programmes: [EPGProgramme]) {
    self.id = id
    self.title = title
    self.programmes = programmes
  }
}

public struct EPGGuidePresentation: Equatable, Sendable {
  public let interval: EPGGuideInterval
  public let channels: [EPGGuideChannel]
  public let nextOffset: Int?

  public init(interval: EPGGuideInterval, channels: [EPGGuideChannel], nextOffset: Int?) {
    self.interval = interval
    self.channels = channels
    self.nextOffset = nextOffset
  }
}
