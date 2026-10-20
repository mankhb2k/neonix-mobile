import XCTest

/// The main row has no Effects tool for now (the feature comes later).
final class NavToolsUITests: XCTestCase {
    func testTheMainRowHidesEffects() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        for id in ["tool-audio", "tool-text", "tool-stickers", "tool-filter"] { XCTAssertTrue(app.buttons[id].exists, id) }
        XCTAssertFalse(app.buttons["tool-effects"].exists, "Effects is hidden")
    }
}
