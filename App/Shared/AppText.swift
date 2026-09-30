import Domain
import Foundation
import Library
import Playback

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
  static func nowProgramme(_ title: String) -> String {
    String.localizedStringWithFormat(localized("epg.now", defaultValue: "Now: %@"), title)
  }
  static func nextProgramme(_ title: String) -> String {
    String.localizedStringWithFormat(localized("epg.next", defaultValue: "Next: %@"), title)
  }
  static let guide = localized("epg.guide.title", defaultValue: "Guide")
  static let guideEmptyTitle = localized("epg.guide.empty.title", defaultValue: "No guide data yet")
  static let guideEmptyMessage = localized(
    "epg.guide.empty.message", defaultValue: "Refresh a mapped M3U source to load its schedule.")
  static let guideUnavailable = localized(
    "epg.guide.unavailable", defaultValue: "Guide is unavailable")
  static let guideNotConfiguredTitle = localized(
    "epg.guide.not_configured.title", defaultValue: "Guide not configured")
  static let guideNotConfiguredMessage = localized(
    "epg.guide.not_configured.message",
    defaultValue: "No guide source is configured for this source.")
  static let guideNotAvailableYetMessage = localized(
    "epg.guide.not_available_yet.message", defaultValue: "Guide data is not available yet.")
  static let guideExpiredMessage = localized(
    "epg.guide.expired.message", defaultValue: "The available guide schedule has expired.")
  static let guideLoadMore = localized("epg.guide.load_more", defaultValue: "More channels")
  static let guideNow = localized("epg.guide.now", defaultValue: "Now")
  static func guideTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }
  static func guideProgrammeAccessibility(_ title: String, channel: String, start: Date, end: Date)
    -> String
  {
    "\(title), \(channel), \(guideTime(start))–\(guideTime(end))"
  }

  static func epgStatus(_ health: EPGHealth, at now: Date = Date()) -> [String] {
    guard health.configured else {
      return [localized("epg.status.not_configured", defaultValue: "Guide not configured")]
    }
    guard let lastSuccessfulAt = health.lastSuccessfulAt else {
      if health.lastResult == .failure {
        return [localized("epg.status.refresh_failed", defaultValue: "Latest guide refresh failed")]
      }
      return [localized("epg.status.not_updated", defaultValue: "Guide not updated yet")]
    }
    var status = [
      String.localizedStringWithFormat(
        localized("epg.status.updated", defaultValue: "Updated %@"), guideDate(lastSuccessfulAt)),
      String.localizedStringWithFormat(
        localized("epg.status.programme_count", defaultValue: "%ld programmes"),
        health.lastCommittedProgrammeCount),
    ]
    switch health.coverage(at: now) {
    case .expired:
      status.append(localized("epg.status.expired", defaultValue: "Schedule expired"))
    case .futureOnly:
      if let start = health.coverageStartAt {
        status.append(
          String.localizedStringWithFormat(
            localized("epg.status.available_from", defaultValue: "Schedule available from %@"),
            guideDate(start)))
      }
    case .currentCoverage:
      if let end = health.coverageEndAt {
        status.append(
          String.localizedStringWithFormat(
            localized("epg.status.available_until", defaultValue: "Schedule available until %@"),
            guideDate(end)))
      }
    case .noData:
      status.append(localized("epg.status.no_data", defaultValue: "No guide data available"))
    }
    if health.lastResult == .failure {
      status.append(
        localized(
          "epg.status.previous_data_retained",
          defaultValue: "Latest guide refresh failed. Previous guide data is still available."))
    }
    return status
  }

  private static func guideDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  static let libraryTitle = localized("library.title", defaultValue: "Library")
  static let continueWatching = localized(
    "home.section.continue_watching", defaultValue: "Continue Watching")
  static let favorites = localized("home.section.favorites", defaultValue: "Favorites")
  static let addToFavorites = localized("favorite.add", defaultValue: "Add to Favorites")
  static let removeFromFavorites = localized(
    "favorite.remove", defaultValue: "Remove from Favorites")
  static let allSources = localized("library.all_sources", defaultValue: "All Sources")
  static let categories = localized("library.categories", defaultValue: "Categories")
  static let allCategories = localized("library.all_categories", defaultValue: "All Categories")
  static let loadMore = localized("library.load_more", defaultValue: "Load More")
  static let refreshLibrary = localized("library.refresh", defaultValue: "Refresh Library")
  static let librarySearchPrompt = localized("library.search.field", defaultValue: "Search Library")
  static let librarySearchPromptTitle = localized(
    "library.search.prompt.title", defaultValue: "Search your library")
  static let librarySearchPromptMessage = localized(
    "library.search.prompt.message",
    defaultValue: "Enter one or more words to find matching titles.")
  static let libraryNoResultsTitle = localized(
    "library.search.empty.title", defaultValue: "No results")
  static let libraryNoResultsMessage = localized(
    "library.search.empty.message", defaultValue: "Try another search or adjust the source filter.")
  static let libraryEmptyTitle = localized(
    "library.empty.title", defaultValue: "Nothing in this view")
  static let libraryEmptyMessage = localized(
    "library.empty.message", defaultValue: "Choose another category, source, or media type.")
  static let libraryNoSourcesTitle = localized(
    "library.no_sources.title", defaultValue: "Bring your library to AEVYNO")
  static let libraryNoSourcesMessage = localized(
    "library.no_sources.message",
    defaultValue: "Add a private media source to start building your local library.")
  static let libraryNoCatalogTitle = localized(
    "library.no_catalog.title", defaultValue: "Your source is ready")
  static let libraryNoCatalogMessage = localized(
    "library.no_catalog.message",
    defaultValue: "Refresh a source to load its catalog into your private local library.")
  static let libraryUnavailableTitle = localized(
    "library.error.title", defaultValue: "Library unavailable")
  static let libraryUnavailableMessage = localized(
    "library.error.message", defaultValue: "Your library could not be opened safely. Try again.")
  static let playbackUnavailable = localized(
    "library.detail.playback_unavailable", defaultValue: "Playback not available yet")
  static let playbackUnavailableHint = localized(
    "library.detail.playback_unavailable.hint", defaultValue: "Playback will be added in Phase 3")
  static let sourceFilterAccessibilityHint = localized(
    "library.source_filter.hint", defaultValue: "Filters the committed library by source")

  static let sources = localized("sources.title", defaultValue: "Sources")
  static let sourcesSubtitle = localized(
    "sources.subtitle",
    defaultValue: "Connect and maintain your private media sources."
  )
  static let play = localized("playback.action.play", defaultValue: "Play")
  static let startOver = localized("playback.action.start_over", defaultValue: "Start Over")
  static let playbackPreparing = localized(
    "playback.preparing", defaultValue: "Preparing playback"
  )
  static let playbackLoading = localized("playback.loading", defaultValue: "Loading")
  static let playbackBuffering = localized("playback.buffering", defaultValue: "Buffering")
  static let playbackFailed = localized("playback.failed.title", defaultValue: "Playback failed")
  static let playAccessibilityHint = localized(
    "playback.action.play.hint", defaultValue: "Opens the system player"
  )
  static let playbackRetryHint = localized(
    "playback.action.retry.hint", defaultValue: "Resolves a fresh playback attempt"
  )
  static let sourcesLoading = localized("sources.loading", defaultValue: "Loading sources")
  static let sourcesUnavailable = localized(
    "sources.unavailable.title",
    defaultValue: "Sources are unavailable"
  )
  static let sourcesUnavailableMessage = localized(
    "sources.unavailable.message",
    defaultValue: "Try again to open your saved source settings."
  )
  static let sourcesEmptyTitle = localized(
    "sources.empty.title",
    defaultValue: "No sources yet"
  )
  static let sourcesEmptyMessage = localized(
    "sources.empty.message",
    defaultValue: "Add an Xtream-compatible account or a secure, query-free M3U playlist."
  )
  static let addSource = localized("sources.action.add", defaultValue: "Add Source")
  static let editSource = localized("sources.action.edit", defaultValue: "Edit Source")
  static let sourceName = localized("sources.field.name", defaultValue: "Source name")
  static let sourceType = localized("sources.field.type", defaultValue: "Source type")
  static let serverAddress = localized("sources.field.server", defaultValue: "Server address")
  static let xmltvEndpoint = localized("sources.field.xmltv", defaultValue: "XMLTV endpoint")
  static let xmltvEndpointAccessibilityHint = localized(
    "sources.accessibility.xmltv_endpoint_hint",
    defaultValue: "Optional XMLTV schedule endpoint for this M3U source"
  )
  static let username = localized("sources.field.username", defaultValue: "Username")
  static let password = localized("sources.field.password", defaultValue: "Password")
  static let xtreamCompatible = localized(
    "sources.kind.xtream",
    defaultValue: "Xtream-compatible"
  )
  static let m3uPlaylist = localized("sources.kind.m3u", defaultValue: "M3U playlist")
  static let testConnection = localized(
    "sources.action.test_connection",
    defaultValue: "Test Connection"
  )
  static let save = localized("sources.action.save", defaultValue: "Save")
  static let delete = localized("sources.action.delete", defaultValue: "Delete")
  static let enable = localized("sources.action.enable", defaultValue: "Enable")
  static let disable = localized("sources.action.disable", defaultValue: "Disable")
  static let enabled = localized("sources.status.enabled", defaultValue: "Enabled")
  static let disabled = localized("sources.status.disabled", defaultValue: "Disabled")
  static let refreshNow = localized("sources.action.refresh", defaultValue: "Refresh Now")
  static let automaticRefresh = localized(
    "sources.refresh_policy.title", defaultValue: "Automatic Refresh")
  static let manualOnly = localized(
    "sources.refresh_policy.manual_only", defaultValue: "Manual only")
  static let every6Hours = localized(
    "sources.refresh_policy.every_6_hours", defaultValue: "Every 6 hours")
  static let every12Hours = localized(
    "sources.refresh_policy.every_12_hours", defaultValue: "Every 12 hours")
  static let daily = localized("sources.refresh_policy.daily", defaultValue: "Daily")
  static let automaticRefreshActiveExplanation = localized(
    "sources.refresh_policy.active_explanation",
    defaultValue:
      "Refreshes while AEVYNO is active. Missed opportunities resume the next time the app becomes active."
  )
  static let automaticRefreshPaused = localized(
    "sources.refresh_policy.paused",
    defaultValue: "Automatic refresh is paused while this source is disabled."
  )
  static let automaticRefreshAccessibilityHint = localized(
    "sources.accessibility.refresh_policy_hint",
    defaultValue: "Chooses how often this source becomes eligible while AEVYNO is active"
  )
  static let automaticRefreshEligibleNow = localized(
    "sources.refresh_policy.eligible_now", defaultValue: "Eligible for automatic refresh now"
  )
  static let neverRefreshed = localized(
    "sources.refresh_policy.never_refreshed", defaultValue: "Never refreshed")
  static let cancel = localized("action.cancel", defaultValue: "Cancel")
  static let credentialSaved = localized(
    "sources.credential.saved",
    defaultValue: "Credential saved securely"
  )
  static let replaceCredential = localized(
    "sources.credential.replace",
    defaultValue: "Replace Credential"
  )
  static let m3uQueryLimitation = localized(
    "sources.m3u.query_limitation",
    defaultValue:
      "This version accepts M3U addresses without query parameters or embedded credentials."
  )
  static let deleteSourceConfirmationTitle = localized(
    "sources.delete.confirmation.title",
    defaultValue: "Delete this source?"
  )
  static let deleteSourceConfirmationMessage = localized(
    "sources.delete.confirmation.message",
    defaultValue: "Its saved credential, local catalog, and refresh status will be removed."
  )
  static let sourcesAccessibilityHint = localized(
    "sources.accessibility.open_hint",
    defaultValue: "Opens source management"
  )
  static let addSourceAccessibilityHint = localized(
    "sources.accessibility.add_hint",
    defaultValue: "Opens the new source form"
  )
  static let editSourceAccessibilityHint = localized(
    "sources.accessibility.edit_hint",
    defaultValue: "Opens source details and actions"
  )
  static let testConnectionAccessibilityHint = localized(
    "sources.accessibility.test_hint",
    defaultValue: "Checks the source without saving or importing its catalog"
  )
  static let passwordAccessibilityHint = localized(
    "sources.accessibility.password_hint",
    defaultValue: "Secure entry; the value is never spoken or displayed"
  )
  static let replaceCredentialAccessibilityHint = localized(
    "sources.accessibility.replace_credential_hint",
    defaultValue: "Shows secure fields for a replacement credential"
  )
  static let deleteAccessibilityHint = localized(
    "sources.accessibility.delete_hint",
    defaultValue: "Permanently removes this source after confirmation"
  )

  static func sourceKind(_ kind: SourceKind) -> String {
    switch kind {
    case .xtreamCompatible: xtreamCompatible
    case .m3u: m3uPlaylist
    }
  }

  static func libraryScope(_ scope: LibraryBrowseScope) -> String {
    switch scope {
    case .library: localized("library.scope.library", defaultValue: "Library")
    case .movies: localized("library.scope.movies", defaultValue: "Movies")
    case .series: localized("library.scope.series", defaultValue: "Series")
    case .liveTV: localized("library.scope.live", defaultValue: "Live TV")
    case .playlist: localized("library.scope.playlist", defaultValue: "Playlist")
    case .search: localized("library.scope.search", defaultValue: "Search")
    }
  }

  static func libraryKind(_ kind: CatalogMediaKind) -> String {
    switch kind {
    case .vod: localized("library.kind.movie", defaultValue: "Movie")
    case .series: localized("library.kind.series", defaultValue: "Series")
    case .live: localized("library.kind.live", defaultValue: "Live TV")
    case .unspecified: localized("library.kind.playlist", defaultValue: "Playlist")
    }
  }

  static func libraryItemMetadata(_ item: LibraryItemPresentation) -> String {
    var values = [libraryKind(item.mediaKind)]
    if !item.sourceName.isEmpty { values.append(item.sourceName) }
    if let categoryTitle = item.categoryTitle, !categoryTitle.isEmpty {
      values.append(categoryTitle)
    }
    return values.joined(separator: "  ·  ")
  }

  static func resumeFrom(_ position: TimeInterval) -> String {
    String.localizedStringWithFormat(
      localized("playback.action.resume_from", defaultValue: "Resume from %@"),
      formattedPlaybackTime(position)
    )
  }

  static func playbackFailureMessage(_ failure: PlaybackFailure?) -> String {
    switch failure {
    case .sourceUnavailable:
      localized(
        "playback.failure.source_unavailable",
        defaultValue: "The source is not available right now."
      )
    case .itemUnavailable, .notFound:
      localized(
        "playback.failure.item_unavailable",
        defaultValue: "This item is no longer available."
      )
    case .unsupported, .unsupportedFormat:
      localized(
        "playback.failure.unsupported",
        defaultValue: "This item cannot be played yet."
      )
    case .unauthorized, .forbidden:
      localized(
        "playback.failure.authorization",
        defaultValue: "The source did not allow playback."
      )
    case .transportSecurity:
      localized(
        "playback.failure.transport_security",
        defaultValue: "A secure connection could not be established."
      )
    case .transport:
      localized(
        "playback.failure.transport",
        defaultValue: "The stream could not be reached. Try again."
      )
    case .mediaUnavailable, .unknown, nil:
      localized(
        "playback.failure.generic",
        defaultValue: "Playback could not continue. Try again."
      )
    }
  }

  static func playbackState(_ state: PlaybackState) -> String {
    switch state {
    case .idle: localized("playback.state.idle", defaultValue: "Player idle")
    case .loading, .ready: playbackLoading
    case .playing: localized("playback.state.playing", defaultValue: "Playing")
    case .paused: localized("playback.state.paused", defaultValue: "Paused")
    case .buffering: playbackBuffering
    case .ended: localized("playback.state.ended", defaultValue: "Playback ended")
    case .failed: playbackFailed
    }
  }

  private static func formattedPlaybackTime(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: max(seconds, 0)) ?? "0:00"
  }

  static func refreshPolicy(_ policy: RefreshPolicy) -> String {
    switch policy {
    case .manualOnly: manualOnly
    case .automatic(.every6Hours): every6Hours
    case .automatic(.every12Hours): every12Hours
    case .automatic(.daily): daily
    }
  }

  static func lastRefreshed(_ date: Date?) -> String {
    guard let date else { return neverRefreshed }
    return String.localizedStringWithFormat(
      localized("sources.refresh_policy.last_refreshed", defaultValue: "Last refreshed: %@"),
      formatted(date)
    )
  }

  static func lastAttempt(_ date: Date, result: CatalogRefreshResultCategory) -> String {
    String.localizedStringWithFormat(
      localized(
        "sources.refresh_policy.last_attempt", defaultValue: "Last attempt: %@ — %@"
      ),
      formatted(date),
      refreshResult(result)
    )
  }

  static func eligibleAfter(_ date: Date) -> String {
    String.localizedStringWithFormat(
      localized("sources.refresh_policy.eligible_after", defaultValue: "Eligible after %@"),
      formatted(date)
    )
  }

  static func sourceRowAccessibilityLabel(name: String, kind: String, status: String) -> String {
    String.localizedStringWithFormat(
      localized(
        "sources.accessibility.row_label",
        defaultValue: "%@, %@, %@"
      ),
      name,
      kind,
      status
    )
  }

  static func sourceOperationState(_ state: SourceOperationState) -> String {
    switch state {
    case .testing:
      return localized("sources.operation.testing", defaultValue: "Testing connection…")
    case .connectionSucceeded:
      return localized("sources.operation.connection_success", defaultValue: "Connection succeeded")
    case .saving:
      return localized("sources.operation.saving", defaultValue: "Saving…")
    case .saved:
      return localized("sources.operation.saved", defaultValue: "Source saved")
    case .enabled:
      return localized("sources.operation.enabled", defaultValue: "Source enabled")
    case .disabled:
      return localized("sources.operation.disabled", defaultValue: "Source disabled")
    case .deleted:
      return localized("sources.operation.deleted", defaultValue: "Source deleted")
    case .cancelled:
      return localized("sources.operation.cancelled", defaultValue: "Operation cancelled")
    case .failed(let error):
      return sourceError(error)
    case .refreshing(let stage):
      return refreshStage(stage)
    }
  }

  private static func sourceError(_ error: SourceManagementError) -> String {
    switch error {
    case .invalidInput:
      localized("sources.error.invalid_fields", defaultValue: "Check the highlighted fields.")
    case .credentialUnavailable:
      localized(
        "sources.error.credential_unavailable", defaultValue: "The saved credential is unavailable."
      )
    case .authenticationRejected:
      localized(
        "sources.error.authentication", defaultValue: "The source rejected these credentials.")
    case .timeout:
      localized("sources.error.timeout", defaultValue: "The source took too long to respond.")
    case .unreachableProvider:
      localized("sources.error.unreachable", defaultValue: "The source could not be reached.")
    case .malformedSource:
      localized(
        "sources.error.malformed", defaultValue: "The source returned an unreadable response.")
    case .inProgress:
      localized("sources.error.in_progress", defaultValue: "This source is already refreshing.")
    case .sourceNotFound:
      localized("sources.error.not_found", defaultValue: "This source is no longer available.")
    case .secureStorageFailure:
      localized(
        "sources.error.secure_storage", defaultValue: "The credential could not be saved securely.")
    case .persistenceFailure:
      localized(
        "sources.error.persistence", defaultValue: "The source settings could not be saved safely.")
    case .compensationFailure, .cleanupFailure:
      localized(
        "sources.error.cleanup", defaultValue: "Cleanup did not finish. Try the action again.")
    }
  }

  private static func refreshStage(_ stage: CatalogRefreshStage) -> String {
    switch stage {
    case .validating:
      localized("sources.refresh.validating", defaultValue: "Validating source…")
    case .acquiring:
      localized("sources.refresh.acquiring", defaultValue: "Contacting source…")
    case .parsingOrDecoding:
      localized("sources.refresh.parsing", defaultValue: "Reading catalog…")
    case .staging:
      localized("sources.refresh.staging", defaultValue: "Preparing update…")
    case .committing:
      localized("sources.refresh.committing", defaultValue: "Saving catalog…")
    case .completed:
      localized("sources.refresh.completed", defaultValue: "Refresh completed")
    case .failed:
      localized("sources.refresh.failed", defaultValue: "Refresh failed")
    case .cancelled:
      localized("sources.operation.cancelled", defaultValue: "Operation cancelled")
    }
  }

  private static func refreshResult(_ result: CatalogRefreshResultCategory) -> String {
    switch result {
    case .success:
      localized("sources.refresh_result.success", defaultValue: "Succeeded")
    case .cancelled:
      localized("sources.refresh_result.cancelled", defaultValue: "Cancelled")
    case .inProgress:
      localized("sources.refresh_result.in_progress", defaultValue: "In progress")
    default:
      localized("sources.refresh_result.failed", defaultValue: "Needs attention")
    }
  }

  private static func formatted(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

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
