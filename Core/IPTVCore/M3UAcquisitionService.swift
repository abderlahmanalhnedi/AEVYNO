import AEVYNOSecurity
import Domain
import Foundation
import OSLog

public protocol M3UAcquisitionTransport: Sendable {
  func data(for request: URLRequest, maximumByteCount: Int) async throws
    -> (Data, HTTPURLResponse)
}

public enum M3UAcquisitionError: Error, Equatable, Sendable, LocalizedError,
  CustomStringConvertible
{
  case invalidSourceConfiguration
  case authenticationRejected
  case httpError(statusCode: Int)
  case transportUnavailable
  case timedOut
  case emptyResponse
  case responseTooLarge
  case unsafeRedirect

  public var errorDescription: String? {
    switch self {
    case .invalidSourceConfiguration:
      return "The playlist source is not configured correctly."
    case .authenticationRejected:
      return "The playlist server rejected the request."
    case .httpError(let statusCode):
      return "The playlist server returned HTTP status \(statusCode)."
    case .transportUnavailable:
      return "The playlist server is currently unreachable."
    case .timedOut:
      return "The playlist request timed out."
    case .emptyResponse:
      return "The playlist response was empty."
    case .responseTooLarge:
      return "The playlist response exceeded the safe download limit."
    case .unsafeRedirect:
      return "The playlist server returned an unsafe redirect."
    }
  }

  public var description: String { errorDescription ?? "The playlist request failed." }
}

public struct M3UAcquisitionService: Sendable {
  /// 64 MiB supports typical 100k-entry playlists while bounding transient response memory.
  public static let defaultMaximumByteCount = 64 * 1_024 * 1_024
  public static let defaultRequestTimeout: TimeInterval = 30

  private let transport: any M3UAcquisitionTransport
  private let maximumByteCount: Int
  private let requestTimeout: TimeInterval
  private let logger = Logger(subsystem: "com.aevyno", category: "m3u-acquisition")

  public init(
    transport: any M3UAcquisitionTransport = URLSessionM3UAcquisitionTransport(),
    maximumByteCount: Int = M3UAcquisitionService.defaultMaximumByteCount,
    requestTimeout: TimeInterval = M3UAcquisitionService.defaultRequestTimeout
  ) {
    self.transport = transport
    self.maximumByteCount = maximumByteCount
    self.requestTimeout = requestTimeout
  }

  public func acquire(from source: SourceConfiguration) async throws -> Data {
    try Task.checkCancellation()
    guard source.kind == .m3u, source.isEnabled, let endpoint = source.endpoint,
      maximumByteCount > 0, requestTimeout > 0
    else {
      throw M3UAcquisitionError.invalidSourceConfiguration
    }

    var request = URLRequest(
      url: endpoint.url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: requestTimeout
    )
    request.httpMethod = "GET"
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue(
      "application/x-mpegURL, audio/mpegurl, text/plain, */*", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await transport.data(
        for: request, maximumByteCount: maximumByteCount)
      try Task.checkCancellation()
      guard (200..<300).contains(response.statusCode) else {
        if response.statusCode == 401 || response.statusCode == 403 {
          throw M3UAcquisitionError.authenticationRejected
        }
        throw M3UAcquisitionError.httpError(statusCode: response.statusCode)
      }
      guard !data.isEmpty else { throw M3UAcquisitionError.emptyResponse }
      guard data.count <= maximumByteCount else { throw M3UAcquisitionError.responseTooLarge }
      return data
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as M3UAcquisitionError {
      logFailure(error, endpoint: endpoint.url)
      throw error
    } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
      throw CancellationError()
    } catch let error as URLError where error.code == .timedOut {
      logFailure(.timedOut, endpoint: endpoint.url)
      throw M3UAcquisitionError.timedOut
    } catch {
      logFailure(.transportUnavailable, endpoint: endpoint.url)
      throw M3UAcquisitionError.transportUnavailable
    }
  }

  private func logFailure(_ error: M3UAcquisitionError, endpoint: URL) {
    logger.error(
      "M3U acquisition failed category=\(String(describing: error), privacy: .public) endpoint=\(SafeDiagnostics.sanitizedURL(endpoint), privacy: .public)"
    )
  }
}

public struct URLSessionM3UAcquisitionTransport: M3UAcquisitionTransport, @unchecked Sendable {
  private let session: URLSession
  private let redirectDelegate: SafeM3URedirectDelegate?

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    let redirectDelegate = SafeM3URedirectDelegate()
    self.redirectDelegate = redirectDelegate
    session = URLSession(
      configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
  }

  public init(session: URLSession) {
    self.session = session
    redirectDelegate = nil
  }

  public func data(for request: URLRequest, maximumByteCount: Int) async throws
    -> (Data, HTTPURLResponse)
  {
    let (bytes, response) = try await session.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw M3UAcquisitionError.transportUnavailable
    }
    if httpResponse.expectedContentLength > Int64(maximumByteCount) {
      throw M3UAcquisitionError.responseTooLarge
    }

    var data = Data()
    if httpResponse.expectedContentLength > 0 {
      data.reserveCapacity(min(maximumByteCount, Int(httpResponse.expectedContentLength)))
    }
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumByteCount else {
        throw M3UAcquisitionError.responseTooLarge
      }
      data.append(byte)
    }
    return (data, httpResponse)
  }
}

private final class SafeM3URedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let url = request.url, let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", url.host != nil,
      url.user == nil, url.password == nil,
      !(response.url?.scheme?.lowercased() == "https" && scheme == "http")
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}
