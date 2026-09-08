import Domain
import Foundation

extension SQLiteCatalogStore {
  public func item(id: String) throws -> CatalogItem? {
    let row = try readDatabase().statement(
      "SELECT id,source,origin,kind,title,category,sealed_references FROM items WHERE id=?", [id])
    guard try row.step() else { return nil }
    return try decodeItem(row)
  }

  public func items(matching filter: CatalogFilter, page: CatalogPage) throws -> [CatalogItem] {
    let predicate = filter.predicate()
    let row = try readDatabase().statement(
      """
      SELECT id,source,origin,kind,title,category,sealed_references FROM items
      \(predicate.sql) ORDER BY search_title COLLATE BINARY,id COLLATE BINARY LIMIT ? OFFSET ?
      """, predicate.values + [String(page.limit), String(page.offset)])
    var items: [CatalogItem] = []
    items.reserveCapacity(page.limit)
    while try row.step() {
      try Task.checkCancellation()
      items.append(try decodeItem(row))
    }
    return items
  }

  public func categories(matching filter: CatalogFilter, page: CatalogPage) throws
    -> [CatalogCategory]
  {
    let predicate = filter.predicate(categoryTable: true)
    let row = try readDatabase().statement(
      """
      SELECT id,source,origin,kind,title FROM categories \(predicate.sql)
      ORDER BY search_title COLLATE BINARY,id COLLATE BINARY LIMIT ? OFFSET ?
      """, predicate.values + [String(page.limit), String(page.offset)])
    var categories: [CatalogCategory] = []
    while try row.step() {
      try Task.checkCancellation()
      guard let id = row.text(0), let title = row.text(4) else {
        throw CatalogStoreError.corruptedStore
      }
      categories.append(CatalogCategory(id: id, scope: try decodeScope(row), title: title))
    }
    return categories
  }

  public func itemCount(matching filter: CatalogFilter) throws -> Int {
    let predicate = filter.predicate()
    return try readDatabase().scalar(
      "SELECT count(*) FROM items \(predicate.sql)", predicate.values)
  }

  public func sourceCatalogCount(sourceID: SourceConfiguration.ID?) throws -> Int {
    if let sourceID {
      return try readDatabase().scalar(
        "SELECT count(*) FROM catalogs WHERE source=?", [sourceID.databaseValue])
    }
    return try readDatabase().scalar("SELECT count(*) FROM catalogs")
  }
}

extension CatalogFilter {
  func predicate(categoryTable: Bool = false) -> (sql: String, values: [String?]) {
    var clauses: [String] = []
    var values: [String?] = []
    if let sourceID {
      clauses.append("source=?")
      values.append(sourceID.databaseValue)
    }
    if let kind {
      clauses.append("kind=?")
      values.append(kind.rawValue)
    }
    if let categoryID {
      clauses.append(categoryTable ? "id=?" : "category=?")
      values.append(categoryID)
    }
    return (clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "), values)
  }
}
