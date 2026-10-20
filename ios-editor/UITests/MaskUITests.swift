import XCTest

/// Mask on a selected video clip: the clip row's Mask replaces the bottom row with the shapes; a tap on a shape applies it (handles on the stage), a tap on the
/// picked shape opens the popup, the popup edits it live, and None takes it away.
final class MaskUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openMask(_ app: XCUIApplication) {
        let row = app.descendants(matching: .any)["selectionToolbar"]
        for _ in 0..<6 where !app.buttons["action-mask"].isHittable { row.swipeLeft() }
        app.buttons["action-mask"].tap()
        XCTAssertTrue(app.buttons["maskShape-circle"].waitForExistence(timeout: 5), "the shapes replace the row")
    }

    func testMaskShapesApplyOnTheStageAndThePickedShapeOpensThePopup() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        app.buttons["tool-edit"].tap()   // selects the clip under the playhead
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }

        openMask(app)
        for shape in ["none", "horizontal", "mirror", "circle", "rectangle"] { XCTAssertTrue(app.buttons["maskShape-\(shape)"].exists, shape) }
        XCTAssertFalse(app.descendants(matching: .any)["maskOverlay"].exists, "no handles while the mask is None")
        shot("mask-list")

        app.buttons["maskShape-circle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["maskOverlay"].waitForExistence(timeout: 5), "the picked shape puts its handles on the stage")
        usleep(500_000)
        shot("mask-circle-on-stage")

        app.buttons["maskShape-circle"].tap()   // the picked tile again: the popup
        XCTAssertTrue(app.buttons["maskDone"].waitForExistence(timeout: 5), "a tap on the picked shape opens the popup")
        usleep(500_000)
        shot("mask-popup-position")
        app.descendants(matching: .any).matching(identifier: "ruler").element(boundBy: 0).swipeLeft(velocity: .slow)
        app.buttons["maskParam-feather"].tap()
        XCTAssertTrue(app.sliders["maskSlider-feather"].waitForExistence(timeout: 3), "Feather is one-way: a slider")
        app.sliders["maskSlider-feather"].adjust(toNormalizedSliderPosition: 0.4)
        app.buttons["maskInvert"].tap()
        usleep(500_000)
        shot("mask-popup-feather-invert")
        app.buttons["maskDone"].tap()
        XCTAssertFalse(app.buttons["maskDone"].waitForExistence(timeout: 2), "Done closes the popup")

        // Another shape replaces it; None takes the mask away and with it the handles.
        app.buttons["maskShape-rectangle"].tap()
        usleep(500_000)
        shot("mask-rectangle")
        app.buttons["maskShape-none"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.descendants(matching: .any)["maskOverlay"])
        wait(for: [gone], timeout: 5)

        // Back returns to the clip's row.
        app.buttons["toolbarBack"].tap()
        XCTAssertTrue(app.buttons["action-mask"].waitForExistence(timeout: 5), "« is back on the clip's row")
    }
}
