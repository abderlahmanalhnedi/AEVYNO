import Domain
import Foundation

/// A compact CloudKit-safe favorite operation. It deliberately has no catalog, URL, or credential fields.
public struct CloudFavoriteRecord: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public let schemaVersion: Int
  public let mediaID: String
  public let isRemoved: Bool
  public let updatedAt: Date
  public let logicalRevision: UInt64
  public let operationID: String

  public init(
    schemaVersion: Int = Self.currentSchemaVersion, mediaID: String, isRemoved: Bool,
    updatedAt: Date, logicalRevision: UInt64, operationID: String
  ) {
    self.schemaVersion = schemaVersion
    self.mediaID = mediaID
    self.isRemoved = isRemoved
    self.updatedAt = updatedAt
    self.logicalRevision = logicalRevision
    self.operationID = operationID
  }
}

public enum CloudFavoriteValidationError: Error, Equatable, Sendable {
  case unsupportedSchema, invalidRecord, mismatchedIdentity
}

public enum FavoriteConflictResolver {
  public static func validate(_ record: CloudFavoriteRecord) throws {
    guard record.schemaVersion == CloudFavoriteRecord.currentSchemaVersion else {
      throw CloudFavoriteValidationError.unsupportedSchema
    }
    guard !record.mediaID.isEmpty, record.mediaID.utf8.count <= 4_096,
      !record.mediaID.contains("\0"),
      record.logicalRevision <= UInt64(Int64.max), !record.operationID.isEmpty,
      record.operationID.utf8.count <= 128, !record.operationID.contains("\0")
    else { throw CloudFavoriteValidationError.invalidRecord }
  }

  /// A tombstone wins an equal-version add, so an old add cannot resurrect a removal.
  public static func resolve(_ first: CloudFavoriteRecord, _ second: CloudFavoriteRecord) throws
    -> CloudFavoriteRecord
  {
    try validate(first)
    try validate(second)
    guard first.mediaID == second.mediaID else {
      throw CloudFavoriteValidationError.mismatchedIdentity
    }
    if first.logicalRevision != second.logicalRevision {
      return first.logicalRevision > second.logicalRevision ? first : second
    }
    if first.isRemoved != second.isRemoved { return first.isRemoved ? first : second }
    if first.operationID != second.operationID {
      return first.operationID > second.operationID ? first : second
    }
    return first.updatedAt >= second.updatedAt ? first : second
  }
}
