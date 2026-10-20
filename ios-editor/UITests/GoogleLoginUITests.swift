import XCTest

final class GoogleLoginUITests: XCTestCase {
    func testGoogleSignInButtonUsesFullContentWidth() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons.element(boundBy: 2).tap() // Account
        app.buttons["account-sign-in-entry"].tap()
        app.buttons["account-sign-in-cta"].tap()

        let googleButton = app.buttons["google-sign-in-button"]
        XCTAssertTrue(googleButton.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(googleButton.frame.width, app.frame.width * 0.65)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Google sign-in button on iPhone 17"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
