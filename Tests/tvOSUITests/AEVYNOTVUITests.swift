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
    let playbackNotice = app.alerts["Playback comes later"]
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

  private func launchApp(arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
    return app
  }

  private func waitForFocus(on element: XCUIElement) -> Bool {
    let predicate = NSPredicate(format: "hasFocus == true")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
  }
}
