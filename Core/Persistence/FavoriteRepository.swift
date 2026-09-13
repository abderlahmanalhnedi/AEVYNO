import Domain
import Foundation

public enum FavoriteRepositoryError: Error, Equatable, Sendable {
  case unavailable
  case corruptedStore
  case unsupportedSchema
  case writeFailed
}

/// Small, versioned durable store intentionally separate from rebuildable catalog SQLite data.
public actor FileFavoriteRepository: FavoriteRepository {
  private struct Snapshot: Codable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let favorites: [Favorite]
  }

  private let fileURL: URL
  private let fileManager: FileManager

  public init(url: URL, fileManager: FileManager = .default) {
    self.fileURL = url
    self.fileManager = fileManager
  }

  public static func openDefault() throws -> FileFavoriteRepository {
    do {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let directory = support.appendingPathComponent("AEVYNO", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return FileFavoriteRepository(url: directory.appendingPathComponent("favorites.json"))
    } catch { throw FavoriteRepositoryError.unavailable }
  }

  public func favorite(for mediaID: String) throws -> Favorite? {
    try load().favorites.first { $0.mediaID == mediaID }
  }

  public func allFavorites() throws -> [Favorite] { try load().favorites }

  public func add(_ favorite: Favorite) throws {
    try validate(favorite)
    var values = try load().favorites
    values.removeAll { $0.mediaID == favorite.mediaID }
    values.append(favorite)
    try save(values)
  }

  public func remove(mediaID: String) throws {
    var values = try load().favorites
    values.removeAll { $0.mediaID == mediaID }
    try save(values)
  }

  private func load() throws -> Snapshot {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return Snapshot(schemaVersion: Snapshot.schemaVersion, favorites: [])
    }
    do {
      let snapshot = try JSONDecoder().decode(
        Snapshot.self, from: Data(contentsOf: fileURL, options: .mappedIfSafe))
      guard snapshot.schemaVersion == Snapshot.schemaVersion else {
        throw FavoriteRepositoryError.unsupportedSchema
      }
      guard Set(snapshot.favorites.map(\.mediaID)).count == snapshot.favorites.count else {
        throw FavoriteRepositoryError.corruptedStore
      }
      try snapshot.favorites.forEach(validate)
      return Snapshot(
        schemaVersion: snapshot.schemaVersion,
        favorites: snapshot.favorites.sorted { $0.mediaID < $1.mediaID })
    } catch let error as FavoriteRepositoryError {
      throw error
    } catch { throw FavoriteRepositoryError.corruptedStore }
  }

  private func save(_ favorites: [Favorite]) throws {
    do {
      try favorites.forEach(validate)
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder.sorted.encode(
        Snapshot(
          schemaVersion: Snapshot.schemaVersion,
          favorites: favorites.sorted { $0.mediaID < $1.mediaID }))
      try data.write(to: fileURL, options: .atomic)
    } catch let error as FavoriteRepositoryError {
      throw error
    } catch { throw FavoriteRepositoryError.writeFailed }
  }

  private func validate(_ favorite: Favorite) throws {
    guard !favorite.mediaID.isEmpty, favorite.mediaID.utf8.count <= 4_096,
      !favorite.mediaID.contains("\0")
    else {
      throw FavoriteRepositoryError.corruptedStore
    }
  }
}

extension JSONEncoder {
  fileprivate static var sorted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}
