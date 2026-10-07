import XCTest

/// Real tap-driven UI tests, using `XCUIApplication` (Accessibility-driven
/// touch injection) — unlike every other verification method used in this
/// project (`xcodebuild build`/`test`, `simctl io screenshot`), this is the
/// only one that actually simulates a real touch, the same way a person
/// tapping the screen would. Added 2026-10-07 after a real bug
/// (`PreviewCanvas`'s `GeometryReader`+`.scaleEffect` combo silently
/// absorbing taps meant for `EditorShellView`'s `Huỷ`/`Xuất` buttons,
/// fixed via `.allowsHitTesting(false)` — see that file's doc comment) was
/// found only by adding this test and eliminating variables one at a time,
/// never by reasoning about a screenshot — `simctl` itself has no tap/touch
/// injection, so nothing before this test could have caught it. This test
/// closes that gap going forward: any future regression in Folder → Editor
/// → dismiss navigation fails a real tap-based test, not just a build or a
/// static screenshot.
final class EditorNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Waits for `element` to leave the accessibility tree, instead of
    /// asserting `!element.exists` immediately after a tap — `fullScreenCover`
    /// dismisses with an animation, during which the outgoing content can
    /// still legitimately exist for a few hundred ms while the view
    /// underneath is already revealed. An instant check after the tap is a
    /// race condition, not a real test of the app.
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element) should disappear within \(timeout)s")
    }

    /// Opens `projectName` from the Folder tab and taps `Huỷ`, asserting the
    /// Editor actually dismisses back to the project list — the behavior
    /// that silently failed for 2 of 3 sample compositions before
    /// `.allowsHitTesting(false)` was added to `PreviewCanvas`'s embedding.
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
