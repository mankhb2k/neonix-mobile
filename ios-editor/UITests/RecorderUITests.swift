import XCTest

/// Audio > Record opens the recorder popup: record, stop into the review, play, Add puts the take on the audio lane at the playhead.
/// Needs the microphone granted to the app on the simulator first:
///   xcrun simctl privacy booted grant microphone com.neonix.editor
/// The denied note runs with `TEST_RUNNER_RECORDER_DENIED=1` after `xcrun simctl privacy booted revoke microphone com.neonix.editor`.
final class RecorderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openRecorder() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 15))
        app.buttons["tool-audio"].tap()
        app.buttons["audio-record"].tap()
        return app
    }

    private func audioTracks(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'audio-track-'")).count
    }

    func testRecordStopReviewAndAddPutsATakeOnTheAudioLane() throws {
        if ProcessInfo.processInfo.environment["RECORDER_DENIED"] != nil { throw XCTSkip("run with the microphone granted") }
        let app = openRecorder()
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(app.buttons["recorderButton"].waitForExistence(timeout: 5), "the Record label opens the popup")
        shot("rec-ready")
        let before = audioTracks(app)

        app.buttons["recorderButton"].tap()
        sleep(3)
        shot("rec-recording")
        XCTAssertNotEqual(app.staticTexts["recorderTime"].label, "00:00.00", "the time runs while recording")
        app.buttons["recorderButton"].tap()   // stop
        XCTAssertTrue(app.buttons["recorderAdd"].waitForExistence(timeout: 5), "stopping turns the popup into the review")
        app.buttons["recorderPlay"].tap()
        usleep(800_000)
        shot("rec-review")
        app.buttons["recorderPlay"].tap()

        app.buttons["recorderAdd"].tap()
        XCTAssertFalse(app.buttons["recorderAdd"].waitForExistence(timeout: 3), "Add closes the popup")
        sleep(1)
        XCTAssertGreaterThan(audioTracks(app), before, "the take is on the timeline (over the song, so a second track)")
    }

    func testDeleteThrowsTheTakeAwayAndTheButtonIsReadyAgain() throws {
        if ProcessInfo.processInfo.environment["RECORDER_DENIED"] != nil { throw XCTSkip("run with the microphone granted") }
        let app = openRecorder()
        XCTAssertTrue(app.buttons["recorderButton"].waitForExistence(timeout: 5))
        app.buttons["recorderButton"].tap()
        sleep(2)
        app.buttons["recorderButton"].tap()
        XCTAssertTrue(app.buttons["recorderDelete"].waitForExistence(timeout: 5))
        app.buttons["recorderDelete"].tap()
        XCTAssertTrue(app.buttons["recorderButton"].waitForExistence(timeout: 3), "back to the record button")
        XCTAssertEqual(app.staticTexts["recorderTime"].label, "00:00.00")
    }

    func testWithoutMicAccessThePopupShowsTheSettingsNote() throws {
        if ProcessInfo.processInfo.environment["RECORDER_DENIED"] == nil { throw XCTSkip("run with TEST_RUNNER_RECORDER_DENIED=1 after revoking the microphone") }
        let app = openRecorder()
        XCTAssertTrue(app.buttons["recorderSettings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recorderButton"].isEnabled)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "rec-denied"; a.lifetime = .keepAlways; add(a)
    }
}
