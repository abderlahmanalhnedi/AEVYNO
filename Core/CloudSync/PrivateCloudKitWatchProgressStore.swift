#if canImport(CloudKit)
  import CloudKit
  import CryptoKit
  import Foundation

  public actor PrivateCloudKitWatchProgressStore: CloudWatchProgressStore {
    public static let recordType = "AEVYNO_WatchProgress_v1"
    public static let zoneName = "AEVYNO_WatchProgress_v1"
    public static let subscriptionID = "AEVYNO_WatchProgress_v1_changes"

    private enum Field {
      static let schemaVersion = "schemaVersion"
      static let mediaID = "mediaID"
      static let position = "positionSeconds"
      static let duration = "durationSeconds"
      static let updatedAt = "updatedAt"
      static let completed = "completed"
      static let resetGeneration = "resetGeneration"
      static let logicalRevision = "logicalRevision"
      static let operationID = "operationID"

      static let all: [CKRecord.FieldKey] = [
        schemaVersion,
        mediaID,
        position,
        duration,
        updatedAt,
        completed,
        resetGeneration,
        logicalRevision,
        operationID,
      ]
    }

    private static let maximumSaveBatch = 200
    private static let maximumFetchBatches = 50

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var infrastructureReady = false

    /// The adapter always selects the injected container's private database.
    public init(container: CKContainer) {
      self.container = container
      database = container.privateCloudDatabase
      zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public func accountAvailability() async -> CloudAccountAvailability {
      do {
        switch try await container.accountStatus() {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .couldNotDetermine: return .couldNotDetermine
        @unknown default: return .couldNotDetermine
        }
      } catch {
        return .couldNotDetermine
      }
    }

    public func fetchChanges(since changeToken: Data?) async throws
      -> CloudWatchProgressChangeBatch
    {
      try await ensureInfrastructure()
      do {
        return try await fetchZoneChanges(since: decodeToken(changeToken))
      } catch let error as CKError where error.code == .changeTokenExpired {
        do {
          return try await fetchZoneChanges(since: nil)
        } catch {
          if isMissingZone(error) { infrastructureReady = false }
          throw normalize(error)
        }
      } catch let error as CloudWatchProgressValidationError {
        throw error == .unsupportedSchema
          ? CloudProgressStoreError.unsupportedSchema
          : CloudProgressStoreError.invalidData
      } catch {
        if isMissingZone(error) { infrastructureReady = false }
        throw normalize(error)
      }
    }

    public func save(_ records: [CloudWatchProgressRecord]) async throws
      -> [CloudWatchProgressRecord]
    {
      guard records.count <= Self.maximumSaveBatch else {
        throw CloudProgressStoreError.invalidData
      }
      for record in records {
        do {
          try WatchProgressConflictResolver.validate(record)
        } catch CloudWatchProgressValidationError.unsupportedSchema {
          throw CloudProgressStoreError.unsupportedSchema
        } catch {
          throw CloudProgressStoreError.invalidData
        }
      }
      guard !records.isEmpty else { return [] }

      try await ensureInfrastructure()
      let recordIDs = records.map { recordID(for: $0.mediaID) }
      do {
        let existing = try await database.records(for: recordIDs)
        var cloudRecords: [CKRecord] = []
        cloudRecords.reserveCapacity(records.count)
        for model in records {
          let id = recordID(for: model.mediaID)
          let cloudRecord: CKRecord
          let resolvedModel: CloudWatchProgressRecord
          switch existing[id] {
          case .success(let found):
            cloudRecord = found
            resolvedModel = try WatchProgressConflictResolver.resolve(model, decode(found))
          case .failure(let error) where isUnknownItem(error):
            cloudRecord = CKRecord(recordType: Self.recordType, recordID: id)
            resolvedModel = model
          case .failure(let error):
            throw error
          case nil:
            cloudRecord = CKRecord(recordType: Self.recordType, recordID: id)
            resolvedModel = model
          }
          write(resolvedModel, to: cloudRecord)
          cloudRecords.append(cloudRecord)
        }

        let result = try await database.modifyRecords(
          saving: cloudRecords,
          deleting: [],
          savePolicy: .ifServerRecordUnchanged,
          atomically: false
        )
        var committedModels: [CloudWatchProgressRecord] = []
        committedModels.reserveCapacity(records.count)
        for saveResult in result.saveResults.values {
          switch saveResult {
          case .success(let committedRecord):
            committedModels.append(try decode(committedRecord))
          case .failure(let error):
            throw error
          }
        }
        guard committedModels.count == records.count else {
          throw CloudProgressStoreError.invalidData
        }
        return committedModels.sorted { $0.mediaID < $1.mediaID }
      } catch let error as CloudWatchProgressValidationError {
        throw error == .unsupportedSchema
          ? CloudProgressStoreError.unsupportedSchema
          : CloudProgressStoreError.invalidData
      } catch {
        if isMissingZone(error) { infrastructureReady = false }
        throw normalize(error)
      }
    }

    private func ensureInfrastructure() async throws {
      guard !infrastructureReady else { return }
      do {
        let zones = try await database.recordZones(for: [zoneID])
        switch zones[zoneID] {
        case .success:
          break
        case .failure(let error) where isUnknownItem(error) || isMissingZone(error):
          let result = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
          )
          if case .failure(let error) = result.saveResults[zoneID] { throw error }
        case .failure(let error):
          throw error
        case nil:
          throw CloudProgressStoreError.configuration
        }

        try await ensureSubscription()
        infrastructureReady = true
      } catch let error as CloudProgressStoreError {
        throw error
      } catch {
        throw normalize(error)
      }
    }

    private func ensureSubscription() async throws {
      let subscriptions = try await database.subscriptions(for: [Self.subscriptionID])
      switch subscriptions[Self.subscriptionID] {
      case .success:
        return
      case .failure(let error) where isUnknownItem(error):
        let subscription = CKRecordZoneSubscription(
          zoneID: zoneID,
          subscriptionID: Self.subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        let result = try await database.modifySubscriptions(
          saving: [subscription],
          deleting: []
        )
        if case .failure(let error) = result.saveResults[Self.subscriptionID] { throw error }
      case .failure(let error):
        throw error
      case nil:
        throw CloudProgressStoreError.configuration
      }
    }

    private func fetchZoneChanges(since initialToken: CKServerChangeToken?) async throws
      -> CloudWatchProgressChangeBatch
    {
      var token = initialToken
      var records: [CloudWatchProgressRecord] = []
      for batchIndex in 0..<Self.maximumFetchBatches {
        try Task.checkCancellation()
        let result = try await database.recordZoneChanges(
          inZoneWith: zoneID,
          since: token,
          desiredKeys: Field.all,
          resultsLimit: Self.maximumSaveBatch
        )
        for modificationResult in result.modificationResultsByID.values {
          switch modificationResult {
          case .success(let modification):
            records.append(try decode(modification.record))
          case .failure(let error):
            throw error
          }
        }
        token = result.changeToken
        if !result.moreComing {
          return CloudWatchProgressChangeBatch(
            records: records,
            changeToken: try encodeToken(result.changeToken)
          )
        }
        if batchIndex == Self.maximumFetchBatches - 1 {
          throw CloudProgressStoreError.serviceUnavailable(retryAfter: nil)
        }
      }
      throw CloudProgressStoreError.serviceUnavailable(retryAfter: nil)
    }

    private func decode(_ record: CKRecord) throws -> CloudWatchProgressRecord {
      guard record.recordType == Self.recordType else {
        throw CloudProgressStoreError.invalidData
      }
      guard
        let schema = integer(record[Field.schemaVersion]),
        let mediaID = record[Field.mediaID] as? String,
        let position = number(record[Field.position]),
        let duration = number(record[Field.duration]),
        let updatedAt = record[Field.updatedAt] as? Date,
        let completed = boolean(record[Field.completed]),
        let resetGeneration = integer(record[Field.resetGeneration]),
        let logicalRevision = integer(record[Field.logicalRevision]),
        let operationID = record[Field.operationID] as? String,
        schema >= 0,
        resetGeneration >= 0,
        logicalRevision >= 0
      else {
        throw CloudProgressStoreError.invalidData
      }
      let model = CloudWatchProgressRecord(
        schemaVersion: Int(schema),
        mediaID: mediaID,
        position: position,
        duration: duration,
        updatedAt: updatedAt,
        isCompleted: completed,
        resetGeneration: UInt64(resetGeneration),
        logicalRevision: UInt64(logicalRevision),
        operationID: operationID
      )
      guard record.recordID == recordID(for: mediaID) else {
        throw CloudProgressStoreError.invalidData
      }
      do {
        try WatchProgressConflictResolver.validate(model)
      } catch CloudWatchProgressValidationError.unsupportedSchema {
        throw CloudProgressStoreError.unsupportedSchema
      } catch {
        throw CloudProgressStoreError.invalidData
      }
      return model
    }

    private func write(_ model: CloudWatchProgressRecord, to record: CKRecord) {
      record[Field.schemaVersion] = NSNumber(value: model.schemaVersion)
      record[Field.mediaID] = model.mediaID as NSString
      record[Field.position] = NSNumber(value: model.position)
      record[Field.duration] = NSNumber(value: model.duration)
      record[Field.updatedAt] = model.updatedAt as NSDate
      record[Field.completed] = NSNumber(value: model.isCompleted)
      record[Field.resetGeneration] = NSNumber(value: Int64(model.resetGeneration))
      record[Field.logicalRevision] = NSNumber(value: Int64(model.logicalRevision))
      record[Field.operationID] = model.operationID as NSString
    }

    private func recordID(for mediaID: String) -> CKRecord.ID {
      let digest = SHA256.hash(data: Data(mediaID.utf8))
      let name = digest.map { String(format: "%02x", $0) }.joined()
      return CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    private func decodeToken(_ data: Data?) throws -> CKServerChangeToken? {
      guard let data else { return nil }
      do {
        return try NSKeyedUnarchiver.unarchivedObject(
          ofClass: CKServerChangeToken.self,
          from: data
        )
      } catch {
        throw CloudProgressStoreError.invalidData
      }
    }

    private func encodeToken(_ token: CKServerChangeToken) throws -> Data {
      do {
        return try NSKeyedArchiver.archivedData(
          withRootObject: token,
          requiringSecureCoding: true
        )
      } catch {
        throw CloudProgressStoreError.invalidData
      }
    }

    private func integer(_ value: CKRecordValue?) -> Int64? {
      (value as? NSNumber)?.int64Value
    }

    private func number(_ value: CKRecordValue?) -> Double? {
      (value as? NSNumber)?.doubleValue
    }

    private func boolean(_ value: CKRecordValue?) -> Bool? {
      (value as? NSNumber)?.boolValue
    }

    private func isUnknownItem(_ error: any Error) -> Bool {
      (error as? CKError)?.code == .unknownItem
    }

    private func isMissingZone(_ error: any Error) -> Bool {
      guard let code = (error as? CKError)?.code else { return false }
      return code == .zoneNotFound || code == .userDeletedZone
    }

    private func normalize(_ error: any Error) -> CloudProgressStoreError {
      if let normalized = error as? CloudProgressStoreError { return normalized }
      guard let cloudError = error as? CKError else { return .unknown }
      let retryAfter = (cloudError.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
      switch cloudError.code {
      case .networkUnavailable, .networkFailure, .serverResponseLost:
        return .networkUnavailable
      case .serviceUnavailable, .zoneBusy, .zoneNotFound, .userDeletedZone:
        return .serviceUnavailable(retryAfter: retryAfter)
      case .requestRateLimited:
        return .rateLimited(retryAfter: retryAfter)
      case .serverRecordChanged, .batchRequestFailed, .changeTokenExpired:
        return .serverConflict
      case .quotaExceeded:
        return .quotaExceeded
      case .notAuthenticated:
        return .accountUnavailable(.noAccount)
      case .managedAccountRestricted, .permissionFailure:
        return .accountUnavailable(.restricted)
      case .accountTemporarilyUnavailable:
        return .accountUnavailable(.temporarilyUnavailable)
      case .badContainer, .badDatabase, .missingEntitlement:
        return .configuration
      case .incompatibleVersion:
        return .unsupportedSchema
      case .invalidArguments, .constraintViolation, .serverRejectedRequest, .limitExceeded:
        return .invalidData
      case .operationCancelled:
        return Task.isCancelled ? .networkUnavailable : .unknown
      default:
        return .unknown
      }
    }
  }
#endif
