import Domain
import Foundation
import IPTVCore
import Persistence

public struct XMLTVEPGImportReport: Equatable, Sendable {
  public let parsedProgrammeCount: Int
  public let skippedProgrammeCount: Int
  public let committedAt: Date

  public init(parsedProgrammeCount: Int, skippedProgrammeCount: Int, committedAt: Date) {
    self.parsedProgrammeCount = parsedProgrammeCount
    self.skippedProgrammeCount = skippedProgrammeCount
    self.committedAt = committedAt
  }
}

enum XMLTVImportPhase: Equatable, Sendable {
  case parsing
  case spoolProduction
  case staging
  case publication
}

/// Streams XMLTV into a normalized temporary spool, then stages bounded batches before one atomic
/// publication. The spool contains only normalized, non-secret EPG metadata and is always removed.
public actor XMLTVEPGImportService {
  private static let spoolReadSize = 64 * 1024
  private static let maximumSpoolLineSize = 64 * 1024

  private let repository: any EPGImportRepository
  private let parser: XMLTVParser
  private let temporaryDirectory: URL
  private let phaseHook: (@Sendable (XMLTVImportPhase) throws -> Void)?

  public init(
    repository: any EPGImportRepository, parser: XMLTVParser = XMLTVParser(),
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) {
    self.repository = repository
    self.parser = parser
    self.temporaryDirectory = temporaryDirectory
    phaseHook = nil
  }

  /// Internal deterministic test seam. Production callers do not install a hook.
  init(
    repository: any EPGImportRepository, parser: XMLTVParser = XMLTVParser(),
    temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    phaseHook: @escaping @Sendable (XMLTVImportPhase) throws -> Void
  ) {
    self.repository = repository
    self.parser = parser
    self.temporaryDirectory = temporaryDirectory
    self.phaseHook = phaseHook
  }

  public func importXMLTV(
    stream: InputStream, sourceID: SourceConfiguration.ID, at now: Date
  ) async throws -> XMLTVEPGImportReport {
    let stagingID = try await repository.beginStaging(sourceID: sourceID)
    let spool = temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: spool)
    }
    do {
      FileManager.default.createFile(atPath: spool.path, contents: nil)
      let writer = try FileHandle(forWritingTo: spool)
      defer { try? writer.close() }
      let encoder = JSONEncoder()
      try phaseHook?(.parsing)
      let parseReport = try parser.parse(stream: stream) { programme in
        try Task.checkCancellation()
        try writer.write(encoder.encode(programme))
        try writer.write(contentsOf: Data([0x0A]))
        try self.phaseHook?(.spoolProduction)
      }
      try writer.close()
      try Task.checkCancellation()
      try await stageSpool(spool, stagingID: stagingID)
      try Task.checkCancellation()
      try phaseHook?(.publication)
      try await repository.commitStagedReplacement(stagingID, at: now)
      return XMLTVEPGImportReport(
        parsedProgrammeCount: parseReport.programmeCount,
        skippedProgrammeCount: parseReport.skippedProgrammeCount, committedAt: now)
    } catch {
      await repository.discardStaging(stagingID)
      throw error
    }
  }

  /// Records a safe current failure fact while deliberately retaining the previous committed dataset.
  public func recordFailure(sourceID: SourceConfiguration.ID, at: Date, error: Error) async throws {
    guard !Self.isCancellation(error) else { return }
    try await repository.recordFailure(
      sourceID: sourceID, at: at, category: Self.failureCategory(for: error))
  }

  static func failureCategory(for error: Error) -> EPGFailureCategory {
    if let error = error as? M3UAcquisitionError {
      switch error {
      case .transportUnavailable, .authenticationRejected, .httpError, .unsafeRedirect:
        return .networkUnavailable
      case .timedOut: return .timeout
      case .responseTooLarge: return .responseTooLarge
      case .emptyResponse, .invalidSourceConfiguration: return .invalidGuideData
      }
    }
    if error is XMLTVParserError { return .invalidGuideData }
    if error is EPGStoreError { return .persistenceFailure }
    return .unknown
  }

  private static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || error as? XMLTVParserError == .cancelled
  }

  private func stageSpool(_ url: URL, stagingID: UUID) async throws {
    let reader = try FileHandle(forReadingFrom: url)
    defer { try? reader.close() }
    let decoder = JSONDecoder()
    var pending = Data()
    var batch: [EPGProgramme] = []
    while let chunk = try reader.read(upToCount: Self.spoolReadSize), !chunk.isEmpty {
      try Task.checkCancellation()
      pending.append(chunk)
      while let newline = pending.firstIndex(of: 0x0A) {
        let line = pending.prefix(upTo: newline)
        pending.removeSubrange(...newline)
        guard !line.isEmpty else { continue }
        batch.append(try decoder.decode(EPGProgramme.self, from: line))
        if batch.count == SQLiteEPGStore.batchLimit {
          try phaseHook?(.staging)
          try await repository.stage(batch, in: stagingID)
          batch.removeAll(keepingCapacity: true)
        }
      }
      guard pending.count <= Self.maximumSpoolLineSize else { throw EPGStoreError.invalidInput }
    }
    guard pending.isEmpty else { throw EPGStoreError.invalidInput }
    if !batch.isEmpty {
      try phaseHook?(.staging)
      try await repository.stage(batch, in: stagingID)
    }
  }
}
