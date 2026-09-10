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

    let savedRow = app.buttons[
      "sources.row.00000000-0000-0000-0000-000000000102"
    ]
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
    XCTAssertTrue(m3uApp.staticTexts["source.m3u-limitation"].exists)
    XCTAssertFalse(m3uApp.secureTextFields["source.password"].exists)
  }

  func testSeededSourceRestoresFocusAndSupportsEnableRefreshDelete() {
    let app = launchSourceManagement(arguments: ["--ui-source-seeded"])
    let row = app.buttons["sources.row.00000000-0000-0000-0000-000000000101"]
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
    app.launchArguments = arguments + localeLaunchArguments(locale)
    app.launch()
    return app
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
    let row = app.buttons["sources.row.00000000-0000-0000-0000-000000000101"]
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

  private func localeLaunchArguments(_ locale: String) -> [String] {
    return ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
  }

  private func waitForFocus(on element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let predicate = NSPredicate(format: "hasFocus == true")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }
}
