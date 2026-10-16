import XCTest

/// Long press + drag on a text clip moves it in time (`ClipMoveModifier`): the clip follows the finger, the playhead does not
/// scrub, and an edge near a snap point is pulled onto it (`SnapEngine`: 8 pt).
final class ClipMoveUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private struct Setup {
        let app: XCUIApplication
        let timeline: XCUIElement
        let window: XCUICoordinate
        let width: Double
        let pxPerMs: Double
        let lane: XCUIElement
        /// The text clip's point (its middle) and its leading trim handle's x once selected.
        let grab: XCUICoordinate
        let handleX: Double
    }

    private func openAndSelectTextClip() -> Setup {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        timeline.pinch(withScale: 0.3, velocity: -1.5)
        let pxPerMs = Double((timeline.value as? String) ?? "") ?? .nan
        XCTAssertFalse(pxPerMs.isNaN)
        let laneScroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        if laneScroll.exists { laneScroll.swipeDown(); laneScroll.swipeDown() }
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let width = Double(app.windows.firstMatch.frame.width)
        let grab = window.withOffset(CGVector(dx: width / 2 + pxPerMs * 2500, dy: lane.frame.midY))
        grab.tap()
        let handle = app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "tapping a clip selects it")
        return Setup(app: app, timeline: timeline, window: window, width: width, pxPerMs: pxPerMs, lane: lane, grab: grab, handleX: handle.frame.midX)
    }

    func testLongPressAndDragMovesATextClipWithoutScrubbing() {
        let s = openAndSelectTextClip()
        let timeBefore = s.timeline.label
        let target = s.window.withOffset(CGVector(dx: s.width / 2 + s.pxPerMs * 2500 + 60, dy: s.lane.frame.midY))
        s.grab.press(forDuration: 0.6, thenDragTo: target)

        XCTAssertEqual(s.timeline.label, timeBefore, "moving a clip must not scrub the playhead")
        let after = s.app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5), "the moved clip stays selected")
        // ~54 pt of finger travel (the touch slop eats ~6 pt), then up to 8 pt of snapping either way.
        XCTAssertEqual(after.frame.midX - s.handleX, 54, accuracy: 25, "the clip follows the finger")
    }

    func testAClipStartNearAnotherClipsEdgeSnapsOntoIt() {
        let s = openAndSelectTextClip()
        // The sample's text clip starts at 1.0 s (it is grabbed at 2.5 s, inside it) and the sample has clip edges at 0.5 s.
        // Drag left so it would start about there; the touch slop (~7 pt, not exact) leaves it a few points off, well inside
        // the 8 pt capture, so it must come to rest exactly on 0.5 s - an unsnapped start would be off by the slop.
        let travel = s.pxPerMs * 500 + 6.6
        let target = s.window.withOffset(CGVector(dx: s.width / 2 + s.pxPerMs * 2500 - travel, dy: s.lane.frame.midY))
        s.grab.press(forDuration: 0.6, thenDragTo: target)

        let after = s.app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        XCTAssertEqual(after.frame.midX, s.handleX - s.pxPerMs * 500, accuracy: 0.8, "the start snapped onto 0.5 s")
    }
}
