import XCTest

/// A tap on empty space - nothing of a clip under it - clears the selection (user 2026-10-17); a tap on a clip still selects it.
final class SelectionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func open() -> (app: XCUIApplication, window: XCUICoordinate, width: Double) {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        return (app, app.windows.firstMatch.coordinate(withNormalizedOffset: .zero), Double(app.windows.firstMatch.frame.width))
    }

    func testTappingEmptySpaceClearsTheSelectionOfAPictureClipAndOfAnAudioClip() {
        let (app, window, width) = open()
        let timeline = app.otherElements["timeline"]
        let pxPerMs = { () -> Double in
            timeline.pinch(withScale: 0.3, velocity: -1.5)
            return Double((timeline.value as? String) ?? "") ?? .nan
        }()
        XCTAssertFalse(pxPerMs.isNaN)
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        if scroll.exists { scroll.swipeDown(); scroll.swipeDown() }

        // The text clip: tap selects it (its row has Edit text), a tap on blank runway to the left of the timeline clears it.
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        window.withOffset(CGVector(dx: width / 2 + pxPerMs * 2500, dy: lane.frame.midY)).tap()
        XCTAssertTrue(app.buttons["action-edit-text"].waitForExistence(timeout: 5), "a tap on the clip selects it")
        window.withOffset(CGVector(dx: width * 0.12, dy: lane.frame.midY)).tap()   // before the start of the timeline: empty
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 5), "a tap on empty space brings the main row back")
        XCTAssertFalse(app.buttons["action-edit-text"].exists, "and the clip is no longer selected")

        // The same for the audio clip.
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        window.withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        XCTAssertTrue(app.buttons["action-volume"].waitForExistence(timeout: 5), "a tap on the audio clip selects it")
        window.withOffset(CGVector(dx: width * 0.12, dy: track.frame.midY)).tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 5), "a tap on empty space clears the audio clip too")
        XCTAssertFalse(app.buttons["action-volume"].exists)

        // Tapping a selected clip's handle must not clear it (it is part of the clip). The lanes were scrolled to reach the audio: back to the top.
        scroll.swipeDown(); scroll.swipeDown()
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        window.withOffset(CGVector(dx: width / 2 + pxPerMs * 2500, dy: lane.frame.midY)).tap()
        XCTAssertTrue(app.buttons["action-edit-text"].waitForExistence(timeout: 5))
        let handle = app.descendants(matching: .any)["trim-handle-trailing"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.tap()
        usleep(500_000)
        XCTAssertTrue(app.buttons["action-edit-text"].exists, "a tap on a trim handle keeps the clip selected")
    }
}
