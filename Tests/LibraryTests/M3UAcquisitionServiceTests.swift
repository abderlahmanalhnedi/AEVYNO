import Domain
import Foundation
import IPTVCore
import Testing

@Suite("Bounded M3U acquisition")
struct M3UAcquisitionServiceTests {
  @Test("2xx responses are returned with explicit cache, timeout, and size policy")
  func success() async throws {
    let body = Data("#EXTM3U\nhttps://example.invalid/live/1.m3u8\n".utf8)
    let transport = SyntheticM3UTransport(behavior: .response(status: 200, data: body))
    let source = try m3uSource()
    let service = M3UAcquisitionService(
      transport: transport, maximumByteCount: 1_024, requestTimeout: 7)

    #expect(try await service.acquire(from: source) == body)
    let request = try #require(await transport.requests.first)
    #expect(request.url == source.endpoint?.url)
    #expect(request.timeoutInterval == 7)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    #expect(await transport.maximumByteCounts == [1_024])
  }

  @Test(
    "HTTP failures are typed and never contain the response body", arguments: [401, 403, 404, 500])
  func httpFailures(statusCode: Int) async throws {
    let marker = "synthetic-secret-body"
    let service = M3UAcquisitionService(
      transport: SyntheticM3UTransport(
        behavior: .response(status: statusCode, data: Data(marker.utf8))))
    do {
      _ = try await service.acquire(from: m3uSource())
      Issue.record("Expected HTTP acquisition failure")
    } catch let error as M3UAcquisitionError {
      if statusCode == 401 || statusCode == 403 {
        #expect(error == .authenticationRejected)
      } else {
        #expect(error == .httpError(statusCode: statusCode))
      }
      #expect(!error.description.contains(marker))
    }
  }

  @Test("Network and timeout failures stay distinct")
  func transportFailures() async throws {
    await #expect(throws: M3UAcquisitionError.transportUnavailable) {
      try await M3UAcquisitionService(
        transport: SyntheticM3UTransport(behavior: .failure(URLError(.cannotConnectToHost)))
      ).acquire(from: m3uSource())
    }
    await #expect(throws: M3UAcquisitionError.timedOut) {
      try await M3UAcquisitionService(
        transport: SyntheticM3UTransport(behavior: .failure(URLError(.timedOut)))
      ).acquire(from: m3uSource())
    }
  }

  @Test("Empty and oversized responses fail safely even when transport metadata is wrong")
  func responseBounds() async throws {
    await #expect(throws: M3UAcquisitionError.emptyResponse) {
      try await M3UAcquisitionService(
        transport: SyntheticM3UTransport(behavior: .response(status: 200, data: Data()))
      ).acquire(from: m3uSource())
    }
    await #expect(throws: M3UAcquisitionError.responseTooLarge) {
      try await M3UAcquisitionService(
        transport: SyntheticM3UTransport(
          behavior: .response(status: 200, data: Data(repeating: 0x41, count: 17))),
        maximumByteCount: 16
      ).acquire(from: m3uSource())
    }
  }

  @Test("Production transport stops a body that exceeds a lying Content-Length")
  func productionTransportStreamingBound() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BoundedBodyURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let transport = URLSessionM3UAcquisitionTransport(session: session)
    let url = try #require(URL(string: "https://example.invalid/oversized.m3u"))
    let request = URLRequest(url: url)

    await #expect(throws: M3UAcquisitionError.responseTooLarge) {
      try await transport.data(for: request, maximumByteCount: 16)
    }
    session.invalidateAndCancel()
  }

  @Test("Disabled and wrong-kind sources perform no network work")
  func invalidSources() async throws {
    let transport = SyntheticM3UTransport(behavior: .response(status: 200, data: Data("x".utf8)))
    let disabled = try m3uSource(isEnabled: false)
    await #expect(throws: M3UAcquisitionError.invalidSourceConfiguration) {
      try await M3UAcquisitionService(transport: transport).acquire(from: disabled)
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test("Cancellation propagates without becoming a network error")
  func cancellation() async throws {
    let transport = SyntheticM3UTransport(behavior: .suspend)
    let task = Task {
      try await M3UAcquisitionService(transport: transport).acquire(from: m3uSource())
    }
    await transport.waitUntilRequestStarts()
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}

private final class BoundedBodyURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Length": "1"])
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(repeating: 0x41, count: 17))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

func m3uSource(
  id: SourceConfiguration.ID = SourceConfiguration.ID(),
  endpoint: String = "https://example.invalid/list.m3u",
  isEnabled: Bool = true
) throws -> SourceConfiguration {
  SourceConfiguration(
    id: id,
    displayName: "Synthetic M3U source",
    kind: .m3u,
    endpoint: try SourceEndpoint(url: #require(URL(string: endpoint))),
    isEnabled: isEnabled
  )
}

actor SyntheticM3UTransport: M3UAcquisitionTransport {
  enum Behavior: @unchecked Sendable {
    case response(status: Int, data: Data)
    case failure(any Error)
    case suspend
  }

  let behavior: Behavior
  private(set) var requests: [URLRequest] = []
  private(set) var maximumByteCounts: [Int] = []

  init(behavior: Behavior) { self.behavior = behavior }

  func data(for request: URLRequest, maximumByteCount: Int) async throws
    -> (Data, HTTPURLResponse)
  {
    requests.append(request)
    maximumByteCounts.append(maximumByteCount)
    switch behavior {
    case .response(let status, let data):
      let url = try #require(request.url)
      let response = try #require(
        HTTPURLResponse(
          url: url, statusCode: status, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/x-mpegURL"])
      )
      return (data, response)
    case .failure(let error):
      throw error
    case .suspend:
      try await Task.sleep(for: .seconds(30))
      throw CancellationError()
    }
  }

  func waitUntilRequestStarts() async {
    while requests.isEmpty { await Task.yield() }
  }
}
