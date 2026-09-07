import XCTest

@MainActor
final class AEVYNOTVUITests: XCTestCase {
    func testHomeLaunchesWithInitialFocusAndMovesRight() {
        let app = XCUIApplication()
        app.launch()

        let firstCard = app.buttons["home.card.continue-orbit"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(on: firstCard), "The initial media card should receive focus")

        XCUIRemote.shared.press(.right)

        let secondCard = app.buttons["home.card.continue-harbor"]
        XCTAssertTrue(waitForFocus(on: secondCard), "Right navigation should move focus to the next card")
    }

    private func waitForFocus(on element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "hasFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
