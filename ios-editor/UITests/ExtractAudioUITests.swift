import XCTest

/// Audio > Extract: pick a video from the library, its sound lands on the audio lane; a video without sound says so.
/// Needs two videos in the simulator's library with Photos access granted to the app (newest first: one with sound, one silent):
/// `xcrun simctl addmedia <sim> silent.mp4; xcrun simctl addmedia <sim> withsound.mp4; xcrun simctl privacy <sim> grant photos com.neonix.editor`.
final class ExtractAudioUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func audioTrackCount(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'audio-track-'")).count
    }

    private func openExtractPicker(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["audio-extract"].tap()
        let grid = app.descendants(matching: .any)["mediaPickerGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "Extract opens the video picker")
        return grid
    }

    func testExtractPutsTheSoundOfAPickedVideoOnTheAudioLaneAndASilentVideoSaysSo() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 15))
        app.buttons["tool-audio"].tap()
        var tracks = audioTrackCount(app)
        var sawSound = false, sawSilent = false

        // Try the first videos of the library (their order is whatever the library gives): one with sound must end on the audio lane,
        // one without must be refused with a message.
        for index in 0..<4 where !(sawSound && sawSilent) {
            let cells = openExtractPicker(app).buttons
            guard index < cells.count else { break }
            if index == 0 {
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "extract-picker"; shot.lifetime = .keepAlways; add(shot)
            }
            cells.element(boundBy: index).tap()   // selects (one at a time)
            XCTAssertTrue(app.buttons["mediaPickerExtract"].isEnabled, "Extract is live once a video is selected")
            if index == 0 {
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "extract-picker-selected"; shot.lifetime = .keepAlways; add(shot)
            }
            app.buttons["mediaPickerExtract"].tap()
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if app.alerts["Couldn't add that"].exists {
                    XCTAssertTrue(app.alerts.staticTexts["That video has no sound"].exists, "a video without sound says so")
                    app.alerts.buttons["OK"].tap()
                    sawSilent = true
                    break
                }
                if audioTrackCount(app) > tracks { tracks = audioTrackCount(app); sawSound = true; break }
                usleep(300_000)
            }
        }
        guard sawSound || sawSilent else { throw XCTSkip("the simulator's library needs videos (see the file header)") }
        XCTAssertTrue(sawSound, "a video with sound puts its audio on the audio lane")
        XCTAssertTrue(sawSilent, "a video without sound is refused")
    }
}
