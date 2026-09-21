import XCTest

@MainActor
final class AEVYNOTVUITests: XCTestCase {
  func testProductionNoSourceOnboardingOpensSourceManagement() {
    let app = launchApp(arguments: ["--ui-production-no-sources"])
    let addSource = app.buttons["library.add-source"]

    XCTAssertTrue(addSource.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: addSource))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.buttons["sources.add"].waitForExistence(timeout: 5))
  }

  func testProductionCatalogLoadsAndUnspecifiedRemainsPlaylist() {
    let app = launchApp(arguments: ["--ui-production-catalog"])
    let first = app.buttons["library.item.movie-1"]

    XCTAssertTrue(first.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: first))
    XCTAssertTrue(app.buttons["library.item.m3u-1"].exists)
    XCTAssertTrue(
      app.buttons["library.item.m3u-1"].value as? String == "Playlist  ·  Family Playlist")
  }

  func testProductionMoviesSeriesLiveAndPlaylistScopes() {
    let app = launchApp(arguments: ["--ui-production-catalog"])
    XCTAssertTrue(app.buttons["library.item.movie-1"].waitForExistence(timeout: 10))

    XCTAssertTrue(focusAndSelect(app.buttons["library.scope.movies"], in: app))
    XCTAssertTrue(app.buttons["library.item.movie-1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.item.series-1"].exists)

    XCTAssertTrue(focusAndSelect(app.buttons["library.scope.series"], in: app))
    XCTAssertTrue(app.buttons["library.item.series-1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.item.live-1"].exists)

    XCTAssertTrue(focusAndSelect(app.buttons["library.scope.liveTV"], in: app))
    XCTAssertTrue(app.buttons["library.item.live-1"].waitForExistence(timeout: 5))

    XCTAssertTrue(focusAndSelect(app.buttons["library.scope.playlist"], in: app))
    XCTAssertTrue(app.buttons["library.item.m3u-1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.item.movie-1"].exists)
  }

  func testProductionCategoryAndDetailRestoreExactItemFocus() {
    let app = launchApp(arguments: ["--ui-production-catalog"])
    let item = app.buttons["library.item.movie-2"]
    XCTAssertTrue(item.waitForExistence(timeout: 10))

    XCTAssertTrue(focusAndSelect(app.buttons["library.category.film"], in: app))
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    XCTAssertTrue(focusAndSelect(item, in: app))
    XCTAssertTrue(app.staticTexts["library.detail.title"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts["library.detail.playback-unavailable"].waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: item))
  }

  func testProductionCategoryBrowseAndBackToAllCategories() {
    let app = launchApp(arguments: ["--ui-production-catalog"])
    XCTAssertTrue(app.buttons["library.item.movie-1"].waitForExistence(timeout: 10))

    XCTAssertTrue(focusAndSelect(app.buttons["library.category.film"], in: app))
    XCTAssertTrue(app.buttons["library.category.all"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["library.item.movie-2"].exists)
    XCTAssertFalse(app.buttons["library.item.live-1"].exists)

    XCTAssertTrue(focusAndSelect(app.buttons["library.category.all"], in: app))
    XCTAssertTrue(app.buttons["library.item.live-1"].waitForExistence(timeout: 5))
  }

  func testProductionSourceFilterIncludesDisabledCommittedCatalog() {
    let app = launchApp(arguments: ["--ui-production-catalog"])
    XCTAssertTrue(app.buttons["library.item.movie-1"].waitForExistence(timeout: 10))

    let disabledSource = app.buttons["Family Playlist"]
    XCTAssertTrue(focusAndSelect(disabledSource, in: app))

    XCTAssertTrue(app.buttons["library.item.m3u-1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.item.movie-1"].exists)
  }

  func testProductionSearchAndNoResultState() {
    let app = launchApp(arguments: ["--ui-production-search-results"])
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["library.item.series-1"].waitForExistence(timeout: 5))

    app.terminate()
    let emptyApp = launchApp(arguments: ["--ui-production-search-empty"])
    XCTAssertTrue(
      emptyApp.descendants(matching: .any)["library.no-results"].waitForExistence(timeout: 10))
  }

  func testProductionArabicRTLAndAccessibilityExposeNoReferences() throws {
    let app = launchApp(arguments: ["--ui-production-catalog"], locale: "ar")
    let item = app.buttons["library.item.m3u-1"]
    XCTAssertTrue(item.waitForExistence(timeout: 10))
    XCTAssertTrue((item.value as? String)?.contains("قائمة تشغيل") == true)
    let exposed = "\(item.label) \(item.value ?? "")"
    XCTAssertFalse(exposed.contains("00000000"))
    XCTAssertFalse(exposed.contains("example.invalid"))
    try app.performAccessibilityAudit()
  }

  func testProductionDetailPresentsDeterministicNowAndNext() {
    let app = launchApp(arguments: ["--ui-production-now-next"])
    _ = openProductionItem("live-1", in: app)

    let programmes = app.staticTexts.matching(identifier: "library.detail.now-next")
    let now = programmes.element(boundBy: 0)
    let next = programmes.element(boundBy: 1)
    XCTAssertTrue(now.waitForExistence(timeout: 5))
    XCTAssertTrue(next.exists)
    XCTAssertEqual(now.label, "Now: Morning Brief")
    XCTAssertEqual(next.label, "Next: Market Review")
    XCTAssertFalse("\(now.label) \(now.value ?? "")".contains("synthetic-news"))
  }

  func testProductionDetailWithoutEPGMappingOmitsNowNext() {
    let app = launchApp(arguments: ["--ui-production-catalog"])
    _ = openProductionItem("live-1", in: app)

    let programmes = app.staticTexts.matching(identifier: "library.detail.now-next")
    XCTAssertFalse(programmes.firstMatch.exists)
  }

  func testProductionArabicNowNextIsLocalizedAndSafe() throws {
    let app = launchApp(arguments: ["--ui-production-now-next"], locale: "ar")
    _ = openProductionItem("live-1", in: app)

    let programmes = app.staticTexts.matching(identifier: "library.detail.now-next")
    let now = programmes.element(boundBy: 0)
    let next = programmes.element(boundBy: 1)
    XCTAssertTrue(now.waitForExistence(timeout: 5))
    XCTAssertTrue(next.exists)
    XCTAssertTrue(now.label.contains("الآن:"))
    XCTAssertTrue(now.label.contains("Morning Brief"))
    XCTAssertTrue(next.label.contains("التالي:"))
    XCTAssertTrue(next.label.contains("Market Review"))
    let exposed = "\(now.label) \(now.value ?? "") \(next.label) \(next.value ?? "")"
    XCTAssertFalse(exposed.contains("synthetic-news"))
    XCTAssertFalse(exposed.contains("00000000"))
    try app.performAccessibilityAudit()
  }

  func testProductionArabicRTLSearch() {
    let app = launchApp(arguments: ["--ui-production-search-arabic"], locale: "ar")
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))

    let result = app.buttons["library.item.series-ar"]
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    XCTAssertTrue((result.value as? String)?.contains("مسلسل") == true)
  }

  func testProductionPaginationKeepsLoadMoreFocusStable() {
    let app = launchApp(arguments: ["--ui-production-pagination"])
    XCTAssertTrue(app.buttons["library.item.page-000"].waitForExistence(timeout: 10))
    let loadMore = app.buttons["library.load-more"]
    for _ in 0..<20 where !loadMore.exists {
      XCUIRemote.shared.press(.down)
    }
    XCTAssertTrue(loadMore.waitForExistence(timeout: 5))

    XCTAssertTrue(focusAndSelect(loadMore, in: app))

    XCTAssertTrue(waitForValue("128", on: app.descendants(matching: .any)["library.loaded"]))
    XCTAssertTrue(loadMore.exists)
    XCTAssertTrue(waitForFocus(on: loadMore))
  }

  func testProductionRefreshInvalidatesWithoutStealingFocus() {
    let app = launchApp(arguments: ["--ui-production-refresh"])
    let stable = app.buttons["library.item.refresh-stable"]
    XCTAssertTrue(stable.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: stable))

    XCTAssertTrue(app.buttons["library.item.refresh-new"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: stable))
  }

  func testContinueWatchingShowsResumableFirstItemAndProgress() {
    let app = launchApp(arguments: ["--ui-continue-watching"])
    let item = app.buttons["continue-watching.item.m3u-1"]

    XCTAssertTrue(item.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Continue Watching"].exists)
    XCTAssertTrue((item.value as? String)?.contains("25") == true)
  }

  func testContinueWatchingResumeRestoresExactCardFocus() {
    let app = launchApp(arguments: ["--ui-continue-watching", "--ui-playback-playing"])
    let item = app.buttons["continue-watching.item.m3u-1"]

    XCTAssertTrue(item.waitForExistence(timeout: 10))
    XCTAssertTrue(focusAndSelect(item, in: app))
    XCTAssertTrue(
      app.descendants(matching: .any)["playback.state.playing"].waitForExistence(timeout: 5))

    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: item))
  }

  func testContinueWatchingCompletedOrOrphanedFixtureLeavesNoFocusGap() {
    for argument in ["--ui-continue-watching-completed", "--ui-continue-watching-orphaned"] {
      let app = launchApp(arguments: [argument])
      XCTAssertTrue(app.buttons["library.item.movie-1"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["continue-watching.item.m3u-1"].exists)
      XCTAssertTrue(waitForFocus(on: app.buttons["library.item.movie-1"]))
      app.terminate()
    }
  }

  func testContinueWatchingArabicRTLAndAccessibilityAreSafe() throws {
    let app = launchApp(arguments: ["--ui-continue-watching"], locale: "ar")
    let item = app.buttons["continue-watching.item.m3u-1"]

    XCTAssertTrue(item.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["متابعة المشاهدة"].exists)
    let exposed = "\(item.label) \(item.value ?? "")"
    XCTAssertFalse(exposed.contains("m3u-1"))
    XCTAssertFalse(exposed.contains("image.invalid"))
    XCTAssertFalse(exposed.contains("provider"))
    try app.performAccessibilityAudit()
  }

  func testFavoritesRailShowsDeterministicFirstCardAndRestoresFocusFromDetail() {
    let app = launchApp(arguments: ["--ui-favorites"])
    let first = app.buttons["favorites.item.movie-1"]

    XCTAssertTrue(first.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Favorites"].exists)
    XCTAssertTrue(focusAndSelect(first, in: app))
    XCTAssertTrue(app.staticTexts["library.detail.title"].waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: first))
  }

  func testUnfavoriteFocusedFavoriteMovesToDeterministicSurvivingFavorite() {
    let app = launchApp(arguments: ["--ui-favorites"])
    let first = app.buttons["favorites.item.movie-1"]
    let second = app.buttons["favorites.item.movie-2"]

    XCTAssertTrue(first.waitForExistence(timeout: 10))
    XCTAssertTrue(focusAndSelect(first, in: app))
    XCTAssertTrue(focusAndSelect(app.buttons["library.detail.favorite"], in: app))
    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertFalse(first.exists)
    XCTAssertTrue(
      waitForFocus(on: second),
      "Expected movie-2 focus after removing movie-1. \(focusDiagnostics(in: app))"
    )
  }

  func testRemovingFinalFavoriteRemovesRailWithoutFocusGap() {
    let app = launchApp(arguments: ["--ui-favorites-single"])
    let favorite = app.buttons["favorites.item.movie-1"]

    XCTAssertTrue(favorite.waitForExistence(timeout: 10))
    XCTAssertTrue(focusAndSelect(favorite, in: app))
    XCTAssertTrue(focusAndSelect(app.buttons["library.detail.favorite"], in: app))
    XCUIRemote.shared.press(.menu)
    XCTAssertFalse(favorite.waitForExistence(timeout: 1))
    XCTAssertTrue(app.buttons["library.item.movie-1"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: app.buttons["library.item.movie-1"]))
  }

  func testFavoriteFromDetailAddsToFavoritesRail() {
    let app = launchApp(arguments: ["--ui-favorites-empty"])
    let item = openProductionItem("movie-1", in: app)

    XCTAssertTrue(focusAndSelect(app.buttons["library.detail.favorite"], in: app))
    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["favorites.item.movie-1"].waitForExistence(timeout: 5))
  }

  func testFavoritesArabicRTLandAccessibilityAreSafe() throws {
    let app = launchApp(arguments: ["--ui-favorites"], locale: "ar")
    let item = app.buttons["favorites.item.movie-1"]

    XCTAssertTrue(item.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["المفضلة"].exists)
    let exposed = "\(item.label) \(item.value ?? "")"
    XCTAssertFalse(exposed.contains("00000000"))
    XCTAssertFalse(exposed.contains("example.invalid"))
    XCTAssertFalse(exposed.lowercased().contains("provider"))
    try app.performAccessibilityAudit()
  }

  func testPlaybackPlayableDetailExposesPlay() {
    let app = launchApp(arguments: ["--ui-playback-playing"])
    openProductionItem("m3u-1", in: app)

    let play = app.buttons["library.detail.play"]
    XCTAssertTrue(play.waitForExistence(timeout: 5))
    XCTAssertEqual(play.label, "Play")
    XCTAssertTrue(waitForFocus(on: play))
  }

  func testPlaybackResumableDetailExposesResumeAndStartOver() {
    let app = launchApp(arguments: ["--ui-playback-resumable"])
    openProductionItem("m3u-1", in: app)

    let resume = app.buttons["library.detail.resume"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    XCTAssertTrue(resume.label.hasPrefix("Resume from "))
    XCTAssertTrue(app.buttons["library.detail.start-over"].exists)
    XCTAssertTrue(waitForFocus(on: resume))
  }

  func testPlaybackCompletedDetailDoesNotOfferStaleResume() {
    let app = launchApp(arguments: ["--ui-playback-completed"])
    openProductionItem("m3u-1", in: app)

    XCTAssertTrue(app.buttons["library.detail.play"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["library.detail.resume"].exists)
    XCTAssertFalse(app.buttons["library.detail.start-over"].exists)
  }

  func testPlaybackDeterministicLoadingPlayingPausedAndBufferingStates() {
    let scenarios = [
      ("--ui-playback-loading", "playback.state.loading"),
      ("--ui-playback-playing", "playback.state.playing"),
      ("--ui-playback-paused", "playback.state.paused"),
      ("--ui-playback-buffering", "playback.state.buffering"),
    ]

    for (argument, identifier) in scenarios {
      let app = launchApp(arguments: [argument])
      openProductionItem("m3u-1", in: app)
      XCTAssertTrue(focusAndSelect(app.buttons["library.detail.play"], in: app))
      XCTAssertTrue(
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
        "Expected deterministic state \(identifier)"
      )
      app.terminate()
    }
  }

  func testPlaybackFailureRetryCreatesSafeFreshAttempt() {
    let app = launchApp(arguments: ["--ui-playback-retry"])
    openProductionItem("m3u-1", in: app)
    XCTAssertTrue(focusAndSelect(app.buttons["library.detail.play"], in: app))

    XCTAssertTrue(
      app.descendants(matching: .any)["playback.state.failed"].waitForExistence(timeout: 5))
    let retry = app.buttons["playback.retry"]
    XCTAssertTrue(retry.exists)
    XCTAssertTrue(focusAndSelect(retry, in: app))
    XCTAssertTrue(
      app.descendants(matching: .any)["playback.state.playing"].waitForExistence(timeout: 5))
  }

  func testPlaybackExitReturnsToDetailThenRestoresExactLibraryItemFocus() {
    let app = launchApp(arguments: ["--ui-playback-playing"])
    let item = openProductionItem("m3u-1", in: app)
    XCTAssertTrue(focusAndSelect(app.buttons["library.detail.play"], in: app))
    XCTAssertTrue(
      app.descendants(matching: .any)["playback.state.playing"].waitForExistence(timeout: 5))

    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(app.staticTexts["library.detail.title"].waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: item))
  }

  func testPlaybackUnsupportedSeriesCommunicatesSafeLimitation() {
    let app = launchApp(arguments: ["--ui-playback-playing"])
    openProductionItem("series-1", in: app)

    let limitation = app.staticTexts["library.detail.playback-unavailable"]
    XCTAssertTrue(limitation.waitForExistence(timeout: 5))
    XCTAssertEqual(limitation.label, "This item cannot be played yet.")
    XCTAssertFalse(app.buttons["library.detail.play"].exists)
  }

  func testPlaybackArabicErrorIsLocalizedAccessibleAndRedacted() throws {
    let app = launchApp(arguments: ["--ui-playback-failure"], locale: "ar")
    openProductionItem("m3u-1", in: app)
    XCTAssertTrue(focusAndSelect(app.buttons["library.detail.play"], in: app))

    XCTAssertTrue(
      app.descendants(matching: .any)["playback.state.failed"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["playback.retry"].label, "إعادة المحاولة")
    XCTAssertTrue(app.staticTexts["فشل التشغيل"].exists)
    let exposed = app.descendants(matching: .any).allElementsBoundByIndex
      .map { "\($0.label) \($0.value ?? "")" }
      .joined(separator: " ")
    XCTAssertFalse(exposed.contains("example.invalid"))
    XCTAssertFalse(exposed.lowercased().contains("token="))
    try app.performAccessibilityAudit(
      for: [
        .contrast, .elementDetection, .sufficientElementDescription, .dynamicType, .textClipped,
        .trait,
      ])
  }

  func testHomeLaunchesWithInitialFocusAndMovesRight() {
    let app = launchApp()

    let firstCard = app.buttons["home.card.continue-orbit"]
    XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: firstCard), "The initial media card should receive focus")

    XCUIRemote.shared.press(.right)

    let secondCard = app.buttons["home.card.continue-harbor"]
    XCTAssertTrue(
      waitForFocus(on: secondCard), "Right navigation should move focus to the next card")
  }

  func testDetailPresentationAndFocusRestoration() throws {
    let app = launchApp()
    let firstCard = app.buttons["home.card.continue-orbit"]
    XCTAssertTrue(firstCard.waitForExistence(timeout: 10))

    XCUIRemote.shared.press(.right)
    let openedCard = app.buttons["home.card.continue-harbor"]
    XCTAssertTrue(waitForFocus(on: openedCard))
    XCUIRemote.shared.press(.select)

    XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["detail.play"].exists)
    try app.performAccessibilityAudit()

    let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
    detailScreenshot.name = "Synthetic Detail screen"
    detailScreenshot.lifetime = .keepAlways
    add(detailScreenshot)

    XCUIRemote.shared.press(.select)
    let playbackNotice = app.alerts.firstMatch
    XCTAssertTrue(playbackNotice.waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(playbackNotice.waitForNonExistence(timeout: 5))

    XCUIRemote.shared.press(.menu)

    XCTAssertTrue(openedCard.waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitForFocus(on: openedCard), "Returning from Detail should restore the opened card")

    for cycle in 2...3 {
      XCUIRemote.shared.press(.select)
      XCTAssertTrue(
        app.staticTexts["detail.title"].waitForExistence(timeout: 5),
        "Detail should open on cycle \(cycle)"
      )
      XCUIRemote.shared.press(.menu)
      XCTAssertTrue(openedCard.waitForExistence(timeout: 5))
      XCTAssertTrue(
        waitForFocus(on: openedCard),
        "Returning from Detail should restore the opened card on cycle \(cycle)"
      )
    }
  }

  func testEmptyStateIsIntentionalAndNonInteractive() {
    let app = launchApp(arguments: ["--ui-state-empty"])

    XCTAssertTrue(app.otherElements["home.empty"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["home.retry"].exists)
  }

  func testErrorStateOffersRetry() {
    let app = launchApp(arguments: ["--ui-state-error"])

    XCTAssertTrue(app.otherElements["home.error"].waitForExistence(timeout: 10))
    let retry = app.buttons["home.retry"]
    XCTAssertTrue(retry.exists)
    XCTAssertEqual(retry.label, "Retry")
    XCTAssertTrue(waitForFocus(on: retry))
  }

  func testLoadingStateUsesStableNonFocusableSkeleton() {
    let app = launchApp(arguments: ["--ui-state-loading"])

    XCTAssertTrue(app.scrollViews["home.loading"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons.firstMatch.exists)
  }

  func testLargeCatalogStressModeUsesStableSyntheticIDs() {
    let app = launchApp(arguments: ["--ui-stress-catalog"])
    let firstCard = app.buttons["home.card.stress-10000-0"]

    XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: firstCard))
  }

  func testLoadedHomePassesSimulatorAccessibilityAudit() throws {
    let app = launchApp()
    let firstCard = app.buttons["home.card.continue-orbit"]

    XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
    try app.performAccessibilityAudit()
  }

  func testGermanHomeLoadsWithLocalizedChrome() {
    let app = launchApp(locale: "de")
    let firstCard = app.buttons["home.card.continue-orbit"]

    XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
    XCTAssertEqual(firstCard.label, "Orbitarchiv 17")
    XCTAssertTrue(app.staticTexts["Weiterschauen"].exists)
  }

  func testArabicHomeUsesRTLAndRestoresFocusFromDetail() throws {
    let app = launchApp(locale: "ar")
    let firstCard = app.buttons["home.card.continue-orbit"]
    let secondCard = app.buttons["home.card.continue-harbor"]

    XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
    XCTAssertTrue(secondCard.exists)
    XCTAssertEqual(firstCard.label, "أرشيف Orbit 17")
    XCTAssertGreaterThan(firstCard.frame.midX, secondCard.frame.midX)
    XCTAssertTrue(waitForFocus(on: firstCard))

    let homeScreenshot = XCTAttachment(screenshot: app.screenshot())
    homeScreenshot.name = "Arabic RTL Home"
    homeScreenshot.lifetime = .keepAlways
    add(homeScreenshot)

    XCUIRemote.shared.press(.left)
    XCTAssertTrue(
      waitForFocus(on: secondCard),
      "Left navigation should move to the visually next card in Arabic RTL"
    )
    XCUIRemote.shared.press(.select)

    let detailTitle = app.staticTexts["detail.title"]
    XCTAssertTrue(detailTitle.waitForExistence(timeout: 5))
    XCTAssertEqual(detailTitle.label, "دراسة الميناء 08")
    XCTAssertEqual(app.buttons["detail.play"].label, "تشغيل المعاينة")
    try app.performAccessibilityAudit()

    let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
    detailScreenshot.name = "Arabic RTL Detail"
    detailScreenshot.lifetime = .keepAlways
    add(detailScreenshot)

    XCUIRemote.shared.press(.select)
    let previewNotice = app.alerts.firstMatch
    XCTAssertTrue(previewNotice.waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(previewNotice.waitForNonExistence(timeout: 5))

    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(secondCard.waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitForFocus(on: secondCard),
      "Returning from Arabic Detail should restore the opened card"
    )
  }

  func testArabicEmptyAndLoadingStatesRemainNonFocusable() {
    let emptyApp = launchApp(arguments: ["--ui-state-empty"], locale: "ar")
    XCTAssertTrue(emptyApp.otherElements["home.empty"].waitForExistence(timeout: 10))
    XCTAssertTrue(emptyApp.staticTexts["شاشتك جاهزة"].exists)
    XCTAssertFalse(emptyApp.buttons.firstMatch.exists)
    emptyApp.terminate()

    let loadingApp = launchApp(arguments: ["--ui-state-loading"], locale: "ar")
    let loading = loadingApp.scrollViews["home.loading"]
    XCTAssertTrue(loading.waitForExistence(timeout: 10))
    XCTAssertEqual(loading.label, "جارٍ تحميل معاينة الصفحة الرئيسية")
    XCTAssertFalse(loadingApp.buttons.firstMatch.exists)
  }

  func testArabicErrorLocalizesRetryAndGivesItFocus() {
    let app = launchApp(arguments: ["--ui-state-error"], locale: "ar")
    let retry = app.buttons["home.retry"]

    XCTAssertTrue(retry.waitForExistence(timeout: 10))
    XCTAssertEqual(retry.label, "إعادة المحاولة")
    XCTAssertTrue(waitForFocus(on: retry))
  }

  func testOpensSourcesFromHomeAndShowsEmptyState() {
    let app = launchApp(arguments: ["--ui-source-management"])
    let sourceEntry = app.buttons["home.sources"]

    XCTAssertTrue(sourceEntry.waitForExistence(timeout: 10))
    XCUIRemote.shared.press(.up)
    XCTAssertTrue(waitForFocus(on: sourceEntry))
    XCUIRemote.shared.press(.select)

    XCTAssertTrue(app.buttons["sources.add"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["No sources yet"].exists)
  }

  func testSourceValidationReturnsFocusToFirstInvalidField() {
    let app = launchSourceManagement()
    let addSource = app.buttons["sources.add"]
    XCTAssertTrue(addSource.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: addSource))
    XCUIRemote.shared.press(.select)

    let name = app.textFields["source.name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: name), "Name should receive initial editor focus")

    XCUIRemote.shared.press(.down)
    XCUIRemote.shared.press(.down)
    let endpoint = app.textFields["source.endpoint"]
    XCTAssertTrue(waitForFocus(on: endpoint), "Endpoint should be reachable below source type")
    XCUIRemote.shared.press(.down)
    XCUIRemote.shared.press(.down)
    let password = app.secureTextFields["source.password"]
    XCTAssertTrue(waitForFocus(on: password), "The secure credential field should be focusable")
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["Manual only"]))
    XCUIRemote.shared.press(.down)
    let save = app.buttons["source.save"]
    XCTAssertTrue(waitForFocus(on: save))
    XCUIRemote.shared.press(.select)

    let status = app.staticTexts["source.status"]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    XCTAssertEqual(status.label, "Check the highlighted fields.")
    XCTAssertTrue(waitForFocus(on: name), "Validation should return remote focus to Name")
  }

  func testXtreamSecureFormTestsConnectionAndSavesSyntheticSource() {
    let app = launchSourceManagement(arguments: ["--ui-source-draft-xtream"])
    let addSource = app.buttons["sources.add"]
    XCTAssertTrue(addSource.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: addSource))
    XCUIRemote.shared.press(.select)
    let name = app.textFields["source.name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: name), "Name should receive initial editor focus")
    XCUIRemote.shared.press(.down)
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.textFields["source.endpoint"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.textFields["source.username"]))
    XCUIRemote.shared.press(.down)
    let secureField = app.secureTextFields["source.password"]
    XCTAssertTrue(secureField.exists)
    XCTAssertTrue(waitForFocus(on: secureField))
    XCTAssertFalse(secureField.label.contains("synthetic-secret"))
    XCTAssertFalse((secureField.value as? String)?.contains("synthetic-secret") ?? false)

    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["Manual only"]))
    XCUIRemote.shared.press(.down)
    let save = app.buttons["source.save"]
    XCTAssertTrue(waitForFocus(on: save))
    XCUIRemote.shared.press(.left)
    let testConnection = app.buttons["source.test"]
    XCTAssertTrue(waitForFocus(on: testConnection))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(waitForLabel("Connection succeeded", on: app.staticTexts["source.status"]))
    XCTAssertTrue(waitForFocus(on: testConnection), "Connection status must not steal focus")
    XCUIRemote.shared.press(.right)
    XCTAssertTrue(waitForFocus(on: save))
    XCUIRemote.shared.press(.select)

    let savedRow = app.buttons["sources.row"]
    XCTAssertTrue(savedRow.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: savedRow))
  }

  func testSyntheticConnectionFailureIsSafeAndM3UFormHasNoCredentialField() {
    let failedApp = launchSourceManagement(
      arguments: ["--ui-source-connection-failure", "--ui-source-draft-xtream"])
    let failedAddSource = failedApp.buttons["sources.add"]
    XCTAssertTrue(failedAddSource.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: failedAddSource))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(failedApp.textFields["source.name"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: failedApp.textFields["source.name"]))
    XCUIRemote.shared.press(.down)
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: failedApp.textFields["source.endpoint"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: failedApp.textFields["source.username"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: failedApp.secureTextFields["source.password"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: failedApp.buttons["Manual only"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: failedApp.buttons["source.save"]))
    XCUIRemote.shared.press(.left)
    let failedTestConnection = failedApp.buttons["source.test"]
    XCTAssertTrue(waitForFocus(on: failedTestConnection))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(
      waitForLabel(
        "The source rejected these credentials.",
        on: failedApp.staticTexts["source.status"]
      )
    )
    XCTAssertFalse(failedApp.staticTexts["source.status"].label.contains("synthetic-secret"))
    XCTAssertTrue(waitForFocus(on: failedTestConnection), "Failure status must not steal focus")
    failedApp.terminate()

    let m3uApp = launchSourceManagement(arguments: ["--ui-source-draft-m3u"])
    let m3uAddSource = m3uApp.buttons["sources.add"]
    XCTAssertTrue(m3uAddSource.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: m3uAddSource))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(m3uApp.textFields["source.name"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: m3uApp.textFields["source.name"]))
    XCUIRemote.shared.press(.down)
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: m3uApp.textFields["source.endpoint"]))
    XCTAssertTrue(m3uApp.textFields["source.epg-endpoint"].exists)
    XCTAssertTrue(m3uApp.staticTexts["source.m3u-limitation"].exists)
    XCTAssertFalse(m3uApp.secureTextFields["source.password"].exists)
  }

  func testSeededSourceRestoresFocusAndSupportsEnableRefreshDelete() {
    let app = launchSourceManagement(arguments: ["--ui-source-seeded"])
    let row = app.buttons["sources.row"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: row))

    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.textFields["source.name"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: app.textFields["source.name"]))
    XCTAssertTrue(app.staticTexts["Credential saved securely"].exists)
    XCTAssertFalse(app.secureTextFields["source.password"].exists)
    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: row))

    XCUIRemote.shared.press(.select)
    XCTAssertTrue(waitForFocus(on: app.textFields["source.name"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.textFields["source.endpoint"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["source.replace-credential"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["Manual only"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["source.save"]))
    XCUIRemote.shared.press(.left)
    XCTAssertTrue(waitForFocus(on: app.buttons["source.test"]))
    XCUIRemote.shared.press(.down)
    let enable = app.buttons["source.enable"]
    XCTAssertTrue(waitForFocus(on: enable))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(waitForLabel("Source disabled", on: app.staticTexts["source.status"]))
    XCTAssertTrue(waitForFocus(on: enable), "Enable state must not steal focus")
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(waitForLabel("Source enabled", on: app.staticTexts["source.status"]))
    XCTAssertTrue(waitForFocus(on: enable), "Enable state must not steal focus")
    XCUIRemote.shared.press(.right)
    let refresh = app.buttons["source.refresh"]
    XCTAssertTrue(waitForFocus(on: refresh))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(waitForLabel("Refresh completed", on: app.staticTexts["source.status"]))
    XCTAssertTrue(waitForFocus(on: refresh), "Refresh status must not steal focus")

    XCUIRemote.shared.press(.right)
    let delete = app.buttons["source.delete"]
    XCTAssertTrue(waitForFocus(on: delete))
    XCUIRemote.shared.press(.select)
    let confirmation = app.sheets.firstMatch
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    let focusedCancel = confirmation.buttons.matching(
      NSPredicate(format: "label == %@ AND hasFocus == true", "Cancel")
    ).firstMatch
    XCTAssertTrue(focusedCancel.exists)
    XCUIRemote.shared.press(.right)
    let focusedDelete = confirmation.buttons.matching(
      NSPredicate(format: "label == %@ AND hasFocus == true", "Delete")
    ).firstMatch
    XCTAssertTrue(focusedDelete.waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.staticTexts["sources.empty"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: app.buttons["sources.add"]))
  }

  func testArabicSourceManagementUsesLocalizedRTLChrome() {
    let app = launchSourceManagement(locale: "ar")

    XCTAssertTrue(app.buttons["sources.add"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["sources.add"].label, "إضافة مصدر")
    XCTAssertTrue(app.staticTexts["لا توجد مصادر بعد"].exists)
    XCTAssertTrue(waitForFocus(on: app.buttons["sources.add"]))

    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.textFields["source.name"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: app.textFields["source.name"]))
    XCTAssertEqual(app.buttons["source.test"].label, "اختبار الاتصال")
    XCTAssertEqual(app.buttons["source.save"].label, "حفظ")
    XCTAssertEqual(app.secureTextFields["source.password"].label, "كلمة المرور")
  }

  func testExistingSourceShowsSchedulingControlWithManualOnlyDefault() {
    let app = launchSourceManagement(arguments: ["--ui-source-seeded"])
    openSeededSource(in: app)

    XCTAssertTrue(app.staticTexts["source.refresh-policy-title"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["source.refresh-policy-title"].label, "Automatic Refresh")
    XCTAssertTrue(app.descendants(matching: .any)["source.refresh-policy"].exists)
    XCTAssertEqual(app.staticTexts["source.current-policy"].label, "Manual only")
    XCTAssertEqual(app.staticTexts["source.last-refreshed"].label, "Never refreshed")
    XCTAssertTrue(app.staticTexts["source.refresh-policy-explanation"].label.contains("active"))
  }

  func testAutomaticCadenceCanBeSelectedAndRemainsVisibleAfterReopening() {
    let app = launchSourceManagement(arguments: ["--ui-source-seeded"])
    let row = openSeededSource(in: app)
    focusSeededSourcePolicy(in: app)

    XCUIRemote.shared.press(.right)
    XCTAssertTrue(waitForFocus(on: app.buttons["Every 6 hours"]))
    XCUIRemote.shared.press(.right)
    XCTAssertTrue(waitForFocus(on: app.buttons["Every 12 hours"]))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(waitForLabel("Every 12 hours", on: app.staticTexts["source.current-policy"]))
    XCTAssertTrue(
      waitForFocus(on: app.buttons["Every 12 hours"]),
      "Changing scheduling status must not steal focus"
    )

    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["source.save"]))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: row))

    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.staticTexts["source.current-policy"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["source.current-policy"].label, "Every 12 hours")
  }

  func testDisabledAutomaticSourceCommunicatesPausedSchedulingWithoutTakingFocus() {
    let app = launchSourceManagement(
      arguments: ["--ui-source-seeded", "--ui-source-policy-6h", "--ui-source-disabled"]
    )
    openSeededSource(in: app)

    XCTAssertEqual(app.staticTexts["source.current-policy"].label, "Every 6 hours")
    XCTAssertEqual(
      app.staticTexts["source.schedule-paused"].label,
      "Automatic refresh is paused while this source is disabled."
    )
    XCTAssertTrue(waitForFocus(on: app.textFields["source.name"]))
  }

  func testArabicSchedulingControlsAreLocalized() {
    let app = launchSourceManagement(
      arguments: ["--ui-source-seeded", "--ui-source-policy-daily"],
      locale: "ar"
    )
    openSeededSource(in: app)

    XCTAssertEqual(app.staticTexts["source.refresh-policy-title"].label, "التحديث التلقائي")
    XCTAssertTrue(app.buttons["يدوي فقط"].exists)
    XCTAssertTrue(app.buttons["كل 6 ساعات"].exists)
    XCTAssertTrue(app.buttons["كل 12 ساعة"].exists)
    XCTAssertTrue(app.buttons["يوميًا"].exists)
    XCTAssertEqual(app.staticTexts["source.current-policy"].label, "يوميًا")
  }

  func testSchedulingAccessibilityDoesNotExposeSyntheticCredentialValues() {
    let app = launchSourceManagement(arguments: ["--ui-source-draft-xtream"])
    let addSource = app.buttons["sources.add"]
    XCTAssertTrue(addSource.waitForExistence(timeout: 10))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.staticTexts["source.refresh-policy-title"].waitForExistence(timeout: 5))

    let schedulingElements = [
      app.staticTexts["source.refresh-policy-title"],
      app.descendants(matching: .any)["source.refresh-policy"],
      app.staticTexts["source.refresh-policy-explanation"],
    ]
    for element in schedulingElements {
      let exposedText = "\(element.label) \(element.value ?? "")"
      XCTAssertFalse(exposedText.contains("synthetic-user"))
      XCTAssertFalse(exposedText.contains("synthetic-secret"))
    }
    XCTAssertFalse(app.secureTextFields["source.password"].label.contains("synthetic-secret"))
    XCTAssertFalse(
      (app.secureTextFields["source.password"].value as? String)?.contains("synthetic-secret")
        ?? false
    )
  }

  private func launchApp(arguments: [String] = [], locale: String = "en") -> XCUIApplication {
    let app = XCUIApplication()
    let isProductionFixture = arguments.contains {
      $0.hasPrefix("--ui-production-") || $0.hasPrefix("--ui-playback-")
        || $0.hasPrefix("--ui-continue-watching") || $0.hasPrefix("--ui-favorites")
    }
    app.launchArguments =
      (isProductionFixture ? arguments : ["--ui-demo-home"] + arguments)
      + localeLaunchArguments(locale)
    app.launch()
    return app
  }

  @discardableResult
  private func openProductionItem(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    let item = app.buttons["library.item.\(identifier)"]
    XCTAssertTrue(item.waitForExistence(timeout: 10))
    XCTAssertTrue(focusAndSelect(item, in: app))
    XCTAssertTrue(app.staticTexts["library.detail.title"].waitForExistence(timeout: 5))
    return item
  }

  private func launchSourceManagement(
    arguments: [String] = [],
    locale: String = "en"
  ) -> XCUIApplication {
    launchApp(
      arguments: ["--ui-source-management", "--ui-open-sources"] + arguments,
      locale: locale
    )
  }

  @discardableResult
  private func openSeededSource(in app: XCUIApplication) -> XCUIElement {
    let row = app.buttons["sources.row"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForFocus(on: row))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.textFields["source.name"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForFocus(on: app.textFields["source.name"]))
    return row
  }

  private func focusSeededSourcePolicy(in app: XCUIApplication) {
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.textFields["source.endpoint"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["source.replace-credential"]))
    XCUIRemote.shared.press(.down)
    XCTAssertTrue(waitForFocus(on: app.buttons["Manual only"]))
  }

  private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
    let predicate = NSPredicate(format: "label == %@", label)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
  }

  private func waitForValue(_ value: String, on element: XCUIElement) -> Bool {
    let predicate = NSPredicate(format: "value == %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
  }

  private func localeLaunchArguments(_ locale: String) -> [String] {
    return ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
  }

  private func waitForFocus(on element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let predicate = NSPredicate(format: "hasFocus == true")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func focusDiagnostics(in app: XCUIApplication) -> String {
    let focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasFocus == true"))
      .allElementsBoundByIndex
      .map { "type=\($0.elementType.rawValue) id=\($0.identifier) label=\($0.label)" }
    return
      "Focused elements: \(focused.isEmpty ? ["none"] : focused). Hierarchy: \(app.debugDescription)"
  }

  @discardableResult
  private func focusAndSelect(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maximumPresses: Int = 24
  ) -> Bool {
    guard element.waitForExistence(timeout: 5) else { return false }
    if !element.hasFocus {
      for _ in 0..<maximumPresses where !element.hasFocus {
        let focused = app.descendants(matching: .any).matching(
          NSPredicate(format: "hasFocus == true")
        ).firstMatch
        guard focused.exists else { return false }

        let currentCenter = CGPoint(x: focused.frame.midX, y: focused.frame.midY)
        let targetCenter = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let horizontalDistance = targetCenter.x - currentCenter.x
        let verticalDistance = targetCenter.y - currentCenter.y
        let direction: XCUIRemote.Button
        if abs(verticalDistance) > 40 {
          direction = verticalDistance < 0 ? .up : .down
        } else {
          direction = horizontalDistance < 0 ? .left : .right
        }
        XCUIRemote.shared.press(direction)
        _ = waitForFocus(on: element, timeout: 0.15)
      }
    }
    guard element.hasFocus else { return false }
    XCUIRemote.shared.press(.select)
    return true
  }
}
