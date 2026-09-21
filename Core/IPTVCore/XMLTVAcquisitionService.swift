import Domain
import Foundation

/// Bounded, provider-neutral XMLTV acquisition for explicitly configured M3U sources only.
public struct XMLTVAcquisitionService: Sendable {
  public static let defaultMaximumByteCount = 64 * 1_024 * 1_024
  public static let defaultRequestTimeout: TimeInterval = 30

  private let transport: any M3UAcquisitionTransport
  private let maximumByteCount: Int
  private let requestTimeout: TimeInterval

  public init(
    transport: any M3UAcquisitionTransport = URLSessionM3UAcquisitionTransport(),
    maximumByteCount: Int = Self.defaultMaximumByteCount,
    requestTimeout: TimeInterval = Self.defaultRequestTimeout
  ) {
    self.transport = transport
    self.maximumByteCount = maximumByteCount
    self.requestTimeout = requestTimeout
  }

  public func acquire(from source: SourceConfiguration) async throws -> Data {
    try Task.checkCancellation()
    guard source.kind == .m3u, source.isEnabled, let endpoint = source.epgConfiguration?.endpoint,
      maximumByteCount > 0, requestTimeout > 0
    else { throw M3UAcquisitionError.invalidSourceConfiguration }
    var request = URLRequest(
      url: endpoint.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout
    )
    request.httpMethod = "GET"
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue("application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
    let (data, response) = try await transport.data(
      for: request, maximumByteCount: maximumByteCount)
    try Task.checkCancellation()
    guard (200..<300).contains(response.statusCode) else {
      throw response.statusCode == 401 || response.statusCode == 403
        ? M3UAcquisitionError.authenticationRejected : .httpError(statusCode: response.statusCode)
    }
    guard !data.isEmpty else { throw M3UAcquisitionError.emptyResponse }
    return data
  }
}
