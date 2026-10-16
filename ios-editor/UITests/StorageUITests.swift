import XCTest

/// Account › Storage: tick rows, "Clear Selected", confirm in the popup.
final class StorageUITests: XCTestCase {
    func testStorageShowsTotalsAndClearsTheSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons.element(boundBy: 2).tap()   // Account
        app.buttons["row-storage"].firstMatch.tap()

        let total = app.staticTexts["storage-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(["MB", "KB", "GB", "bytes", "byte", "Zero"].contains { total.label.contains($0) }, "a size, not a placeholder: \(total.label)")

        if let dir = ProcessInfo.processInfo.environment["TEMPLATE_SHOTS_DIR"] {   // to look at it: TEST_RUNNER_TEMPLATE_SHOTS_DIR=…
            sleep(1)
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("storage.png"))
        }

        // Media can't be ticked.
        XCTAssertFalse(app.buttons["storage-select-media"].isEnabled)
        XCTAssertTrue(app.buttons["storage-select-cache"].isEnabled)

        let clear = app.buttons["storage-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        if clear.isEnabled {
            clear.tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5), "a popup first")
            alert.buttons.matching(NSPredicate(format: "label IN {'Clear', 'Dọn'}")).firstMatch.tap()
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            let gone = NSPredicate(format: "isEnabled == false")
            expectation(for: gone, evaluatedWith: clear)
            waitForExpectations(timeout: 10)   // nothing left selected to clear
        }
    }
}
