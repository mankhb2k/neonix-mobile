import XCTest

/// The lanes' vertical scroll must always answer a swipe - from a clip or from blank runway, at the start, and after the playhead
/// was moved to some other point of the timeline (a scrub must not leave anything behind that blocks the next scroll).
final class TimelineLaneScrollStabilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private struct Rig {
        let app: XCUIApplication
        let timeline: XCUIElement
        let lane: XCUIElement
        let window: XCUICoordinate
        let width: Double
        let scrollTop: Double
        let scrollHeight: Double
    }

    private func open() -> Rig {
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_EXTRA_LANES"] = "8"   // enough lanes to overflow the viewport
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let timeline = app.otherElements["timeline"]
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        XCTAssertTrue(scroll.exists, "the lanes overflow, so they scroll")
        return Rig(app: app, timeline: timeline, lane: lane, window: app.windows.firstMatch.coordinate(withNormalizedOffset: .zero),
                   width: Double(app.windows.firstMatch.frame.width), scrollTop: Double(scroll.frame.minY), scrollHeight: Double(scroll.frame.height))
    }

    /// One vertical swipe over the lanes starting at `x` (a fraction of the width); returns how far the lanes moved (pt).
    private func swipe(_ rig: Rig, fingerUp: Bool, x: Double) -> Double {
        let y0 = rig.scrollTop + rig.scrollHeight * (fingerUp ? 0.8 : 0.2)
        let y1 = rig.scrollTop + rig.scrollHeight * (fingerUp ? 0.2 : 0.8)
        let before = Double(rig.lane.frame.minY)
        rig.window.withOffset(CGVector(dx: rig.width * x, dy: y0))
            .press(forDuration: 0.02, thenDragTo: rig.window.withOffset(CGVector(dx: rig.width * x, dy: y1)), withVelocity: .fast, thenHoldForDuration: 0)
        usleep(700_000)
        return Double(rig.lane.frame.minY) - before
    }

    /// Scrolls down then back up from several x positions (clips and blank runway); every swipe must move the lanes.
    private func assertScrollsBothWays(_ rig: Rig, _ context: String) {
        for x in [0.12, 0.55, 0.9] {
            let down = swipe(rig, fingerUp: true, x: x)
            XCTAssertLessThan(down, -1, "\(context): finger up at x=\(x) must scroll the lanes (moved \(down) pt)")
            let up = swipe(rig, fingerUp: false, x: x)
            XCTAssertGreaterThan(up, 1, "\(context): finger down at x=\(x) must scroll them back (moved \(up) pt)")
        }
    }

    func testTheLanesScrollFromTheStart() {
        assertScrollsBothWays(open(), "at the start")
    }

    func testTheLanesStillScrollAfterThePlayheadWasMovedToAnotherPoint() {
        let rig = open()
        let rulerPoint = rig.timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        var lastTime = rig.timeline.label
        for dx in [-150.0, 90.0, -40.0] {   // arbitrary points: the playhead is moved by dragging the timeline sideways
            rulerPoint.press(forDuration: 0.02, thenDragTo: rulerPoint.withOffset(CGVector(dx: dx, dy: 0)), withVelocity: .default, thenHoldForDuration: 0)
            usleep(900_000)   // let any glide settle
            XCTAssertNotEqual(rig.timeline.label, lastTime, "the playhead moved")
            lastTime = rig.timeline.label
            assertScrollsBothWays(rig, "after the playhead moved to \(lastTime) ms")
        }
    }
}
