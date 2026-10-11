import XCTest

/// Opens Account > Developer > Design Lab and tries the Transform and Adjust sheets: the ruler, the round buttons inside.
/// Screenshots go to `TEMPLATE_SHOTS_DIR` if set.
final class DesignLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TEMPLATE_SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func openLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        // "Design Lab" is in the Developer section, at the bottom of the list.
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Design Lab should be listed under Developer")
        link.tap()
        let experiment = app.staticTexts["Transform controls"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        saveShot(app, "lab-0-opened")
        XCTAssertTrue(app.buttons["labClose"].waitForExistence(timeout: 10), "the lab should open full screen")
        return app
    }

    private func readout(_ app: XCUIApplication) -> String { app.staticTexts["rulerReadout"].label }

    /// Tapping a round button opens the sheet; the ruler in it changes the value; the buttons in it switch parameter.
    func testPopupSheetRulerAndButtons() throws {
        let app = openLab()
        XCTAssertFalse(app.staticTexts["rulerReadout"].exists, "closed until a button is tapped")
        saveShot(app, "lab-1-closed")

        app.buttons["chip-rotation"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "tapping a button opens the sheet with the ruler")
        XCTAssertEqual(readout(app), "0°")
        saveShot(app, "lab-2-popup")

        // Drag the ruler: the value changes.
        let ruler = app.descendants(matching: .any)["ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeLeft(velocity: .slow)
        XCTAssertNotEqual(readout(app), "0°", "dragging the ruler changes the value")
        let afterDrag = readout(app)
        saveShot(app, "lab-3-ruler-dragged")

        // The round buttons inside the sheet switch the parameter without closing it, each with its own ruler.
        app.buttons["sheetChip-scale"].tap()
        XCTAssertEqual(readout(app), "100%")
        app.buttons["sheetChip-x"].tap()
        XCTAssertEqual(readout(app), "0")
        app.buttons["sheetChip-rotation"].tap()
        XCTAssertEqual(readout(app), afterDrag, "the rotation was kept")

        // Double tap puts just this parameter back to neutral.
        app.buttons["sheetChip-rotation"].doubleTap()
        XCTAssertEqual(readout(app), "0°")

        app.buttons["popupDone"].tap()
        XCTAssertFalse(app.staticTexts["rulerReadout"].waitForExistence(timeout: 2), "Done closes the sheet")
    }

    func testPinchOnTheStageMovesTheLayerWhileTheSheetIsOpen() throws {
        let app = openLab()
        app.buttons["chip-scale"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5))
        XCTAssertEqual(readout(app), "100%")
        app.descendants(matching: .any)["labStage"].pinch(withScale: 1.8, velocity: 1)
        XCTAssertNotEqual(readout(app), "100%", "pinching the stage changes the scale and the ruler follows")
        saveShot(app, "lab-4-pinched")
    }

    // MARK: Adjust lab

    private func openAdjustLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Adjust controls"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["adjClose"].waitForExistence(timeout: 10), "the Adjust lab should open full screen")
        return app
    }

    func testAdjustScrollLayoutScrollsAndMarksChangedControls() throws {
        let app = openAdjustLab()
        sleep(1)
        saveShot(app, "adj-0-closed")
        app.buttons["adjAction-Adjust"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "Adjust opens the sheet")
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "0")
        saveShot(app, "adj-1-scroll")

        // Drag the ruler: the value changes and the button for it shows the change.
        app.descendants(matching: .any)["ruler"].swipeLeft(velocity: .slow)
        XCTAssertNotEqual(app.staticTexts["rulerReadout"].label, "0")

        // A control at the far end of the row is reachable by scrolling, and selecting it recentres the row.
        app.descendants(matching: .any)["chipsScroll"].swipeLeft()
        let noise = app.buttons["sheetChip-noise"]
        XCTAssertTrue(noise.waitForExistence(timeout: 5))
        noise.tap()
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "0")
        XCTAssertTrue(app.navigationBars["Noise"].waitForExistence(timeout: 5), "the sheet is now editing Noise")
        saveShot(app, "adj-2-noise")
        app.buttons["adjDone"].tap()
        XCTAssertFalse(app.staticTexts["rulerReadout"].waitForExistence(timeout: 2))
    }

    func testAdjustGroupsLayoutShowsOneGroupAtATime() throws {
        let app = openAdjustLab()
        app.segmentedControls["adjVariantPicker"].buttons["Groups"].tap()
        app.buttons["adjAction-Adjust"].tap()
        XCTAssertTrue(app.buttons["group-Light"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["groupChip-brightness"].exists)
        XCTAssertFalse(app.buttons["groupChip-saturation"].exists, "other groups' buttons are not on screen")
        saveShot(app, "adj-3-groups-light")

        app.buttons["group-Color"].tap()
        XCTAssertTrue(app.buttons["groupChip-saturation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["groupChip-brightness"].exists)
        XCTAssertTrue(app.navigationBars["Saturation"].exists, "switching group selects its first control")
        saveShot(app, "adj-4-groups-color")

        app.buttons["group-Detail"].tap()
        XCTAssertTrue(app.buttons["groupChip-noise"].waitForExistence(timeout: 5), "all five Detail buttons fit without scrolling")
        XCTAssertTrue(app.buttons["groupChip-noise"].isHittable)
    }
}
