import XCTest

@MainActor
final class AEVYNOTVUITests: XCTestCase {
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

  private func launchApp(arguments: [String] = [], locale: String = "en") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments + localeLaunchArguments(locale)
    app.launch()
    return app
  }

  private func localeLaunchArguments(_ locale: String) -> [String] {
    return ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
  }

  private func waitForFocus(on element: XCUIElement) -> Bool {
    let predicate = NSPredicate(format: "hasFocus == true")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
  }
}
