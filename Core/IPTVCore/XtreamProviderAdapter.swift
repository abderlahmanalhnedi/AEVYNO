import AEVYNOSecurity
import Domain
import Foundation

public struct XtreamProviderAdapter: ProviderAdapter, Sendable {
  public static let defaultRequestTimeout: TimeInterval = 15

  private let credentialStore: any CredentialStore
  private let transport: any ProviderHTTPTransport
  private let requestBuilder: XtreamRequestBuilder

  public init(
    credentialStore: any CredentialStore,
    transport: any ProviderHTTPTransport = URLSessionProviderHTTPTransport(),
    requestTimeout: TimeInterval = XtreamProviderAdapter.defaultRequestTimeout
  ) {
    self.credentialStore = credentialStore
    self.transport = transport
    requestBuilder = XtreamRequestBuilder(timeout: requestTimeout)
  }

  public func discover(source: SourceConfiguration) async throws -> ProviderAccountSnapshot {
    let data = try await responseData(for: source, action: nil)
    let response: XtreamAuthenticationDTO
    do {
      response = try JSONDecoder().decode(XtreamAuthenticationDTO.self, from: data)
    } catch {
      throw ProviderAdapterError.malformedResponse
    }
    try Task.checkCancellation()

    guard let userInfo = response.userInfo, let authenticated = userInfo.authenticated else {
      throw ProviderAdapterError.providerResponseInvalid
    }
    guard authenticated else {
      throw ProviderAdapterError.authenticationRejected
    }

    let expiresAt = userInfo.expiresAtEpoch.flatMap { epoch -> Date? in
      guard epoch > 0 else { return nil }
      return Date(timeIntervalSince1970: TimeInterval(epoch))
    }
    return ProviderAccountSnapshot(
      status: userInfo.status,
      expiresAt: expiresAt,
      isTrial: userInfo.isTrial,
      activeConnections: userInfo.activeConnections,
      maximumConnections: userInfo.maximumConnections,
      allowedOutputFormats: userInfo.allowedOutputFormats,
      serverTimeZoneIdentifier: response.serverInfo?.timeZoneIdentifier
    )
  }

  public func categories(
    for kind: ProviderMediaKind,
    source: SourceConfiguration
  ) async throws -> ProviderCategoryResult {
    let data = try await responseData(for: source, action: XtreamAction(categoryKind: kind))
    let records: [XtreamCategoryDTO]
    do {
      records = try JSONDecoder().decode([XtreamCategoryDTO].self, from: data)
    } catch {
      throw ProviderAdapterError.malformedResponse
    }
    try Task.checkCancellation()

    var categories: [ProviderCategory] = []
    categories.reserveCapacity(records.count)
    var skippedCount = 0
    for record in records {
      try Task.checkCancellation()
      guard let providerID = record.providerID, let title = record.title else {
        skippedCount += 1
        continue
      }
      categories.append(
        ProviderCategory(
          id: ProviderCategory.ID(sourceID: source.id, kind: kind, providerID: providerID),
          sourceID: source.id,
          kind: kind,
          providerID: providerID,
          title: title
        )
      )
    }
    return ProviderCategoryResult(
      categories: categories,
      receivedCount: records.count,
      skippedCount: skippedCount
    )
  }

  public func fetchCatalog(
    for kind: ProviderMediaKind,
    source: SourceConfiguration,
    onItem: (ProviderCatalogItem) async throws -> Void
  ) async throws -> ProviderCatalogReport {
    let data = try await responseData(for: source, action: XtreamAction(catalogKind: kind))
    let records: [XtreamCatalogItemDTO]
    do {
      records = try JSONDecoder().decode([XtreamCatalogItemDTO].self, from: data)
    } catch {
      throw ProviderAdapterError.malformedResponse
    }
    try Task.checkCancellation()

    var normalizedCount = 0
    var skippedCount = 0
    for record in records {
      try Task.checkCancellation()
      let providerID = kind == .series ? record.seriesID : record.streamID
      guard let providerID, let title = record.title else {
        skippedCount += 1
        continue
      }

      let reference = ProviderItemReference(kind: kind, providerID: providerID)
      let categoryID = record.categoryID.map {
        ProviderCategory.ID(sourceID: source.id, kind: kind, providerID: $0)
      }
      let artworkURL = validArtworkURL(record.coverBig ?? record.cover ?? record.streamIcon)
      try await onItem(
        ProviderCatalogItem(
          id: ProviderCatalogItem.ID(sourceID: source.id, reference: reference),
          sourceID: source.id,
          providerReference: reference,
          title: title,
          categoryID: categoryID,
          artworkURL: artworkURL
        )
      )
      normalizedCount += 1
    }

    return ProviderCatalogReport(
      receivedCount: records.count,
      normalizedCount: normalizedCount,
      skippedCount: skippedCount
    )
  }
}

extension XtreamProviderAdapter {
  private func responseData(
    for source: SourceConfiguration,
    action: XtreamAction?
  ) async throws -> Data {
    try Task.checkCancellation()
    guard
      source.kind == .xtreamCompatible,
      source.isEnabled,
      let endpoint = source.endpoint,
      let credentialReference = source.credentialReference
    else {
      throw ProviderAdapterError.invalidSourceConfiguration
    }

    let credential: SourceCredential
    do {
      guard let resolvedCredential = try await credentialStore.credential(for: credentialReference)
      else {
        throw ProviderAdapterError.credentialUnavailable
      }
      credential = resolvedCredential
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ProviderAdapterError {
      throw error
    } catch {
      throw ProviderAdapterError.credentialUnavailable
    }

    let request = try requestBuilder.request(
      endpoint: endpoint,
      credential: credential,
      action: action
    )
    do {
      let (data, response) = try await transport.data(for: request)
      try Task.checkCancellation()
      guard (200..<300).contains(response.statusCode) else {
        if response.statusCode == 401 || response.statusCode == 403 {
          throw ProviderAdapterError.authenticationRejected
        }
        throw ProviderAdapterError.httpError(statusCode: response.statusCode)
      }
      return data
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ProviderAdapterError {
      throw error
    } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
      throw CancellationError()
    } catch let error as URLError where error.code == .timedOut {
      throw ProviderAdapterError.timedOut
    } catch {
      throw ProviderAdapterError.transportUnavailable
    }
  }

  private func validArtworkURL(_ rawValue: String?) -> URL? {
    guard
      let rawValue,
      let url = URL(string: rawValue),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      url.host != nil
    else {
      return nil
    }
    return url
  }
}
