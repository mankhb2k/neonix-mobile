import XCTest

/// Measurement runs for Remove BG on video (`PLAYBACK_PIPELINE.md` section 9): the selfie plays for 10 s with and without the cut while the playback metrics record
/// (CSV in the app's Documents, pulled by hand). Needs the selfie's mattes complete in the cache (`RemoveBackgroundVideoUITests` leaves them) and runs on the iPhone.
final class RemoveBackgroundPlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Measured on the iPhone only")
        #endif
    }

    private func record(tag: String, cut: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["PLAYBACK_METRICS_SCENARIO"] = "T5"
        app.launchEnvironment["PLAYBACK_METRICS_LEADIN"] = "3"
        app.launchEnvironment["PLAYBACK_METRICS_SECONDS"] = "16"
        app.launchEnvironment["PLAYBACK_METRICS_TAG"] = tag
        app.launchEnvironment["EDITOR_SELECT"] = "people-1"
        app.launchEnvironment["EDITOR_AUTOPLAY_AFTER"] = "6"
        app.launchEnvironment["EDITOR_AUTOPLAY_FOR"] = "10"
        if cut { app.launchEnvironment["EDITOR_AUTO_REMOVEBG"] = "1" }
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Selfie (Remove BG test)"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 20))
        sleep(24)   // 3 s lead-in + 16 s recording, plus the editor opening
    }

    func testPlaybackWithoutTheCut() { record(tag: "rawvideo", cut: false) }
    func testPlaybackWithTheCut() { record(tag: "removebgcut", cut: true) }
}
