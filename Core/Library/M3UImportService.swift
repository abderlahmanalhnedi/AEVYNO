import Domain
import IPTVCore

public protocol M3UImportSink: Sendable {
  func beginImport(for sourceID: SourceConfiguration.ID) async throws
  func write(_ items: [ImportedMediaItem]) async throws
  func commitImport() async throws
  func rollbackImport() async
}

public struct M3UImportReport: Equatable, Sendable {
  public let parsedCount: Int
  public let importedCount: Int
  public let skippedCount: Int
  public let duplicateCount: Int
  public let warningCounts: [M3UParserWarning: Int]

  public init(
    parsedCount: Int,
    importedCount: Int,
    skippedCount: Int,
    duplicateCount: Int,
    warningCounts: [M3UParserWarning: Int]
  ) {
    self.parsedCount = parsedCount
    self.importedCount = importedCount
    self.skippedCount = skippedCount
    self.duplicateCount = duplicateCount
    self.warningCounts = warningCounts
  }
}

public struct M3UImportService: Sendable {
  public static let defaultBatchSize = 256

  private let parser: M3UParser
  private let batchSize: Int

  public init(
    parser: M3UParser = M3UParser(),
    batchSize: Int = M3UImportService.defaultBatchSize
  ) {
    self.parser = parser
    self.batchSize = max(1, batchSize)
  }

  public func importPlaylist<Lines: AsyncSequence>(
    lines: Lines,
    sourceID: SourceConfiguration.ID,
    sink: any M3UImportSink
  ) async throws -> M3UImportReport where Lines.Element == String {
    try Task.checkCancellation()
    try await sink.beginImport(for: sourceID)

    var batch: [ImportedMediaItem] = []
    batch.reserveCapacity(batchSize)
    var occurrencesByHashedAnchor: [String: Int] = [:]
    var duplicateCount = 0
    var importedCount = 0

    do {
      let parseReport = try await parser.parse(lines: lines) { parsedEntry in
        try Task.checkCancellation()

        let stableKey: String
        if let tvgID = parsedEntry.tvgID, !tvgID.isEmpty {
          stableKey = "tvg-id:\(tvgID)"
        } else {
          stableKey = "media-url:\(parsedEntry.mediaURL.absoluteString)"
        }

        let hashedAnchor = ImportedMediaItem.ID(
          sourceID: sourceID,
          stableKey: stableKey,
          occurrence: 0
        ).rawValue
        let occurrence = occurrencesByHashedAnchor[hashedAnchor, default: 0]
        occurrencesByHashedAnchor[hashedAnchor] = occurrence + 1
        if occurrence > 0 {
          duplicateCount += 1
        }
        let itemID =
          occurrence == 0
          ? ImportedMediaItem.ID(rawValue: hashedAnchor)
          : ImportedMediaItem.ID(
            sourceID: sourceID,
            stableKey: stableKey,
            occurrence: occurrence
          )

        batch.append(
          ImportedMediaItem(
            id: itemID,
            sourceID: sourceID,
            title: parsedEntry.title,
            mediaURL: parsedEntry.mediaURL,
            groupTitle: parsedEntry.groupTitle,
            artworkURL: parsedEntry.artworkURL,
            tvgID: parsedEntry.tvgID,
            tvgName: parsedEntry.tvgName,
            duration: parsedEntry.duration
          )
        )

        if batch.count == batchSize {
          try await sink.write(batch)
          importedCount += batch.count
          batch.removeAll(keepingCapacity: true)
        }
      }

      try Task.checkCancellation()
      if !batch.isEmpty {
        try await sink.write(batch)
        importedCount += batch.count
        batch.removeAll(keepingCapacity: false)
      }
      try Task.checkCancellation()
      try await sink.commitImport()

      return M3UImportReport(
        parsedCount: parseReport.parsedCount,
        importedCount: importedCount,
        skippedCount: parseReport.skippedCount,
        duplicateCount: duplicateCount,
        warningCounts: parseReport.warningCounts
      )
    } catch {
      await sink.rollbackImport()
      throw error
    }
  }
}
