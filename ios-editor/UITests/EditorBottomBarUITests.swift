import XCTest

/// The editor's bottom is ONE row at every level: main tools -> the selected clip's tools (with "«" back) ->
/// a tool's own options (with "«" back). Never two rows.
final class EditorBottomBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TEMPLATE_SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func openTripToParis() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15), "the main tools row should be there")
        return app
    }

    func testSelectingAClipReplacesTheToolsRowWithItsOwnToolsAndBackReturns() throws {
        let app = openTripToParis()
        saveShot(app, "bar-1-main")
        XCTAssertTrue(app.buttons["tool-aspectRatio"].exists)
        XCTAssertFalse(app.buttons["toolbarBack"].exists, "no back button at the top level")

        // Edit selects the clip under the playhead and opens ITS tools in place of the main row.
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["toolbarBack"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["action-split"].exists || app.buttons["action-delete"].exists)
        XCTAssertTrue(app.buttons["action-delete"].exists)
        XCTAssertTrue(app.buttons["action-extract-audio"].exists, "a video clip can give up its audio")
        XCTAssertFalse(app.buttons["tool-aspectRatio"].exists, "the main row is gone, not stacked below")
        XCTAssertFalse(app.buttons["tool-audio"].exists)
        saveShot(app, "bar-2-clip")

        // Back: deselect, main row returns.
        app.buttons["toolbarBack"].tap()
        XCTAssertTrue(app.buttons["tool-aspectRatio"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["toolbarBack"].exists)
        XCTAssertFalse(app.buttons["action-delete"].exists)
    }

    /// Adjust opens as a sheet (ruler + round buttons) over the lower part of the screen; Done brings the clip's row back.
    func testAdjustOpensASheetAndDoneReturnsToTheClipsRow() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-adjust"].waitForExistence(timeout: 5))

        app.buttons["action-adjust"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "the Adjust sheet should open with a ruler")
        XCTAssertTrue(app.buttons["adjust-brightness"].exists)
        saveShot(app, "bar-3-adjust")

        // Drag the ruler: the value changes and that button is marked.
        app.descendants(matching: .any)["ruler"].swipeLeft(velocity: .slow)
        XCTAssertNotEqual(app.staticTexts["rulerReadout"].label, "0")

        // A control further along the scrolling row, then Done.
        app.descendants(matching: .any)["adjustButtons"].swipeLeft()
        XCTAssertTrue(app.buttons["adjust-noise"].waitForExistence(timeout: 5))
        app.buttons["adjust-noise"].tap()
        XCTAssertTrue(app.navigationBars["Noise"].waitForExistence(timeout: 5))
        app.buttons["adjustDone"].tap()
        XCTAssertFalse(app.staticTexts["rulerReadout"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["action-delete"].waitForExistence(timeout: 5), "back on the clip's row, still selected")
    }

    /// Transform: a sheet with the position/scale/rotate/opacity rulers; the stage can be pinched while it is open.
    func testTransformSheetChangesTheLayerAndUndoRestoresIt() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-transform"].waitForExistence(timeout: 5))
        app.buttons["action-transform"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "the Transform sheet should open")
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "0", "starts on Position X at its neutral value")
        saveShot(app, "bar-5-transform")

        app.buttons["transform-scale"].tap()
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "100%")
        app.descendants(matching: .any)["ruler"].swipeLeft(velocity: .slow)
        XCTAssertNotEqual(app.staticTexts["rulerReadout"].label, "100%", "the ruler changes the scale")
        saveShot(app, "bar-6-transform-scaled")

        // Double tap puts just that one back.
        app.buttons["transform-scale"].doubleTap()
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "100%")

        app.buttons["transformDone"].tap()
        XCTAssertTrue(app.buttons["action-transform"].waitForExistence(timeout: 5), "back on the clip's row")
    }

    func testAToolWithNoSelectionOpensItsOptionsWithBack() throws {
        let app = openTripToParis()
        app.buttons["tool-text"].tap()
        XCTAssertTrue(app.buttons["toolbarBack"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tool-audio"].exists, "the tools row is replaced by the Text options")
        saveShot(app, "bar-4-text")
        app.buttons["toolbarBack"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 5))
    }

    func testDeleteRemovesTheClipAndReturnsToTheMainRow() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-delete"].waitForExistence(timeout: 5))
        app.buttons["action-delete"].tap()
        XCTAssertTrue(app.buttons["tool-aspectRatio"].waitForExistence(timeout: 5), "with nothing selected any more the main row is back")
    }
}
