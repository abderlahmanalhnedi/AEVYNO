import Foundation
import Testing

@Test("Every catalog entry contains all supported localizations")
func completeLocalizationCatalog() throws {
  let catalog = try localizationCatalog()

  for key in catalog.keys.sorted() {
    try assertCompleteTranslations(for: key, in: catalog)
  }
}

@Test("Critical app strings contain English, German, and Arabic translations")
func criticalLocalizationCoverage() throws {
  let catalog = try localizationCatalog()
  let criticalKeys = [
    "action.retry",
    "detail.action.play_preview",
    "detail.action.save",
    "detail.preview_notice.message",
    "detail.preview_notice.title",
    "home.empty.message",
    "home.empty.title",
    "home.error.message",
    "home.error.title",
    "home.loading.accessibility_label",
    "home.section.continue_watching",
    "home.section.favorites",
    "home.section.live_tv",
    "home.section.movies",
    "home.section.series",
    "sources.accessibility.password_hint",
    "sources.action.add",
    "sources.action.delete",
    "sources.action.refresh",
    "sources.action.save",
    "sources.action.test_connection",
    "sources.delete.confirmation.message",
    "sources.delete.confirmation.title",
    "sources.error.authentication",
    "sources.error.malformed",
    "sources.error.timeout",
    "sources.error.unreachable",
    "sources.field.password",
    "sources.field.server",
    "sources.field.username",
    "sources.m3u.query_limitation",
    "sources.title",
  ]

  for key in criticalKeys {
    try assertCompleteTranslations(for: key, in: catalog)
  }
}

@Test("Synthetic preview presentation has no untranslated catalog entries")
func syntheticPreviewLocalizationCoverage() throws {
  let catalog = try localizationCatalog()
  let previewIDs = [
    "continue-cinder",
    "continue-harbor",
    "continue-orbit",
    "favorite-afterglow",
    "favorite-compass",
    "favorite-relay",
    "live-current",
    "live-field",
    "live-horizon",
    "movie-lagoon",
    "movie-meadow",
    "movie-solar",
    "movie-vector",
    "series-aurora",
    "series-ember",
    "series-midnight",
  ]

  for previewID in previewIDs {
    for field in ["title", "subtitle", "summary"] {
      try assertCompleteTranslations(
        for: "preview.media.\(previewID).\(field)",
        in: catalog
      )
    }
  }
}

private func localizationCatalog() throws -> [String: Any] {
  let testFile = URL(fileURLWithPath: #filePath)
  let catalogURL =
    testFile
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "App/Shared/Localizable.xcstrings")
  let data = try Data(contentsOf: catalogURL)
  let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  return try #require(document["strings"] as? [String: Any])
}

private func assertCompleteTranslations(for key: String, in catalog: [String: Any]) throws {
  let entry = try #require(catalog[key] as? [String: Any], "Missing localization key: \(key)")
  let localizations = try #require(
    entry["localizations"] as? [String: Any],
    "Missing localizations for: \(key)"
  )

  for locale in ["en", "de", "ar"] {
    let localization = try #require(
      localizations[locale] as? [String: Any],
      "Missing \(locale) localization for: \(key)"
    )
    let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
    let value = try #require(stringUnit["value"] as? String)
    #expect(stringUnit["state"] as? String == "translated")
    #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(value != key)
  }
}
