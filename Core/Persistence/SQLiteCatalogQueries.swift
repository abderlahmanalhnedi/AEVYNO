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
    try filter.validate()
    let predicate = filter.predicate()
    return try readItems(predicate: predicate, page: page)
  }

  public func searchItems(
    matching filter: CatalogFilter, query: CatalogSearchQuery, page: CatalogPage
  ) throws -> [CatalogItem] {
    try filter.validate()
    guard !query.isEmpty else { return try items(matching: filter, page: page) }
    var predicate = filter.predicate()
    let searchClauses = query.terms.map { _ in "instr(search_title,?) > 0" }
    predicate.sql += predicate.sql.isEmpty ? "WHERE " : " AND "
    predicate.sql += searchClauses.joined(separator: " AND ")
    predicate.values += query.terms
    return try readItems(predicate: predicate, page: page)
  }

  private func readItems(
    predicate: (sql: String, values: [String?]), page: CatalogPage
  ) throws -> [CatalogItem] {
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
    try filter.validate()
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

  public func categorySummaries(matching filter: CatalogFilter, page: CatalogPage) throws
    -> [CatalogCategorySummary]
  {
    try filter.validate()
    let predicate = filter.predicate(categoryTable: true, qualifier: "c.")
    let row = try readDatabase().statement(
      """
      SELECT c.id,c.source,c.origin,c.kind,c.title,
        (SELECT count(*) FROM items i WHERE i.category=c.id)
      FROM categories c \(predicate.sql)
      ORDER BY c.search_title COLLATE BINARY,c.id COLLATE BINARY LIMIT ? OFFSET ?
      """, predicate.values + [String(page.limit), String(page.offset)])
    var summaries: [CatalogCategorySummary] = []
    summaries.reserveCapacity(page.limit)
    while try row.step() {
      try Task.checkCancellation()
      guard let id = row.text(0), let title = row.text(4) else {
        throw CatalogStoreError.corruptedStore
      }
      let category = CatalogCategory(id: id, scope: try decodeScope(row), title: title)
      summaries.append(CatalogCategorySummary(category: category, itemCount: row.integer(5)))
    }
    return summaries
  }

  public func itemCount(matching filter: CatalogFilter) throws -> Int {
    try filter.validate()
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
  func validate() throws {
    if let categoryID,
      categoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || categoryID.contains("\0")
        || categoryID.utf8.count > 16_384
    {
      throw CatalogStoreError.invalidInput
    }
    if let origin, let kind {
      guard (origin == .m3u) == (kind == .unspecified) else {
        throw CatalogStoreError.invalidInput
      }
    }
  }

  func predicate(
    categoryTable: Bool = false, qualifier: String = ""
  ) -> (sql: String, values: [String?]) {
    var clauses: [String] = []
    var values: [String?] = []
    if let sourceID {
      clauses.append("\(qualifier)source=?")
      values.append(sourceID.databaseValue)
    }
    if let origin {
      clauses.append("\(qualifier)origin=?")
      values.append(origin.rawValue)
    }
    if let kind {
      clauses.append("\(qualifier)kind=?")
      values.append(kind.rawValue)
    }
    if let categoryID {
      clauses.append(categoryTable ? "\(qualifier)id=?" : "\(qualifier)category=?")
      values.append(categoryID)
    }
    return (clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "), values)
  }
}
