import AEVYNOSecurity
import Domain
import Foundation
import IPTVCore
import Testing

func xtreamFixture(named name: String) throws -> Data {
  let resourceURL =
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Xtream")
    ?? Bundle.module.url(forResource: name, withExtension: "json")
  return try Data(contentsOf: #require(resourceURL))
}

func makeXtreamSource(
  id: SourceConfiguration.ID? = nil,
  endpoint: String = "https://example.invalid/provider"
) throws -> SourceConfiguration {
  let resolvedID =
    try id
    ?? SourceConfiguration.ID(
      rawValue: try #require(UUID(uuidString: "70000000-0000-0000-0000-000000000007"))
    )
  return SourceConfiguration(
    id: resolvedID,
    displayName: "Synthetic Xtream source",
    kind: .xtreamCompatible,
    endpoint: try SourceEndpoint(url: #require(URL(string: endpoint))),
    credentialReference: CredentialReference(
      rawValue: try #require(UUID(uuidString: "71000000-0000-0000-0000-000000000007"))
    )
  )
}

actor SyntheticXtreamCredentialStore: CredentialStore {
  private let storedCredential: SourceCredential?
  private let isUnavailable: Bool

  init(credential: SourceCredential? = nil, isUnavailable: Bool = false) throws {
    storedCredential =
      try credential
      ?? SourceCredential(
        username: "synthetic-user",
        secret: "synthetic-secret",
        secretKind: .password
      )
    self.isUnavailable = isUnavailable
  }

  func store(_ credential: SourceCredential, for reference: CredentialReference) throws {}

  func credential(for reference: CredentialReference) throws -> SourceCredential? {
    if isUnavailable {
      throw CredentialStoreError.unavailable
    }
    return storedCredential
  }

  func update(_ credential: SourceCredential, for reference: CredentialReference) throws {}

  func deleteCredential(for reference: CredentialReference) throws {}
}

actor XtreamFixtureTransport: ProviderHTTPTransport {
  enum Behavior: Sendable {
    case respond
    case timeOut
    case unavailable
    case suspend
  }

  private let responses: [String: Data]
  private let statusCode: Int
  private let behavior: Behavior
  private(set) var requests: [URLRequest] = []

  init(
    responses: [String: Data],
    statusCode: Int = 200,
    behavior: Behavior = .respond
  ) {
    self.responses = responses
    self.statusCode = statusCode
    self.behavior = behavior
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    switch behavior {
    case .respond:
      break
    case .timeOut:
      throw URLError(.timedOut)
    case .unavailable:
      throw URLError(.cannotConnectToHost)
    case .suspend:
      try await Task.sleep(for: .seconds(30))
    }

    let action =
      request.url.flatMap { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first(where: { $0.name == "action" })?.value
      } ?? "authentication"
    let data = responses[action] ?? Data("[]".utf8)
    guard
      let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      throw SyntheticXtreamTestError.invalidResponse
    }
    return (data, response)
  }

  func waitUntilRequestStarts() async {
    while requests.isEmpty {
      await Task.yield()
    }
  }
}

actor ProviderItemCollector {
  private(set) var items: [ProviderCatalogItem] = []

  func append(_ item: ProviderCatalogItem) {
    items.append(item)
  }
}

enum SyntheticXtreamTestError: Error {
  case invalidResponse
  case importFailure
}
