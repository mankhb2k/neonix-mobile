import XCTest

/// Crop on a selected video clip: the tool opens a popup as tall as the screen (like Stickers) with the picture and its frame inside, Reset and Done
/// pinned at the top; an aspect locks the frame, Done keeps it on the clip, Reset takes it away.
final class CropUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func frame(_ app: XCUIApplication) -> [Double] {
        ((app.descendants(matching: .any)["cropStage"].firstMatch.value as? String) ?? "").split(separator: ",").compactMap { Double($0) }
    }

    private func openCrop(_ app: XCUIApplication) {
        let row = app.descendants(matching: .any)["selectionToolbar"]
        for _ in 0..<6 where !app.buttons["action-crop"].isHittable { row.swipeLeft() }
        app.buttons["action-crop"].tap()
        XCTAssertTrue(app.buttons["cropDone"].waitForExistence(timeout: 5), "Crop opens its popup")
        // The picture is the video's frame, loaded a moment after the popup opens.
        usleep(1_500_000)
    }

    func testCropPopupIsFullLengthKeepsItsFrameAndResetTakesItAway() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        app.buttons["tool-edit"].tap()   // selects the clip under the playhead
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }

        openCrop(app)
        let full = frame(app)
        XCTAssertEqual(full.count, 4)
        XCTAssertLessThan(app.buttons["cropDone"].frame.minY, 150, "Done is pinned at the top of the popup")
        XCTAssertLessThan(app.buttons["cropReset"].frame.minY, 150, "so is the back-arrow (reset) icon")
        XCTAssertGreaterThan(full[3], 300, "the picture takes the room above the controls")
        shot("crop-popup-opened")
        let scrub = app.sliders["cropScrub"]
        XCTAssertTrue(scrub.exists, "a video has the time bar under the picture")
        scrub.adjust(toNormalizedSliderPosition: 0.2)   // another frame of the clip to crop on
        usleep(800_000)
        XCTAssertEqual(frame(app)[2], full[2], accuracy: 2, "moving the time bar does not move the frame")
        // The clip's length is the second clock under the picture ("00:31").
        let clocks = app.staticTexts.matching(NSPredicate(format: "label MATCHES '\\\\d\\\\d:\\\\d\\\\d' AND label != '00:00'")).allElementsBoundByIndex
        var clipSeconds = 0.0
        if let label = clocks.first?.label {
            let parts = label.split(separator: ":")
            if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) { clipSeconds = minutes * 60 + seconds }
        }
        let before = scrub.normalizedSliderPosition
        let began = Date()
        app.buttons["cropPlay"].tap()
        sleep(3)
        let afterPlay = scrub.normalizedSliderPosition
        let wall = Date().timeIntervalSince(began)
        XCTAssertGreaterThan(afterPlay, before + 0.02, "Play runs the time bar")
        if clipSeconds > 0 {
            // A real player keeps real time: the bar's progress (in clip seconds) matches the seconds that went by.
            let played = (afterPlay - before) * clipSeconds
            XCTAssertEqual(played, wall, accuracy: wall * 0.4, "the bar ran \(played) s of footage in \(wall) s")
        }
        XCTAssertEqual(app.buttons["cropPlay"].label, "Pause")
        app.buttons["cropPlay"].tap()
        XCTAssertEqual(app.buttons["cropPlay"].label, "Play")
        let paused = scrub.normalizedSliderPosition
        sleep(1)
        XCTAssertEqual(scrub.normalizedSliderPosition, paused, accuracy: 0.005, "Pause stops it")
        shot("crop-popup")

        app.buttons["cropAspect-1:1"].tap()
        usleep(500_000)
        let square = frame(app)
        XCTAssertEqual(square[2], square[3], accuracy: 2, "1:1 makes the frame square")
        shot("crop-popup-square")
        app.buttons["cropDone"].tap()
        XCTAssertFalse(app.buttons["cropDone"].waitForExistence(timeout: 2), "Done closes the popup")

        // The crop stayed on the clip: the frame is where it was left.
        openCrop(app)
        let again = frame(app)
        XCTAssertEqual(again[2], again[3], accuracy: 3, "the cropped (square) frame is back")
        XCTAssertLessThan(again[3], full[3] - 20, "a square on a tall picture is shorter than the whole picture")
        app.buttons["cropReset"].tap()
        usleep(500_000)
        app.buttons["cropDone"].tap()
        XCTAssertFalse(app.buttons["cropDone"].waitForExistence(timeout: 2))

        openCrop(app)
        XCTAssertEqual(frame(app)[3], full[3], accuracy: 3, "Reset took the crop away")
    }
}
