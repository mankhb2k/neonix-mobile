import XCTest

/// Audio > Sound FX: the library sheet lists the sounds with a waveform each, playing one downloads it, Use puts it on the audio lane at the playhead.
/// No server: the app reads the catalogue and the files from `public/preview/sounds` on this Mac (`SOUNDS_FIXTURE_DIR`, Debug only).
final class SoundFXUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private var fixtureDirectory: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("public/preview/sounds").path
    }

    func testListPlayUseAndFilterByCategory() {
        let app = XCUIApplication()
        app.launchEnvironment["SOUNDS_FIXTURE_DIR"] = fixtureDirectory
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-audio"].waitForExistence(timeout: 15))
        app.buttons["tool-audio"].tap()
        app.buttons["audio-sfx"].tap()

        XCTAssertTrue(app.buttons["soundPlay-sfx-whoosh-soft"].waitForExistence(timeout: 10), "the catalogue loads from the fixture")
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        shot("soundfx-list")

        // Listening downloads the sound and plays it (the ring shows progress, the button turns into stop).
        app.buttons["soundPlay-sfx-riser"].tap()
        usleep(900_000)
        shot("soundfx-playing")
        app.buttons["soundPlay-sfx-riser"].tap()   // stop

        // Chips filter the list.
        app.buttons["soundChip-ui"].tap()
        XCTAssertTrue(app.buttons["soundPlay-sfx-pop"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["soundPlay-sfx-boom"].waitForExistence(timeout: 1), "the UI chip hides the impacts")

        // Use: the sound is copied into the project and lands on the audio lane (the playhead is at 0, over the song: a second track).
        // The check on the button lasts about a second, too short for a UI test to catch reliably, so the timeline is what is asserted.
        let before = audioTracks(app)
        app.buttons["soundUse-sfx-pop"].tap()
        sleep(2)
        shot("soundfx-added")
        app.buttons["soundDone"].tap()
        XCTAssertFalse(app.buttons["soundDone"].waitForExistence(timeout: 2))
        XCTAssertGreaterThan(audioTracks(app), before, "the sound is on the timeline")
    }

    private func audioTracks(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'audio-track-'")).count
    }
}
