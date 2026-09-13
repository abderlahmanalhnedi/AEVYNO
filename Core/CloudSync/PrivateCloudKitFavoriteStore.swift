#if canImport(CloudKit)
  import CloudKit
  import CryptoKit
  import Foundation

  /// CloudKit-only adapter; Domain and UI never see CKRecord or CKDatabase.
  public actor PrivateCloudKitFavoriteStore: CloudFavoriteStore {
    public static let recordType = "AEVYNO_Favorite_v1"
    public static let zoneName = "AEVYNO_Favorite_v1"
    public static let subscriptionID = "AEVYNO_Favorite_v1_changes"
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var ready = false

    public init(container: CKContainer) {
      self.container = container
      database = container.privateCloudDatabase
      zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }
    public func accountAvailability() async -> CloudAccountAvailability {
      guard let status = try? await container.accountStatus() else { return .couldNotDetermine }
      switch status {
      case .available: return CloudAccountAvailability.available
      case .noAccount: return CloudAccountAvailability.noAccount
      case .restricted: return CloudAccountAvailability.restricted
      case .temporarilyUnavailable: return CloudAccountAvailability.temporarilyUnavailable
      case .couldNotDetermine: return CloudAccountAvailability.couldNotDetermine
      @unknown default: return CloudAccountAvailability.couldNotDetermine
      }
    }
    public func fetchChanges(since token: Data?) async throws -> CloudFavoriteChangeBatch {
      try await infrastructure()
      do {
        let result = try await database.recordZoneChanges(
          inZoneWith: zoneID, since: try decode(token), desiredKeys: Field.all, resultsLimit: 200)
        guard !result.moreComing else {
          throw CloudProgressStoreError.serviceUnavailable(retryAfter: nil)
        }
        let records = try result.modificationResultsByID.values.compactMap {
          result -> CloudFavoriteRecord? in
          switch result {
          case .success(let modification): return try read(modification.record)
          case .failure(let error): throw error
          }
        }
        return CloudFavoriteChangeBatch(
          records: records, changeToken: try encode(result.changeToken))
      } catch let error as CloudProgressStoreError {
        throw error
      } catch { throw CloudProgressStoreError.unknown }
    }
    public func save(_ models: [CloudFavoriteRecord]) async throws -> [CloudFavoriteRecord] {
      guard models.count <= 200 else { throw CloudProgressStoreError.invalidData }
      for model in models {
        try FavoriteConflictResolver.validate(model)
      }
      guard !models.isEmpty else { return [] }
      try await infrastructure()
      do {
        let identifiers = models.map { recordID($0.mediaID) }
        let existing = try await database.records(for: identifiers)
        let records = try models.map { model -> CKRecord in
          let identifier = recordID(model.mediaID)
          let resolved: CloudFavoriteRecord
          let record: CKRecord
          if case .success(let found)? = existing[identifier] {
            record = found
            resolved = try FavoriteConflictResolver.resolve(model, read(found))
          } else {
            record = CKRecord(recordType: Self.recordType, recordID: identifier)
            resolved = model
          }
          write(resolved, to: record)
          return record
        }
        let response = try await database.modifyRecords(
          saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        return try response.saveResults.values.map { result in
          switch result {
          case .success(let record): return try read(record)
          case .failure(let error): throw error
          }
        }.sorted { $0.mediaID < $1.mediaID }
      } catch let error as CloudFavoriteValidationError {
        throw error == .unsupportedSchema
          ? CloudProgressStoreError.unsupportedSchema : CloudProgressStoreError.invalidData
      } catch { throw CloudProgressStoreError.unknown }
    }
    private func infrastructure() async throws {
      guard !ready else { return }
      do {
        let zones = try await database.recordZones(for: [zoneID])
        if case .failure? = zones[zoneID] {
          _ = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        }
        let subscriptions = try await database.subscriptions(for: [Self.subscriptionID])
        if case .failure? = subscriptions[Self.subscriptionID] {
          let subscription = CKRecordZoneSubscription(
            zoneID: zoneID, subscriptionID: Self.subscriptionID)
          let info = CKSubscription.NotificationInfo()
          info.shouldSendContentAvailable = true
          subscription.notificationInfo = info
          _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        }
        ready = true
      } catch { throw CloudProgressStoreError.configuration }
    }
    private enum Field {
      static let schema = "schemaVersion", mediaID = "mediaID", removed = "isRemoved",
        updated = "updatedAt", revision = "logicalRevision", operation = "operationID"
      static let all: [CKRecord.FieldKey] = [
        schema, mediaID, removed, updated, revision, operation,
      ]
    }
    private func read(_ record: CKRecord) throws -> CloudFavoriteRecord {
      guard record.recordType == Self.recordType, let schema = record[Field.schema] as? NSNumber,
        let mediaID = record[Field.mediaID] as? String,
        let removed = record[Field.removed] as? NSNumber,
        let updated = record[Field.updated] as? Date,
        let revision = record[Field.revision] as? NSNumber,
        let operation = record[Field.operation] as? String
      else { throw CloudProgressStoreError.invalidData }
      let value = CloudFavoriteRecord(
        schemaVersion: schema.intValue, mediaID: mediaID, isRemoved: removed.boolValue,
        updatedAt: updated, logicalRevision: UInt64(revision.int64Value), operationID: operation)
      guard record.recordID == recordID(mediaID) else { throw CloudProgressStoreError.invalidData }
      try FavoriteConflictResolver.validate(value)
      return value
    }
    private func write(_ value: CloudFavoriteRecord, to record: CKRecord) {
      record[Field.schema] = value.schemaVersion as NSNumber
      record[Field.mediaID] = value.mediaID as NSString
      record[Field.removed] = value.isRemoved as NSNumber
      record[Field.updated] = value.updatedAt as NSDate
      record[Field.revision] = Int64(value.logicalRevision) as NSNumber
      record[Field.operation] = value.operationID as NSString
    }
    private func recordID(_ mediaID: String) -> CKRecord.ID {
      CKRecord.ID(
        recordName: SHA256.hash(data: Data(mediaID.utf8)).map { String(format: "%02x", $0) }
          .joined(), zoneID: zoneID)
    }
    private func encode(_ token: CKServerChangeToken?) throws -> Data? {
      guard let token else { return nil }
      return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
    private func decode(_ data: Data?) throws -> CKServerChangeToken? {
      guard let data else { return nil }
      return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
  }
#endif
