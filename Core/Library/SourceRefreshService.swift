import Domain
import Foundation
import IPTVCore

/// Coordinates the independent catalog and optional XMLTV refreshes for one source.
/// A usable catalog is never rolled back when its companion EPG endpoint is unavailable.
public struct SourceRefreshService: CatalogRefreshing, Sendable {
  private let catalogRefresh: any CatalogRefreshing
  private let xmltvAcquisition: XMLTVAcquisitionService?
  private let epgImporter: XMLTVEPGImportService?

  public init(
    catalogRefresh: any CatalogRefreshing,
    xmltvAcquisition: XMLTVAcquisitionService? = nil,
    epgImporter: XMLTVEPGImportService? = nil
  ) {
    self.catalogRefresh = catalogRefresh
    self.xmltvAcquisition = xmltvAcquisition
    self.epgImporter = epgImporter
  }

  public func refresh(
    _ source: SourceConfiguration,
    onStage: CatalogRefreshStageHandler?
  ) async throws -> CatalogRefreshReport {
    let report = try await catalogRefresh.refresh(source, onStage: onStage)
    guard source.epgConfiguration != nil, let xmltvAcquisition, let epgImporter else {
      return report
    }
    do {
      let data = try await xmltvAcquisition.acquire(from: source)
      _ = try await epgImporter.importXMLTV(
        stream: InputStream(data: data), sourceID: source.id, at: report.completedAt)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // Catalog and EPG are independently committed caches. Keep the catalog available.
    }
    return report
  }
}
