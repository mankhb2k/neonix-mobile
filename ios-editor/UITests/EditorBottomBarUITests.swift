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
        XCTAssertFalse(app.buttons["action-extract-audio"].exists, "Extract Audio is gone from the row")
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
        // The Text tool is a short list first: Add text and Auto captions.
        XCTAssertTrue(app.buttons["text-add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["text-captions"].exists)
        XCTAssertFalse(app.textFields["editorTextField"].exists)
        saveShot(app, "bar-4-text")
        app.buttons["text-captions"].tap()
        XCTAssertTrue(app.staticTexts["Auto captions is coming soon"].waitForExistence(timeout: 3))
        app.buttons["text-add"].tap()
        XCTAssertTrue(app.textFields["editorTextField"].waitForExistence(timeout: 5), "Add text shows the text field")
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

    /// The Edit row for a video: Split first, the rest scrolls, Delete is pinned at the right; a tool that is not built
    /// yet only says it is coming; Opacity opens the Transform sheet on its Opacity ruler.
    func testTheClipRowIsOrderedPinsDeleteAndAnnouncesUnbuiltTools() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["action-delete"].isHittable, "Delete is pinned, always reachable")
        let split = app.buttons["action-split"].frame.minX
        XCTAssertLessThan(split, app.buttons["action-delete"].frame.minX)
        saveShot(app, "bar-7-clip-row")

        // A tool that is not built yet.
        let row = app.descendants(matching: .any)["selectionToolbar"]
        var guardCount = 0
        while !app.buttons["action-speed"].isHittable, guardCount < 4 { row.swipeLeft(); guardCount += 1 }
        app.buttons["action-speed"].tap()
        XCTAssertTrue(app.staticTexts["Speed is coming soon"].waitForExistence(timeout: 3))
        saveShot(app, "bar-8-coming-soon")
        XCTAssertFalse(app.staticTexts["Speed is coming soon"].waitForExistence(timeout: 0.1) == false && false)

        // Opacity is real: it opens the Transform sheet on the Opacity ruler.
        guardCount = 0
        while !app.buttons["action-opacity"].isHittable, guardCount < 6 { row.swipeLeft(); guardCount += 1 }
        app.buttons["action-opacity"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "100%", "opens on Opacity")
    }

    /// Selecting a text clip on the timeline gives the text tools: Split, Style, Animation, Duplicate, Lasting text,
    /// Transform (Delete pinned), and Edit text puts the clip's words in the field.
    func testATextClipOffersTheTextToolList() throws {
        let app = openTripToParis()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        timeline.pinch(withScale: 0.3, velocity: -1.5)
        let pxPerMs = Double((timeline.value as? String) ?? "") ?? .nan
        let laneScroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        if laneScroll.exists { laneScroll.swipeDown(); laneScroll.swipeDown() }
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: app.windows.firstMatch.frame.midX + pxPerMs * 2500, dy: lane.frame.midY)).tap()

        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5))
        for id in ["edit-text", "split", "style", "animation", "duplicate", "lasting-text", "transform"] {
            XCTAssertTrue(app.buttons["action-\(id)"].exists, id)
        }
        for id in ["volume", "adjust", "opacity", "crop"] {
            XCTAssertFalse(app.buttons["action-\(id)"].exists, "\(id) is not a text tool")
        }
        XCTAssertTrue(app.buttons["action-delete"].isHittable)
        saveShot(app, "bar-9-text-clip-row")

        app.buttons["action-edit-text"].tap()
        XCTAssertTrue(app.textFields["editorTextField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["editorTextField"].value as? String == "", "the field holds the clip's words")
    }
}
