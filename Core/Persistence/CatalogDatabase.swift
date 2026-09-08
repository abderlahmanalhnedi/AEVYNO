import Foundation
import SQLite3

/// Non-Sendable handles stay inside SQLiteCatalogStore's actor. Never expose raw SQL diagnostics.
final class CatalogDatabase {
  private var handle: OpaquePointer?

  init(url: URL, readOnly: Bool = false) throws {
    let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
      sqlite3_close_v2(handle)
      handle = nil
      throw CatalogStoreError.unavailable
    }
    sqlite3_busy_timeout(handle, 0)
    sqlite3_progress_handler(
      handle, 1000, { _ in Task<Never, Never>.isCancelled ? 1 : 0 }, nil)
  }

  deinit { sqlite3_close_v2(handle) }

  func statement(_ sql: String, _ values: [String?] = []) throws -> CatalogStatement {
    var pointer: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
      throw failure()
    }
    let statement = CatalogStatement(pointer: pointer)
    try statement.bind(values)
    return statement
  }

  func execute(_ sql: String, _ values: [String?] = []) throws {
    let statement = try statement(sql, values)
    while try statement.step() {}
  }

  func scalar(_ sql: String, _ values: [String?] = []) throws -> Int {
    let statement = try statement(sql, values)
    guard try statement.step() else { throw CatalogStoreError.corruptedStore }
    return statement.integer(0)
  }

  func rollback() throws {
    // Cleanup must execute even in the cancelled import task.
    sqlite3_progress_handler(handle, 0, nil, nil)
    defer {
      sqlite3_progress_handler(
        handle, 1000, { _ in Task<Never, Never>.isCancelled ? 1 : 0 }, nil)
    }
    if sqlite3_get_autocommit(handle) == 0 { try execute("ROLLBACK") }
  }

  func executeIgnoringCancellation(_ sql: String, _ values: [String?] = []) throws {
    sqlite3_progress_handler(handle, 0, nil, nil)
    defer {
      sqlite3_progress_handler(
        handle, 1000, { _ in Task<Never, Never>.isCancelled ? 1 : 0 }, nil)
    }
    try execute(sql, values)
  }

  private func failure() -> any Error {
    catalogDatabaseError(sqlite3_errcode(handle))
  }
}

final class CatalogStatement {
  private let pointer: OpaquePointer

  init(pointer: OpaquePointer) { self.pointer = pointer }
  deinit { sqlite3_finalize(pointer) }

  func bind(_ values: [String?]) throws {
    sqlite3_reset(pointer)
    sqlite3_clear_bindings(pointer)
    for (index, value) in values.enumerated() {
      let result: Int32
      if let value {
        // Explicit byte count preserves opaque Unicode and avoids truncating embedded NULs.
        result = value.withCString {
          sqlite3_bind_text(
            pointer, Int32(index + 1), $0, Int32(value.utf8.count),
            unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
      } else {
        result = sqlite3_bind_null(pointer, Int32(index + 1))
      }
      guard result == SQLITE_OK else { throw catalogDatabaseError(result) }
    }
  }

  func step() throws -> Bool {
    let result = sqlite3_step(pointer)
    if result == SQLITE_ROW { return true }
    guard result == SQLITE_DONE else { throw catalogDatabaseError(result) }
    return false
  }

  func requireChangedRows(_ expected: Int = 1) throws {
    guard sqlite3_changes(sqlite3_db_handle(pointer)) == expected else {
      throw CatalogStoreError.invalidInput
    }
  }

  func text(_ column: Int32) -> String? {
    guard let bytes = sqlite3_column_text(pointer, column) else { return nil }
    return String(
      decoding: UnsafeBufferPointer(
        start: bytes, count: Int(sqlite3_column_bytes(pointer, column))),
      as: UTF8.self)
  }

  func integer(_ column: Int32) -> Int { Int(sqlite3_column_int64(pointer, column)) }
  func double(_ column: Int32) -> Double { sqlite3_column_double(pointer, column) }
  func isNull(_ column: Int32) -> Bool { sqlite3_column_type(pointer, column) == SQLITE_NULL }
}

private func catalogDatabaseError(_ code: Int32) -> any Error {
  switch code {
  case SQLITE_INTERRUPT: CancellationError()
  case SQLITE_BUSY, SQLITE_LOCKED: CatalogStoreError.busy
  case SQLITE_CORRUPT, SQLITE_NOTADB: CatalogStoreError.corruptedStore
  default: CatalogStoreError.writeFailed
  }
}
