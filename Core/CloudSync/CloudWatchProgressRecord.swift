import Domain
import Foundation

public struct CloudWatchProgressRecord: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let mediaID: String
  public let position: TimeInterval
  public let duration: TimeInterval
  public let updatedAt: Date
  public let isCompleted: Bool
  public let resetGeneration: UInt64
  public let logicalRevision: UInt64
  public let operationID: String

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    mediaID: String,
    position: TimeInterval,
    duration: TimeInterval,
    updatedAt: Date,
    isCompleted: Bool,
    resetGeneration: UInt64,
    logicalRevision: UInt64,
    operationID: String
  ) {
    self.schemaVersion = schemaVersion
    self.mediaID = mediaID
    self.position = position
    self.duration = duration
    self.updatedAt = updatedAt
    self.isCompleted = isCompleted
    self.resetGeneration = resetGeneration
    self.logicalRevision = logicalRevision
    self.operationID = operationID
  }

  public init(
    progress: WatchProgress,
    resetGeneration: UInt64,
    logicalRevision: UInt64,
    operationID: String
  ) {
    self.init(
      mediaID: progress.mediaID,
      position: progress.position,
      duration: progress.duration,
      updatedAt: progress.updatedAt,
      isCompleted: progress.isCompleted,
      resetGeneration: resetGeneration,
      logicalRevision: logicalRevision,
      operationID: operationID
    )
  }

  public var progress: WatchProgress {
    WatchProgress(
      mediaID: mediaID,
      position: position,
      duration: duration,
      updatedAt: updatedAt,
      isCompleted: isCompleted
    )
  }

  func replacing(
    progress: WatchProgress? = nil,
    resetGeneration: UInt64? = nil,
    logicalRevision: UInt64? = nil,
    operationID: String? = nil
  ) -> Self {
    let value = progress ?? self.progress
    return Self(
      mediaID: value.mediaID,
      position: value.position,
      duration: value.duration,
      updatedAt: value.updatedAt,
      isCompleted: value.isCompleted,
      resetGeneration: resetGeneration ?? self.resetGeneration,
      logicalRevision: logicalRevision ?? self.logicalRevision,
      operationID: operationID ?? self.operationID
    )
  }
}

public enum CloudWatchProgressValidationError: Error, Equatable, Sendable {
  case unsupportedSchema
  case invalidRecord
  case mismatchedIdentity
}

public enum WatchProgressConflictResolver {
  public static func resolve(
    _ first: CloudWatchProgressRecord,
    _ second: CloudWatchProgressRecord
  ) throws -> CloudWatchProgressRecord {
    try validate(first)
    try validate(second)
    guard first.mediaID == second.mediaID else {
      throw CloudWatchProgressValidationError.mismatchedIdentity
    }

    if first == second { return first }

    if first.resetGeneration != second.resetGeneration {
      return first.resetGeneration > second.resetGeneration ? first : second
    }

    if first.isCompleted != second.isCompleted {
      return first.isCompleted ? first : second
    }

    if first.position != second.position {
      return first.position > second.position ? first : second
    }

    if first.logicalRevision != second.logicalRevision {
      return first.logicalRevision > second.logicalRevision ? first : second
    }

    if first.duration != second.duration {
      return deterministicWinner(first, second)
    }

    return deterministicWinner(first, second)
  }

  public static func validate(_ record: CloudWatchProgressRecord) throws {
    guard record.schemaVersion == CloudWatchProgressRecord.currentSchemaVersion else {
      throw CloudWatchProgressValidationError.unsupportedSchema
    }
    guard
      !record.mediaID.isEmpty,
      record.mediaID.utf8.count <= 4_096,
      !record.mediaID.contains("\0"),
      record.position.isFinite,
      record.position >= 0,
      record.duration.isFinite,
      record.duration > 0,
      record.position <= record.duration,
      record.resetGeneration <= UInt64(Int64.max),
      record.logicalRevision <= UInt64(Int64.max),
      !record.operationID.isEmpty,
      record.operationID.utf8.count <= 128,
      !record.operationID.contains("\0")
    else {
      throw CloudWatchProgressValidationError.invalidRecord
    }
  }

  private static func deterministicWinner(
    _ first: CloudWatchProgressRecord,
    _ second: CloudWatchProgressRecord
  ) -> CloudWatchProgressRecord {
    if first.operationID != second.operationID {
      return first.operationID > second.operationID ? first : second
    }
    // This final comparison handles malformed duplicate operation IDs without making wall-clock
    // time the primary conflict rule.
    return first.updatedAt >= second.updatedAt ? first : second
  }
}
