import Foundation

enum CatalogSearchNormalization {
  static func fold(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .precomposedStringWithCanonicalMapping
  }
}
