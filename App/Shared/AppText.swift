import Domain
import Foundation

enum AppText {
  static let appName = localized("app.name", defaultValue: "AEVYNO")

  static let homeHeroTitle = localized(
    "home.hero.title",
    defaultValue: "Your media,\nbeautifully in focus."
  )
  static let homeHeroSubtitle = localized(
    "home.hero.subtitle",
    defaultValue: "A calm, synthetic preview of the browsing experience."
  )
  static let mobileHomeSubtitle = localized(
    "home.mobile.subtitle",
    defaultValue: "Your shared media foundation, shaped for touch."
  )
  static let homeLoadingAccessibilityLabel = localized(
    "home.loading.accessibility_label",
    defaultValue: "Loading Home preview"
  )
  static let homeEmptyTitle = localized(
    "home.empty.title",
    defaultValue: "Your screen is ready"
  )
  static let homeEmptyMessage = localized(
    "home.empty.message",
    defaultValue: "There is no preview content in this synthetic collection yet."
  )
  static let mobileHomeEmptyTitle = localized(
    "home.mobile.empty.title",
    defaultValue: "Nothing here yet"
  )
  static let mobileHomeEmptyMessage = localized(
    "home.mobile.empty.message",
    defaultValue: "Source setup will arrive in a later phase."
  )
  static let homeErrorTitle = localized(
    "home.error.title",
    defaultValue: "Home is unavailable"
  )
  static let homeErrorMessage = localized(
    "home.error.message",
    defaultValue: "Please try loading the preview again."
  )
  static let retry = localized("action.retry", defaultValue: "Retry")
  static let retryAccessibilityHint = localized(
    "action.retry.accessibility_hint",
    defaultValue: "Attempts to load Home again"
  )
  static let openDetailsAccessibilityHint = localized(
    "home.card.open_details.accessibility_hint",
    defaultValue: "Opens details"
  )
  static let live = localized("media.live", defaultValue: "Live")
  static let liveBadge = localized("media.live.badge", defaultValue: "LIVE")

  static let detailPlayPreview = localized(
    "detail.action.play_preview",
    defaultValue: "Play Preview"
  )
  static let detailPlayAccessibilityHint = localized(
    "detail.action.play_preview.accessibility_hint",
    defaultValue: "Shows a message; playback is not included in this preview"
  )
  static let detailSave = localized("detail.action.save", defaultValue: "Save for Demo")
  static let detailSaved = localized("detail.action.saved", defaultValue: "Saved for Demo")
  static let detailSavedAccessibilityValue = localized(
    "detail.action.saved.accessibility_value",
    defaultValue: "Saved"
  )
  static let detailNotSavedAccessibilityValue = localized(
    "detail.action.not_saved.accessibility_value",
    defaultValue: "Not saved"
  )
  static let detailSaveAccessibilityHint = localized(
    "detail.action.save.accessibility_hint",
    defaultValue: "Changes only this temporary synthetic preview"
  )
  static let detailPreviewNoticeTitle = localized(
    "detail.preview_notice.title",
    defaultValue: "Playback comes later"
  )
  static let detailPreviewNoticeMessage = localized(
    "detail.preview_notice.message",
    defaultValue: "This Phase 1 action is a safe interface preview and does not start playback."
  )
  static let done = localized("action.done", defaultValue: "Done")

  static let homeHeroAccessibilityLabel = localized(
    "home.hero.accessibility_label",
    defaultValue: "AEVYNO. Your media, beautifully in focus. A synthetic browsing preview."
  )

  static func sectionTitle(for kind: HomeSectionKind, fallback: String) -> String {
    let key: String
    switch kind {
    case .continueWatching: key = "home.section.continue_watching"
    case .movies: key = "home.section.movies"
    case .series: key = "home.section.series"
    case .liveTV: key = "home.section.live_tv"
    case .favorites: key = "home.section.favorites"
    }
    return localized(key, defaultValue: fallback)
  }

  static func itemCount(_ count: Int) -> String {
    String.localizedStringWithFormat(
      localized("home.section.item_count", defaultValue: "Items: %lld"),
      count
    )
  }

  static func detailEyebrow(for kind: MediaKind) -> String {
    switch kind {
    case .movie:
      return localized("detail.eyebrow.movie", defaultValue: "AEVYNO FILM")
    case .series:
      return localized("detail.eyebrow.series", defaultValue: "AEVYNO SERIES")
    case .liveChannel:
      return localized("detail.eyebrow.live", defaultValue: "AEVYNO LIVE")
    }
  }

  static func progressAccessibilityValue(_ progress: Double) -> String {
    String.localizedStringWithFormat(
      localized(
        "media.progress.accessibility_value",
        defaultValue: "%lld percent complete"
      ),
      Int(progress * 100)
    )
  }

  static func mediaPresentation(for item: MediaItem) -> MediaPresentation {
    guard localizedPreviewIDs.contains(item.id.rawValue) else {
      return MediaPresentation(
        title: item.title,
        subtitle: item.subtitle,
        facts: item.facts,
        summary: item.summary
      )
    }

    let keyPrefix = "preview.media.\(item.id.rawValue)"
    return MediaPresentation(
      title: localized("\(keyPrefix).title", defaultValue: item.title),
      subtitle: localized("\(keyPrefix).subtitle", defaultValue: item.subtitle),
      facts: item.facts.map(localizedPreviewFact),
      summary: localized("\(keyPrefix).summary", defaultValue: item.summary)
    )
  }

  private static let localizedPreviewIDs: Set<String> = [
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

  private static func localizedPreviewFact(_ fact: String) -> String {
    let key: String
    switch fact {
    case "Series": key = "preview.fact.series"
    case "Film": key = "preview.fact.film"
    case "51 min": key = "preview.fact.51_minutes"
    case "1 hr 44 min": key = "preview.fact.1_hour_44_minutes"
    case "48 min": key = "preview.fact.48_minutes"
    case "PG": key = "preview.fact.pg"
    case "1 hr 58 min": key = "preview.fact.1_hour_58_minutes"
    case "1 hr 39 min": key = "preview.fact.1_hour_39_minutes"
    case "G": key = "preview.fact.g"
    case "1 hr 22 min": key = "preview.fact.1_hour_22_minutes"
    case "1 hr 47 min": key = "preview.fact.1_hour_47_minutes"
    case "8 episodes": key = "preview.fact.8_episodes"
    case "Drama": key = "preview.fact.drama"
    case "10 episodes": key = "preview.fact.10_episodes"
    case "Mystery": key = "preview.fact.mystery"
    case "6 episodes": key = "preview.fact.6_episodes"
    case "Documentary": key = "preview.fact.documentary"
    case "Live": key = "preview.fact.live"
    case "Arts": key = "preview.fact.arts"
    case "All ages": key = "preview.fact.all_ages"
    case "Culture": key = "preview.fact.culture"
    case "Design": key = "preview.fact.design"
    case "Adventure": key = "preview.fact.adventure"
    case "Studio": key = "preview.fact.studio"
    default: return fact
    }
    return localized(key, defaultValue: fact)
  }

  private static func localized(_ key: String, defaultValue: String) -> String {
    NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: .main,
      value: defaultValue,
      comment: ""
    )
  }
}

struct MediaPresentation {
  let title: String
  let subtitle: String
  let facts: [String]
  let summary: String
}
