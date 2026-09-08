import Domain
import Foundation
import Testing

@Test("Source configuration preserves stable identity and source kind")
func sourceConfigurationPreservesIdentityAndKind() throws {
  let sourceID = SourceConfiguration.ID(
    rawValue: try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
  )
  let credentialReference = CredentialReference(
    rawValue: try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
  )
  let endpoint = try SourceEndpoint(url: #require(URL(string: "https://example.invalid/api")))
  let source = SourceConfiguration(
    id: sourceID,
    displayName: "Synthetic source",
    kind: .xtreamCompatible,
    endpoint: endpoint,
    credentialReference: credentialReference,
    isEnabled: false
  )

  let decoded = try JSONDecoder().decode(
    SourceConfiguration.self,
    from: JSONEncoder().encode(source)
  )

  #expect(decoded == source)
  #expect(decoded.id == sourceID)
  #expect(decoded.kind == .xtreamCompatible)
  #expect(decoded.credentialReference == credentialReference)
  #expect(!decoded.isEnabled)
}

@Test("Source kinds cover the Phase 2 source formats")
func sourceKindsCoverPhaseTwoFormats() {
  #expect(Set(SourceKind.allCases) == [.xtreamCompatible, .m3u])
}

@Test("Credential references are stable, serializable, and non-secret")
func credentialReferencesRoundTrip() throws {
  let reference = CredentialReference(
    rawValue: try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000003"))
  )

  let data = try JSONEncoder().encode(reference)
  let decoded = try JSONDecoder().decode(CredentialReference.self, from: data)

  #expect(decoded == reference)
  #expect(String(decoding: data, as: UTF8.self).contains(reference.rawValue.uuidString))
}

@Test("Source endpoints accept only non-credential HTTP metadata")
func sourceEndpointsRejectSensitiveComponents() throws {
  let validEndpoint = try SourceEndpoint(
    url: #require(URL(string: "https://example.invalid/provider"))
  )

  #expect(validEndpoint.url.host == "example.invalid")
  #expect(throws: SourceEndpointError.containsSensitiveComponents) {
    try SourceEndpoint(
      url: #require(URL(string: "https://synthetic-user@example.invalid/provider"))
    )
  }
  #expect(throws: SourceEndpointError.containsSensitiveComponents) {
    try SourceEndpoint(
      url: #require(URL(string: "https://example.invalid/provider?token=synthetic-secret"))
    )
  }
  #expect(throws: SourceEndpointError.absoluteHTTPURLRequired) {
    try SourceEndpoint(url: #require(URL(string: "file:///tmp/source.m3u")))
  }
}

@Test("Source serialization cannot contain credential plaintext")
func sourceSerializationContainsOnlyCredentialReference() throws {
  let syntheticUsername = "synthetic-user"
  let syntheticSecret = "synthetic-password-value"
  let source = SourceConfiguration(
    displayName: "Synthetic source",
    kind: .m3u,
    endpoint: try SourceEndpoint(
      url: #require(URL(string: "https://example.invalid/playlist"))
    ),
    credentialReference: CredentialReference()
  )

  let data = try JSONEncoder().encode(source)
  let serialized = String(decoding: data, as: UTF8.self)
  let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

  #expect(!serialized.contains(syntheticUsername))
  #expect(!serialized.contains(syntheticSecret))
  #expect(document["credentialReference"] != nil)
  #expect(document["username"] == nil)
  #expect(document["password"] == nil)
  #expect(document["secret"] == nil)
  #expect(document["token"] == nil)
}

@Test("Source diagnostics omit display names and endpoint values")
func sourceDiagnosticsAreSafeByDefault() throws {
  let displayName = "Private synthetic source"
  let endpointValue = "https://example.invalid/private-path"
  let source = SourceConfiguration(
    displayName: displayName,
    kind: .m3u,
    endpoint: try SourceEndpoint(url: #require(URL(string: endpointValue))),
    credentialReference: CredentialReference()
  )

  #expect(!source.description.contains(displayName))
  #expect(!source.description.contains(endpointValue))
  #expect(source.description.contains("credentialReference: present"))
  #expect(!String(describing: source.endpoint).contains("private-path"))
}
