import AEVYNOSecurity
import Domain
import Foundation
import IPTVCore
import Testing

@Test("Authentication uses a centralized credential-bearing request and returns safe account data")
func xtreamAuthenticationAndRequestConstruction() async throws {
  let transport = XtreamFixtureTransport(
    responses: ["authentication": try xtreamFixture(named: "auth-valid")]
  )
  let adapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: transport,
    requestTimeout: 12
  )

  let snapshot = try await adapter.discover(source: makeXtreamSource())

  #expect(snapshot.status == "Active")
  #expect(snapshot.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
  #expect(snapshot.isTrial == false)
  #expect(snapshot.activeConnections == 2)
  #expect(snapshot.maximumConnections == 4)
  #expect(snapshot.allowedOutputFormats == ["m3u8", "ts"])
  #expect(snapshot.serverTimeZoneIdentifier == "Europe/Berlin")

  let request = try #require(await transport.requests.first)
  let components = try #require(
    request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
  )
  let query = Dictionary(
    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
  #expect(components.path == "/provider/player_api.php")
  #expect(query["username"] == "synthetic-user")
  #expect(query["password"] == "synthetic-secret")
  #expect(query["action"] == nil)
  #expect(request.httpMethod == "GET")
  #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
  #expect(request.timeoutInterval == 12)
  let safeURL = SafeDiagnostics.sanitizedURL(try #require(request.url))
  #expect(safeURL == "https://example.invalid/redacted?redacted")
  #expect(!safeURL.contains("synthetic-user"))
  #expect(!safeURL.contains("synthetic-secret"))
  #expect(!String(describing: snapshot).contains("synthetic-user"))
  #expect(!String(describing: snapshot).contains("synthetic-secret"))
}

@Test("Authentication rejection and HTTP failures are normalized without raw response data")
func xtreamAuthenticationAndHTTPFailuresAreSafe() async throws {
  let rejectedAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(
      responses: ["authentication": try xtreamFixture(named: "auth-rejected")]
    )
  )
  await #expect(throws: ProviderAdapterError.authenticationRejected) {
    try await rejectedAdapter.discover(source: makeXtreamSource())
  }

  let httpAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(responses: [:], statusCode: 503)
  )
  await #expect(throws: ProviderAdapterError.httpError(statusCode: 503)) {
    try await httpAdapter.categories(for: .live, source: makeXtreamSource())
  }

  let rawBody = String(decoding: try xtreamFixture(named: "malformed-response"), as: UTF8.self)
  let malformedAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(
      responses: ["get_live_streams": Data("not-json-synthetic-secret".utf8)]
    )
  )
  await #expect(throws: ProviderAdapterError.malformedResponse) {
    try await malformedAdapter.fetchCatalog(for: .live, source: makeXtreamSource()) { _ in }
  }
  #expect(!ProviderAdapterError.malformedResponse.description.contains(rawBody))
  #expect(!ProviderAdapterError.malformedResponse.description.contains("synthetic-secret"))
  #expect(!ProviderAdapterError.authenticationRejected.description.contains("synthetic-user"))
}

@Test("Live, VOD, and series categories decode typed variations and report invalid identifiers")
func xtreamCategoryDecoding() async throws {
  let transport = XtreamFixtureTransport(
    responses: [
      "get_live_categories": try xtreamFixture(named: "live-categories"),
      "get_vod_categories": try xtreamFixture(named: "vod-categories"),
      "get_series_categories": try xtreamFixture(named: "series-categories"),
    ]
  )
  let adapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: transport
  )
  let source = try makeXtreamSource()

  let live = try await adapter.categories(for: .live, source: source)
  let vod = try await adapter.categories(for: .vod, source: source)
  let series = try await adapter.categories(for: .series, source: source)

  #expect(live.receivedCount == 3)
  #expect(live.categories.map(\.providerID) == ["10", "11"])
  #expect(live.skippedCount == 1)
  #expect(vod.categories.map(\.title) == ["Films", "Documentaries"])
  #expect(series.categories.map(\.providerID) == ["30", "31"])
  #expect(
    Set(await transport.requests.compactMap(requestAction)) == [
      "get_live_categories", "get_vod_categories", "get_series_categories",
    ])
}

@Test("Live, VOD, and series catalogs normalize without retaining provider credentials")
func xtreamCatalogDecoding() async throws {
  let transport = XtreamFixtureTransport(
    responses: [
      "get_live_streams": try xtreamFixture(named: "live-streams"),
      "get_vod_streams": try xtreamFixture(named: "vod-streams"),
      "get_series": try xtreamFixture(named: "series-list"),
    ]
  )
  let adapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: transport
  )
  let source = try makeXtreamSource()

  let liveCollector = ProviderItemCollector()
  let live = try await adapter.fetchCatalog(for: .live, source: source) {
    await liveCollector.append($0)
  }
  let vodCollector = ProviderItemCollector()
  let vod = try await adapter.fetchCatalog(for: .vod, source: source) {
    await vodCollector.append($0)
  }
  let seriesCollector = ProviderItemCollector()
  let series = try await adapter.fetchCatalog(for: .series, source: source) {
    await seriesCollector.append($0)
  }

  let liveItems = await liveCollector.items
  let vodItems = await vodCollector.items
  let seriesItems = await seriesCollector.items
  #expect(live == ProviderCatalogReport(receivedCount: 3, normalizedCount: 2, skippedCount: 1))
  #expect(vod.normalizedCount == 2)
  #expect(series.normalizedCount == 2)
  #expect(liveItems.map(\.providerReference.providerID) == ["1001", "1002"])
  #expect(vodItems.allSatisfy { $0.providerReference.kind == .vod })
  #expect(seriesItems.allSatisfy { $0.providerReference.kind == .series })
  #expect(seriesItems[1].artworkURL?.absoluteString.hasSuffix("series-large.jpg") == true)

  let encoded = String(decoding: try JSONEncoder().encode(liveItems), as: UTF8.self)
  #expect(!encoded.contains("synthetic-user"))
  #expect(!encoded.contains("synthetic-secret"))
  #expect(!liveItems[0].description.contains("example.invalid"))
}

@Test("Provider item identity is deterministic, source scoped, and kind scoped")
func xtreamStableIdentity() throws {
  let source = try makeXtreamSource()
  let otherSource = try makeXtreamSource(
    id: SourceConfiguration.ID(
      rawValue: try #require(UUID(uuidString: "72000000-0000-0000-0000-000000000007"))
    )
  )
  let liveReference = ProviderItemReference(kind: .live, providerID: "1001")
  let vodReference = ProviderItemReference(kind: .vod, providerID: "1001")

  let first = ProviderCatalogItem.ID(sourceID: source.id, reference: liveReference)
  let repeated = ProviderCatalogItem.ID(sourceID: source.id, reference: liveReference)
  let otherSourceID = ProviderCatalogItem.ID(sourceID: otherSource.id, reference: liveReference)
  let otherKindID = ProviderCatalogItem.ID(sourceID: source.id, reference: vodReference)

  #expect(first == repeated)
  #expect(first != otherSourceID)
  #expect(first != otherKindID)
}

@Test("Empty catalogs succeed and malformed top-level responses fail safely")
func xtreamEmptyAndMalformedCatalogs() async throws {
  let emptyAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(
      responses: ["get_vod_streams": try xtreamFixture(named: "empty-catalog")]
    )
  )
  let emptyReport = try await emptyAdapter.fetchCatalog(
    for: .vod,
    source: makeXtreamSource()
  ) { _ in }
  #expect(
    emptyReport == ProviderCatalogReport(receivedCount: 0, normalizedCount: 0, skippedCount: 0))

  let malformedAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(
      responses: ["get_series": try xtreamFixture(named: "malformed-response")]
    )
  )
  await #expect(throws: ProviderAdapterError.malformedResponse) {
    try await malformedAdapter.fetchCatalog(for: .series, source: makeXtreamSource()) { _ in }
  }
}

@Test("Authentication responses missing required state are rejected")
func xtreamInvalidAuthenticationResponse() async throws {
  let adapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(
      responses: ["authentication": try xtreamFixture(named: "malformed-response")]
    )
  )

  await #expect(throws: ProviderAdapterError.providerResponseInvalid) {
    try await adapter.discover(source: makeXtreamSource())
  }
}

@Test("Invalid sources and unavailable credentials fail before network transport")
func xtreamSourceAndCredentialValidation() async throws {
  let transport = XtreamFixtureTransport(responses: [:])
  let unavailableAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(credential: nil, isUnavailable: true),
    transport: transport
  )
  await #expect(throws: ProviderAdapterError.credentialUnavailable) {
    try await unavailableAdapter.discover(source: makeXtreamSource())
  }

  let invalidSource = SourceConfiguration(displayName: "M3U", kind: .m3u)
  await #expect(throws: ProviderAdapterError.invalidSourceConfiguration) {
    try await unavailableAdapter.discover(source: invalidSource)
  }
  #expect(await transport.requests.isEmpty)
}

@Test("Timeout and connectivity failures are distinct normalized errors")
func xtreamTransportErrors() async throws {
  let timedOutAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(responses: [:], behavior: .timeOut)
  )
  await #expect(throws: ProviderAdapterError.timedOut) {
    try await timedOutAdapter.categories(for: .live, source: makeXtreamSource())
  }

  let unavailableAdapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: XtreamFixtureTransport(responses: [:], behavior: .unavailable)
  )
  await #expect(throws: ProviderAdapterError.transportUnavailable) {
    try await unavailableAdapter.categories(for: .live, source: makeXtreamSource())
  }
}

@Test("Task cancellation propagates without becoming a provider failure")
func xtreamCancellationPropagates() async throws {
  let transport = XtreamFixtureTransport(responses: [:], behavior: .suspend)
  let adapter = try XtreamProviderAdapter(
    credentialStore: SyntheticXtreamCredentialStore(),
    transport: transport
  )
  let source = try makeXtreamSource()
  let task = Task {
    try await adapter.fetchCatalog(for: .live, source: source) { _ in }
  }

  await transport.waitUntilRequestStarts()
  task.cancel()

  await #expect(throws: CancellationError.self) {
    try await task.value
  }
}

private func requestAction(_ request: URLRequest) -> String? {
  request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
    .queryItems?.first(where: { $0.name == "action" })?.value
}
