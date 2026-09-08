import Foundation

/// Version 3 adds multi-partition staging and local refresh metadata.
enum CatalogSchema {
  static func prepare(_ database: CatalogDatabase) throws {
    let version = try database.scalar("PRAGMA user_version")
    guard (0...3).contains(version) else { throw CatalogStoreError.unsupportedSchema }
    if version > 0 {
      guard try database.scalar("PRAGMA application_id") == 1_094_014_553 else {
        throw CatalogStoreError.corruptedStore
      }
      if version == 3 { return }
      if version == 1 { try migrateVersion1(database) }
      try migrateVersion2(database)
      return
    }
    // Do not adopt arbitrary existing databases as a new catalog.
    guard
      try database.scalar("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0
    else { throw CatalogStoreError.corruptedStore }
    try database.execute("BEGIN IMMEDIATE")
    do {
      for sql in liveStatements + stagingStatements + metadataStatements {
        try database.execute(sql)
      }
      try database.execute("PRAGMA application_id = 1094014553")
      try database.execute("PRAGMA user_version = 3")
      try database.execute("COMMIT")
    } catch {
      try database.rollback()
      throw error
    }
  }

  private static func migrateVersion1(_ database: CatalogDatabase) throws {
    try database.execute("BEGIN IMMEDIATE")
    do {
      for sql in stagingStatements { try database.execute(sql) }
      try database.execute("PRAGMA user_version = 2")
      try database.execute("COMMIT")
    } catch {
      try database.rollback()
      throw error
    }
  }

  private static func migrateVersion2(_ database: CatalogDatabase) throws {
    try database.execute("BEGIN IMMEDIATE")
    do {
      // Version 2 staging is disposable and query-invisible, so it is safe to rebuild in place.
      try database.execute("DROP TABLE staged_items")
      try database.execute("DROP TABLE staged_categories")
      try database.execute("DROP TABLE staged_catalogs")
      for sql in stagingStatements + metadataStatements { try database.execute(sql) }
      try database.execute("PRAGMA user_version = 3")
      try database.execute("COMMIT")
    } catch {
      try database.rollback()
      throw error
    }
  }

  private static let liveStatements = [
    """
    CREATE TABLE catalogs (
      source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
      PRIMARY KEY(source, origin, kind)) WITHOUT ROWID
    """,
    """
    CREATE TABLE categories (
      id TEXT PRIMARY KEY, source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
      title TEXT NOT NULL CHECK(length(title)>0), search_title TEXT NOT NULL,
      UNIQUE(id, source, origin, kind),
      FOREIGN KEY(source, origin, kind) REFERENCES catalogs ON DELETE CASCADE)
    """,
    """
    CREATE TABLE items (
      id TEXT PRIMARY KEY, source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
      title TEXT NOT NULL CHECK(length(title)>0), search_title TEXT NOT NULL,
      category TEXT, sealed_references TEXT NOT NULL,
      FOREIGN KEY(source, origin, kind) REFERENCES catalogs ON DELETE CASCADE,
      FOREIGN KEY(category, source, origin, kind) REFERENCES categories(id, source, origin, kind)
        DEFERRABLE INITIALLY DEFERRED)
    """,
    "CREATE INDEX items_title ON items(search_title, id)",
    "CREATE INDEX items_source ON items(source, search_title, id)",
    "CREATE INDEX items_kind ON items(kind, search_title, id)",
    "CREATE INDEX items_source_kind ON items(source, kind, search_title, id)",
    "CREATE INDEX items_category ON items(category, search_title, id)",
    "CREATE INDEX categories_source_kind ON categories(source, kind, search_title, id)",
    "CREATE INDEX categories_title ON categories(search_title, id)",
    "CREATE INDEX categories_kind ON categories(kind, search_title, id)",
  ]

  private static let stagingStatements = [
    """
    CREATE TABLE staged_catalogs (
      staging_id TEXT NOT NULL, source TEXT NOT NULL, origin TEXT NOT NULL, kind TEXT NOT NULL,
      PRIMARY KEY(staging_id, source, origin, kind)) WITHOUT ROWID
    """,
    """
    CREATE TABLE staged_categories (
      sequence INTEGER PRIMARY KEY, staging_id TEXT NOT NULL, id TEXT NOT NULL,
      source TEXT NOT NULL, origin TEXT NOT NULL,
      kind TEXT NOT NULL, title TEXT NOT NULL CHECK(length(title)>0), search_title TEXT NOT NULL,
      UNIQUE(staging_id, id),
      FOREIGN KEY(staging_id, source, origin, kind)
        REFERENCES staged_catalogs(staging_id, source, origin, kind) ON DELETE CASCADE)
    """,
    """
    CREATE TABLE staged_items (
      sequence INTEGER PRIMARY KEY, staging_id TEXT NOT NULL, id TEXT NOT NULL,
      source TEXT NOT NULL, origin TEXT NOT NULL,
      kind TEXT NOT NULL, title TEXT NOT NULL CHECK(length(title)>0), search_title TEXT NOT NULL,
      category TEXT, sealed_references TEXT NOT NULL,
      UNIQUE(staging_id, id),
      FOREIGN KEY(staging_id, source, origin, kind)
        REFERENCES staged_catalogs(staging_id, source, origin, kind) ON DELETE CASCADE)
    """,
    "CREATE INDEX staged_categories_order ON staged_categories(staging_id, sequence)",
    "CREATE INDEX staged_items_order ON staged_items(staging_id, sequence)",
  ]

  private static let metadataStatements = [
    """
    CREATE TABLE IF NOT EXISTS refresh_metadata (
      source TEXT PRIMARY KEY,
      last_attempt REAL NOT NULL,
      last_success REAL,
      committed_item_count INTEGER NOT NULL CHECK(committed_item_count >= 0),
      last_result TEXT NOT NULL)
    """
  ]
}
