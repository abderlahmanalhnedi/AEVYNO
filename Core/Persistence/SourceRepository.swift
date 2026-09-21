import Domain
import Foundation

public enum SourceRepositoryError: Error, Equatable, Sendable {
  case duplicateSource
  case sourceNotFound
  case invalidSource
  case unsupportedSchema
  case corruptedStore
  case unavailable
  case writeFailed
}

public protocol SourceRepository: Sendable {
  func listSources() async throws -> [SourceConfiguration]
  func source(id: SourceConfiguration.ID) async throws -> SourceConfiguration?
  func create(_ source: SourceConfiguration) async throws
  func update(_ source: SourceConfiguration) async throws
  func delete(id: SourceConfiguration.ID) async throws
  func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) async throws
}

/// Durable user-authored source metadata. This store intentionally lives outside the catalog cache.
public actor FileSourceRepository: SourceRepository {
  public static let currentSchemaVersion = 3

  private let fileURL: URL
  private let fileManager: FileManager
  private var loadedSources: [SourceConfiguration]?

  public init(url: URL, fileManager: FileManager = .default) {
    fileURL = url
    self.fileManager = fileManager
  }

  public static func openDefault() throws -> FileSourceRepository {
    do {
      let applicationSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = applicationSupport.appendingPathComponent("AEVYNO", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return FileSourceRepository(url: directory.appendingPathComponent("sources.json"))
    } catch {
      throw SourceRepositoryError.unavailable
    }
  }

  public func listSources() throws -> [SourceConfiguration] {
    try loadIfNeeded()
  }

  public func source(id: SourceConfiguration.ID) throws -> SourceConfiguration? {
    try loadIfNeeded().first { $0.id == id }
  }

  public func create(_ source: SourceConfiguration) throws {
    var sources = try loadIfNeeded()
    try validate(source)
    guard !sources.contains(where: { $0.id == source.id }) else {
      throw SourceRepositoryError.duplicateSource
    }
    sources.append(source)
    try persist(sources)
  }

  public func update(_ source: SourceConfiguration) throws {
    var sources = try loadIfNeeded()
    try validate(source)
    guard let index = sources.firstIndex(where: { $0.id == source.id }) else {
      throw SourceRepositoryError.sourceNotFound
    }
    sources[index] = source
    try persist(sources)
  }

  public func delete(id: SourceConfiguration.ID) throws {
    var sources = try loadIfNeeded()
    guard let index = sources.firstIndex(where: { $0.id == id }) else {
      throw SourceRepositoryError.sourceNotFound
    }
    sources.remove(at: index)
    try persist(sources)
  }

  public func setEnabled(_ isEnabled: Bool, id: SourceConfiguration.ID) throws {
    var sources = try loadIfNeeded()
    guard let index = sources.firstIndex(where: { $0.id == id }) else {
      throw SourceRepositoryError.sourceNotFound
    }
    let existing = sources[index]
    sources[index] = SourceConfiguration(
      id: existing.id,
      displayName: existing.displayName,
      kind: existing.kind,
      endpoint: existing.endpoint,
      credentialReference: existing.credentialReference,
      isEnabled: isEnabled,
      refreshPolicy: existing.refreshPolicy,
      epgConfiguration: existing.epgConfiguration
    )
    try persist(sources)
  }

  private func loadIfNeeded() throws -> [SourceConfiguration] {
    if let loadedSources { return loadedSources }
    guard fileManager.fileExists(atPath: fileURL.path) else {
      loadedSources = []
      return []
    }

    do {
      let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
      let header = try JSONDecoder().decode(SourceRegistryHeader.self, from: data)
      let sources: [SourceConfiguration]
      switch header.schemaVersion {
      case 1:
        let legacy = try JSONDecoder().decode(SourceRegistryV1.self, from: data)
        sources = legacy.sources.map { $0.migratedConfiguration }
      case 2, Self.currentSchemaVersion:
        sources = try JSONDecoder().decode(SourceRegistry.self, from: data).sources
      default:
        throw SourceRepositoryError.unsupportedSchema
      }
      guard Set(sources.map(\.id)).count == sources.count else {
        throw SourceRepositoryError.corruptedStore
      }
      for source in sources { try validate(source) }
      if header.schemaVersion < Self.currentSchemaVersion {
        try persist(sources)
      } else {
        loadedSources = sources
      }
      return sources
    } catch let error as SourceRepositoryError {
      throw error
    } catch {
      throw SourceRepositoryError.corruptedStore
    }
  }

  private func persist(_ sources: [SourceConfiguration]) throws {
    do {
      let parent = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(
        SourceRegistry(schemaVersion: Self.currentSchemaVersion, sources: sources)
      )
      try data.write(to: fileURL, options: [.atomic])
      loadedSources = sources
    } catch {
      throw SourceRepositoryError.writeFailed
    }
  }

  private func validate(_ source: SourceConfiguration) throws {
    guard
      !source.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      source.endpoint != nil,
      (source.kind == .xtreamCompatible) == (source.credentialReference != nil)
    else {
      throw SourceRepositoryError.invalidSource
    }
  }
}

private struct SourceRegistryHeader: Decodable {
  let schemaVersion: Int
}

private struct SourceRegistry: Codable {
  let schemaVersion: Int
  let sources: [SourceConfiguration]
}

private struct SourceRegistryV1: Decodable {
  let schemaVersion: Int
  let sources: [SourceConfigurationV1]
}

private struct SourceConfigurationV1: Decodable {
  let id: SourceConfiguration.ID
  let displayName: String
  let kind: SourceKind
  let endpoint: SourceEndpoint?
  let credentialReference: CredentialReference?
  let isEnabled: Bool

  var migratedConfiguration: SourceConfiguration {
    SourceConfiguration(
      id: id,
      displayName: displayName,
      kind: kind,
      endpoint: endpoint,
      credentialReference: credentialReference,
      isEnabled: isEnabled,
      refreshPolicy: .manualOnly
    )
  }
}
