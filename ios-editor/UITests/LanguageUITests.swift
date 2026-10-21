import XCTest

/// Account › Language switches the app's text at runtime (no restart).
final class LanguageUITests: XCTestCase {
    private func openLanguage(_ app: XCUIApplication) {
        // The row reads "Language" or "Ngôn ngữ" depending on what an earlier run left stored.
        let row = app.staticTexts.matching(NSPredicate(format: "label IN {'Language', 'Ngôn ngữ'}")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
    }

    func testSwitchToVietnameseAndBack() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons.element(boundBy: 1).tap()   // Account (its label is translated)

        // A known start: English.
        openLanguage(app)
        app.buttons["language-english"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))

        openLanguage(app)
        app.buttons["language-vietnamese"].tap()
        XCTAssertTrue(app.navigationBars["Ngôn ngữ"].waitForExistence(timeout: 5), "the title should now be Vietnamese")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Giao diện"].waitForExistence(timeout: 5), "Appearance row should read Giao diện")
        app.staticTexts["Trung tâm trợ giúp"].tap()
        XCTAssertTrue(app.staticTexts["Làm sao để cắt hoặc chia một clip?"].waitForExistence(timeout: 5)
                      || app.buttons["Làm sao để cắt hoặc chia một clip?"].waitForExistence(timeout: 2),
                      "the help center only lists currently available editor features")

        app.navigationBars.buttons.firstMatch.tap()
        openLanguage(app)
        app.buttons["language-english"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 5))
    }
}
