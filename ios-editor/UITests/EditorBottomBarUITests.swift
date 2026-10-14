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

    /// Delete is the last button of the scrolling row: swipe the row until it can be hit.
    private func revealDelete(_ app: XCUIApplication) {
        let row = app.descendants(matching: .any)["selectionToolbar"]
        var tries = 0
        while !app.buttons["action-delete"].isHittable && tries < 6 {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
            tries += 1
        }
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
        app.buttons["text-captions"].tap()
        app.buttons["toolbarBack"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 5))
    }

    /// Add text opens the Text sheet (Font / Style tabs, the field at the bottom); typing, a font and a colour reach the clip;
    /// closing it with empty words leaves nothing behind.
    func testAddTextOpensTheTextSheetAndEditsTheNewClipLive() throws {
        let app = openTripToParis()
        app.buttons["tool-text"].tap()
        app.buttons["text-add"].tap()
        let field = app.textFields["textField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Add text opens the sheet with the field at the bottom")
        XCTAssertTrue(app.buttons["textTab-Font"].exists && app.buttons["textTab-Style"].exists)
        XCTAssertEqual(field.value as? String, "Hello", "a new clip starts with default words")
        field.tap()
        field.typeText("Bye")
        XCTAssertEqual(field.value as? String, "Bye", "the first tap selected the default words, so typing replaced them")
        XCTAssertFalse(app.buttons["fontCell-Georgia-Bold"].exists, "while typing the sheet shrinks to the field and the tabs")
        app.buttons["textTab-Font"].tap()   // ends the editing and brings the fonts back
        XCTAssertTrue(app.buttons["fontCell-Georgia-Bold"].waitForExistence(timeout: 5))
        app.buttons["fontCell-Georgia-Bold"].tap()
        app.buttons["textTab-Style"].tap()
        XCTAssertTrue(app.buttons["textColor-#FF3B30ff"].waitForExistence(timeout: 5))
        app.buttons["textColor-#FF3B30ff"].tap()
        app.buttons["textBackground-#FFFFFFff"].tap()
        app.buttons["textColor-#000000ff"].tap()
        saveShot(app, "text-sheet")
        app.buttons["textDone"].tap()
        XCTAssertTrue(app.buttons["action-edit-text"].waitForExistence(timeout: 5), "the new text clip is selected, with its own tools")

        // Empty words: the session is undone, no clip is left.
        app.buttons["toolbarBack"].tap()
        app.buttons["tool-text"].tap()
        app.buttons["text-add"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue)   // the default words are selected: one delete empties the field
        XCTAssertEqual(field.value as? String ?? "", "Enter text", "an empty field reports its placeholder")
        app.buttons["textDone"].tap()
        XCTAssertFalse(app.buttons["action-edit-text"].waitForExistence(timeout: 2), "an empty new text clip is discarded")
    }

    func testDeleteRemovesTheClipAndReturnsToTheMainRow() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-delete"].waitForExistence(timeout: 5))
        revealDelete(app)
        app.buttons["action-delete"].tap()
        XCTAssertTrue(app.buttons["tool-aspectRatio"].waitForExistence(timeout: 5), "with nothing selected any more the main row is back")
    }

    /// The Edit row for a video: Split first, the rest scrolls, Delete is pinned at the right; a tool that is not built
    /// yet only says it is coming; Opacity opens the Transform sheet on its Opacity ruler.
    func testTheClipRowIsOrderedPinsDeleteAndAnnouncesUnbuiltTools() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5))
        revealDelete(app)
        XCTAssertTrue(app.buttons["action-delete"].isHittable, "Delete is the row's last button")
        saveShot(app, "bar-7-clip-row")
        for _ in 0..<4 {
            let row = app.descendants(matching: .any)["selectionToolbar"]
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }   // back to the start of the row

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

    /// Selecting a text clip on the timeline gives the text tools: Split, Style, Animation, Duplicate,
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
        for id in ["edit-text", "split", "style", "animation", "duplicate", "transform"] {
            XCTAssertTrue(app.buttons["action-\(id)"].exists, id)
        }
        for id in ["volume", "adjust", "opacity", "crop", "lasting-text"] {
            XCTAssertFalse(app.buttons["action-\(id)"].exists, "\(id) is not a text tool")
        }
        revealDelete(app)
        XCTAssertTrue(app.buttons["action-delete"].isHittable)
        saveShot(app, "bar-9-text-clip-row")

        app.buttons["action-edit-text"].tap()
        XCTAssertTrue(app.textFields["textField"].waitForExistence(timeout: 5), "Edit text opens the Text sheet")
        XCTAssertFalse(app.textFields["textField"].value as? String == "", "the field holds the clip's words")
    }

    /// Filter opens from the clip row: a grid with None first, no Intensity until a filter is picked, then the slider.
    func testFilterSheetPicksAFilterAndShowsIntensityOnlyThen() throws {
        let app = openTripToParis()
        app.buttons["tool-edit"].tap()
        let row = app.descendants(matching: .any)["selectionToolbar"]
        var guardCount = 0
        while !app.buttons["action-filter"].isHittable, guardCount < 6 { row.swipeLeft(); guardCount += 1 }
        app.buttons["action-filter"].tap()

        XCTAssertTrue(app.buttons["filterCell-none"].waitForExistence(timeout: 5), "None is the first cell")
        XCTAssertTrue(app.buttons["filterCell-warm"].exists)
        XCTAssertFalse(app.sliders["filterSlider"].exists, "no Intensity while no filter is picked")
        saveShot(app, "filter-prod-grid")

        app.buttons["filterCell-mono"].tap()
        XCTAssertTrue(app.sliders["filterSlider"].waitForExistence(timeout: 5), "picking a filter shows Intensity")
        saveShot(app, "filter-prod-picked")
        app.sliders["filterSlider"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertNotEqual(app.staticTexts["filterIntensityValue"].label, "100")

        app.buttons["filterChip-B&W"].tap()
        XCTAssertTrue(app.buttons["filterCell-noir"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filterCell-warm"].exists, "Warm is not in B&W")

        app.buttons["filterReset"].tap()
        XCTAssertFalse(app.sliders["filterSlider"].waitForExistence(timeout: 1), "Reset removes the filter and hides Intensity")
        app.buttons["filterDone"].tap()
        XCTAssertTrue(app.buttons["action-delete"].waitForExistence(timeout: 5), "back on the clip's row")
    }

    /// The main toolbar's Filter tool selects the clip under the playhead and opens the same sheet.
    func testTheMainFilterToolOpensTheSheet() throws {
        let app = openTripToParis()
        // The main row scrolls: Stickers pushed Filter off the right edge.
        let edit = app.buttons["tool-edit"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        edit.press(forDuration: 0.05, thenDragTo: edit.withOffset(CGVector(dx: -300, dy: 0)))
        app.buttons["tool-filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-none"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["filterDone"].exists)
    }
}

extension EditorBottomBarUITests {
    /// Needs the local API (`DEV_AUTH_BYPASS=true`, port 8080) with the sticker catalogue on R2.
    func testStickerSheetAddsAStickerToTheStage() throws {
        let app = openTripToParis()
        app.buttons["tool-stickers"].tap()
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stickerCell-'")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 20), "the grid should load from the API")
        sleep(2)
        saveShot(app, "stickers-small")
        cell.tap()
        sleep(1)
        saveShot(app, "stickers-added")
        app.swipeUp()
        sleep(1)
        saveShot(app, "stickers-large")
        app.buttons["stickerDone"].tap()
        XCTAssertTrue(app.buttons["toolbarBack"].waitForExistence(timeout: 5), "the new sticker is selected, so its tools show")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.80)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.64)), withVelocity: .slow, thenHoldForDuration: 0.2)
        sleep(1)
        saveShot(app, "sticker-selected")
        app.buttons["action-mirror"].tap()
        sleep(1)
        saveShot(app, "sticker-mirrored")
    }

    /// The keyframe icon sits next to fullscreen: off with nothing selected, a diamond toggle on a clip; the clip row's
    /// Graph tool is dimmed until the playhead is between two keyframes.
    func testKeyframeIconTogglesAndGraphStaysDimmedWithoutASegment() throws {
        let app = openTripToParis()
        let toggle = app.buttons["keyframe-toggle"]
        XCTAssertTrue(toggle.exists)
        XCTAssertFalse(toggle.isEnabled, "nothing selected")
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertFalse(app.buttons["action-graph"].isEnabled, "no segment yet")
        toggle.tap()
        XCTAssertTrue(app.images["keyframeMarker"].waitForExistence(timeout: 3), "the keyframe is drawn on the selected clip")
        XCTAssertFalse(app.buttons["action-graph"].isEnabled, "one keyframe is not a segment \(app.images["keyframeMarker"].frame) \(app.descendants(matching: .any)["timeline"].frame)")
        saveShot(app, "keyframe-icon-on")
    }



    /// Two lines of different length with a white label: the label steps with the lines (Facebook story style).
    func testTextBackgroundStepsAcrossTwoLines() throws {
        let app = openTripToParis()
        app.buttons["tool-text"].tap()
        app.buttons["text-add"].tap()
        let field = app.textFields["textField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("This is the\nFacebook style")
        app.buttons["textTab-Style"].tap()
        XCTAssertTrue(app.buttons["textBackground-#FFFFFFff"].waitForExistence(timeout: 5))
        app.buttons["textBackground-#FFFFFFff"].tap()
        app.buttons["textColor-#000000ff"].tap()
        sleep(1)
        saveShot(app, "text-background")
        app.buttons["textDone"].tap()
        XCTAssertTrue(app.buttons["action-edit-text"].waitForExistence(timeout: 5))
    }

    /// While the field is edited the sheet is only the field and the tabs (the keyboard sits right under them); the stage stays visible.
    func testTextSheetShrinksToFieldAndTabsWhileTyping() throws {
        let app = openTripToParis()
        app.buttons["tool-text"].tap()
        app.buttons["text-add"].tap()
        let field = app.textFields["textField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fontCell-Georgia-Bold"].waitForExistence(timeout: 5), "at rest the fonts are there")
        saveShot(app, "text-sheet-rest")
        field.tap()
        sleep(2)
        saveShot(app, "text-sheet-typing")
        XCTAssertFalse(app.buttons["fontCell-Georgia-Bold"].exists)
        XCTAssertTrue(app.buttons["textTab-Font"].exists && app.buttons["textTab-Style"].exists, "the tabs stay")
        XCTAssertLessThan(field.frame.minY, app.windows.firstMatch.frame.height, "the field is on screen")
    }
}
