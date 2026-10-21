import XCTest

/// Templates and credit top-ups are currently hidden from the app's user-facing navigation.
final class TemplateFlowUITests: XCTestCase {
    func testPlusOpensMediaPickerAndCreatesAnEditorProject() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let createButton = app.buttons["createProjectButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.tap()

        let grid = app.descendants(matching: .any)["mediaPickerGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "The plus button opens the photo and video library")
        XCTAssertTrue(app.staticTexts["New project"].exists)
        let addSelected = app.buttons["mediaPickerAddSelected"]
        XCTAssertTrue(addSelected.exists)
        XCTAssertFalse(addSelected.isEnabled, "A project is created after selecting media")

        let firstAsset = app.buttons.matching(identifier: "assetCell").firstMatch
        guard firstAsset.waitForExistence(timeout: 5) else {
            throw XCTSkip("The simulator photo library is empty; add a photo or video to exercise project creation.")
        }
        firstAsset.tap()
        XCTAssertTrue(addSelected.isEnabled)
        addSelected.tap()

        XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 20), "After import, the new project opens directly in the editor")
        let importedClip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "timelineClip-main-"))
            .firstMatch
        XCTAssertTrue(importedClip.waitForExistence(timeout: 10), "The selected media is the first clip in the new project")
    }

    func testTemplateAndCreditEntryPointsAreHiddenAndDonateIsAvailable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertTrue(app.tabBars.buttons["Folder"].exists)
        XCTAssertTrue(app.tabBars.buttons["Account"].exists)
        XCTAssertFalse(app.tabBars.buttons["Home"].exists, "the template catalogue tab is hidden")

        app.tabBars.buttons["Account"].tap()
        XCTAssertFalse(app.staticTexts["Credits"].exists, "credit balance and top-up entry points are hidden")
        let donate = app.descendants(matching: .any)["row-donate"]
        XCTAssertTrue(donate.waitForExistence(timeout: 10))
        donate.tap()
        XCTAssertTrue(app.navigationBars["Donate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Support Neonix"].exists)
    }
}
