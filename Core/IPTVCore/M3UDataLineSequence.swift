import Foundation

public struct M3UDataLineSequence: AsyncSequence, Sendable {
  public typealias Element = String

  private let data: Data

  public init(data: Data) {
    self.data = data
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(data: data)
  }

  public struct Iterator: AsyncIteratorProtocol {
    private let data: Data
    private var position: Data.Index
    private var lineNumber = 0

    fileprivate init(data: Data) {
      self.data = data
      self.position = data.startIndex
    }

    public mutating func next() async throws -> String? {
      guard position < data.endIndex else {
        return nil
      }

      try Task.checkCancellation()
      let lineStart = position
      var scannedByteCount = 0

      while position < data.endIndex, data[position] != 0x0A {
        data.formIndex(after: &position)
        scannedByteCount += 1
        if scannedByteCount.isMultiple(of: 4_096) {
          try Task.checkCancellation()
        }
      }

      var lineEnd = position
      if lineEnd > lineStart {
        let previousIndex = data.index(before: lineEnd)
        if data[previousIndex] == 0x0D {
          lineEnd = previousIndex
        }
      }

      if position < data.endIndex {
        data.formIndex(after: &position)
      }

      lineNumber += 1
      guard let line = String(data: data[lineStart..<lineEnd], encoding: .utf8) else {
        throw M3UParserError.invalidUTF8(line: lineNumber)
      }
      return line
    }
  }
}
