import XCTest

/// Real tap-driven UI tests (`XCUIApplication`) — the only verification
/// method here that synthesizes an actual touch; see `ui-design-note.md`
/// (repo root) for the hit-testing bug this was built to catch.
final class EditorNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Waits for `element` to leave the tree — an instant `!element.exists`
    /// check right after a tap is a race against the dismiss animation.
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element) should disappear within \(timeout)s")
    }

    /// Opens `projectName` from Folder, taps `Huỷ`, asserts it dismisses.
    private func assertCancelReturnsToFolder(projectName: String) {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Folder"].tap()

        let projectRow = app.staticTexts[projectName]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "Folder tab should list the placeholder sample projects")
        projectRow.tap()

        let cancelButton = app.buttons["Huỷ"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "EditorShellView's Huỷ button should appear after opening a project")
        cancelButton.tap()

        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "Tapping Huỷ should dismiss back to the Folder project list")
        waitForDisappearance(of: cancelButton)
    }

    func testCancelButtonReturnsToFolderFor9x16Composition() {
        assertCancelReturnsToFolder(projectName: "Trip to Paris")
    }

    func testCancelButtonReturnsToFolderFor16x9Composition() {
        assertCancelReturnsToFolder(projectName: "Product Launch")
    }

    func testCancelButtonReturnsToFolderForSquareComposition() {
        assertCancelReturnsToFolder(projectName: "Birthday Recap")
    }
}
