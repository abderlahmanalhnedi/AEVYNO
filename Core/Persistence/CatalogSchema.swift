import Foundation

/// Version 1 is created atomically. Unknown versions are refused without deleting user data.
enum CatalogSchema {
  static func prepare(_ database: CatalogDatabase) throws {
    let version = try database.scalar("PRAGMA user_version")
    guard version == 0 || version == 1 else { throw CatalogStoreError.unsupportedSchema }
    if version == 1 {
      guard try database.scalar("PRAGMA application_id") == 1_094_014_553 else {
        throw CatalogStoreError.corruptedStore
      }
      return
    }
    // Do not adopt arbitrary existing databases as a new catalog.
    guard
      try database.scalar("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0
    else { throw CatalogStoreError.corruptedStore }
    try database.execute("BEGIN IMMEDIATE")
    do {
      for sql in statements { try database.execute(sql) }
      try database.execute("PRAGMA application_id = 1094014553")
      try database.execute("PRAGMA user_version = 1")
      try database.execute("COMMIT")
    } catch {
      try database.rollback()
      throw error
    }
  }

  private static let statements = [
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
}
