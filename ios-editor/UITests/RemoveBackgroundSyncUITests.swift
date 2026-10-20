import XCTest

/// Measurement (Remove BG on video): scrubs, flicks and plays the cut selfie while the app logs, per draw, the time the matte is looked up at and the time of the frame the player
/// really handed over (`Documents/removebg_sync.csv`, pulled by hand). iPhone only; needs the selfie's mattes complete in the cache.
final class RemoveBackgroundSyncUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Measured on the iPhone only")
        #endif
    }

    func testLogWhereTheShownFrameIsAgainstTheMatteTime() {
        let app = XCUIApplication()
        app.launchEnvironment["REMOVEBG_SYNC_LOG"] = "1"
        app.launchEnvironment["EDITOR_SELECT"] = "people-1"
        app.launchEnvironment["EDITOR_AUTO_REMOVEBG"] = "1"
        app.launchEnvironment["EDITOR_AUTOPLAY_AFTER"] = "3"
        app.launchEnvironment["EDITOR_AUTOPLAY_FOR"] = "8"
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Selfie (Remove BG test)"].tap()
        sleep(14)                                                                   // the cut is ready and the autoplay (3 s after the editor opened, 8 s long) is over
        let timeline = app.descendants(matching: .any)["timeline"].firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        for _ in 0..<4 { timeline.swipeLeft(velocity: .slow); usleep(400_000) }     // slow scrubs, forward
        for _ in 0..<4 { timeline.swipeRight(velocity: .slow); usleep(400_000) }    // and back
        sleep(2)                                                                    // at rest
        for _ in 0..<3 { timeline.swipeLeft(velocity: .fast); usleep(1_500_000) }   // flicks
        sleep(4)                                                                    // at rest again
    }
}
