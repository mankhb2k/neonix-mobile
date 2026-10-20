import XCTest

/// The Audio tool's four labels (Extract, Music, Sound FX, Record); Sound FX opens the library sheet.
final class AudioLabelsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTheAudioToolShowsItsFourLabelsAndSoundFXOpensTheLibrary() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 15))
        app.buttons["tool-audio"].tap()
        for id in ["audio-extract", "audio-music", "audio-sfx", "audio-record"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), id)
        }
        app.buttons["audio-sfx"].tap()
        XCTAssertTrue(app.buttons["soundDone"].waitForExistence(timeout: 5), "Sound FX opens the library sheet")
    }

    /// With the Audio tool's labels open, tapping an audio clip gives the row to that clip's tools (Split, Volume, ...); the labels go away.
    func testTappingAnAudioClipWhileTheAudioToolIsOpenShowsTheClipsTools() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 15))
        app.buttons["tool-audio"].tap()
        XCTAssertTrue(app.buttons["audio-extract"].waitForExistence(timeout: 5))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5), "the clip's tools replace the Audio tool's labels")
        XCTAssertFalse(app.buttons["audio-extract"].exists)
        XCTAssertTrue(app.buttons["toolbarBack"].exists)
    }
}
