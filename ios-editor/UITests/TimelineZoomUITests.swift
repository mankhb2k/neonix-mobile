import XCTest

/// Real two-finger gestures (`XCUIElement.pinch`) against the timeline — the
/// only way in this toolchain to prove the pinch recogniser is wired and does
/// not fight the scrub drag. The timeline exposes its current scale as the
/// accessibility value of the element identified `timeline`.
final class TimelineZoomUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openTimeline() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15), "the timeline should be on screen")
        return (app, timeline)
    }

    private func scale(of timeline: XCUIElement) -> Double {
        Double((timeline.value as? String) ?? "") ?? .nan
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ZOOM_SHOTS_DIR"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
    }

    func testPinchOutZoomsInAndPinchInZoomsOut() {
        let (app, timeline) = openTimeline()
        let start = scale(of: timeline)
        XCTAssertEqual(start, 0.2, accuracy: 0.001, "default scale is 0.2 px/ms")
        saveShot(app, "zoom_0_default")

        timeline.pinch(withScale: 2.5, velocity: 1.5)
        let zoomedIn = scale(of: timeline)
        XCTAssertGreaterThan(zoomedIn, start * 1.5, "pinching outwards must zoom in")
        saveShot(app, "zoom_1_in")

        timeline.pinch(withScale: 0.25, velocity: -1.5)
        let zoomedOut = scale(of: timeline)
        XCTAssertLessThan(zoomedOut, zoomedIn / 1.5, "pinching inwards must zoom out")
        saveShot(app, "zoom_2_out")
    }

    func testZoomStaysInsideItsLimits() {
        let (app, timeline) = openTimeline()
        for _ in 0..<4 { timeline.pinch(withScale: 4, velocity: 3) }
        XCTAssertLessThanOrEqual(scale(of: timeline), 1.44 + 1e-9)
        XCTAssertEqual(scale(of: timeline), 1.44, accuracy: 0.001, "repeated pinch-out must reach exactly one frame per 48 pt")
        saveShot(app, "zoom_3_max")
        for _ in 0..<5 { timeline.pinch(withScale: 0.1, velocity: -3) }
        XCTAssertGreaterThanOrEqual(scale(of: timeline), 0.0096 - 1e-9)
        XCTAssertEqual(scale(of: timeline), 0.0096, accuracy: 0.0001, "repeated pinch-in must reach exactly 5 s per 48 pt")
        saveShot(app, "zoom_4_min")
    }

    func testAPlainSwipeScrubsWithoutChangingTheScale() {
        let (_, timeline) = openTimeline()
        let before = scale(of: timeline)
        timeline.swipeLeft()
        XCTAssertEqual(scale(of: timeline), before, accuracy: 1e-9, "a one-finger drag must not zoom")
    }
}


/// Vertical lane scrolling: the main (video) lane stays pinned while the lanes
/// below it scroll (a native `ScrollView`), a vertical drag must not move the
/// playhead, and a horizontal drag over the lanes must still scrub.
final class TimelineLaneScrollUITests: XCTestCase {
    func testVerticalDragScrollsLowerLanesWithoutScrubbing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_EXTRA_LANES"] = "6"
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))

        func shot(_ name: String) {
            guard let dir = ProcessInfo.processInfo.environment["ZOOM_SHOTS_DIR"] else { return }
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        let main = app.descendants(matching: .any)["lane-main"].firstMatch
        let firstLane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5), "the main lane should be identifiable")
        XCTAssertTrue(firstLane.exists, "the first scrolling lane should be identifiable")
        shot("lanes_0_top")
        let mainBefore = main.frame.minY
        let laneBefore = firstLane.frame.minY
        let timeBefore = timeline.label
        let scaleBefore = timeline.value as? String

        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.85))
        let end = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        let moved = laneBefore - firstLane.frame.minY
        shot("lanes_1_scrolled")
        XCTAssertGreaterThan(moved, 40, "dragging up must scroll the lower lanes (they moved \(moved) pt)")
        XCTAssertEqual(main.frame.minY, mainBefore, accuracy: 0.5, "the main lane must stay pinned")
        XCTAssertEqual(timeline.value as? String, scaleBefore, "a vertical drag must not change the zoom")
        XCTAssertEqual(timeline.label, timeBefore, "a vertical drag over the lanes must not scrub the playhead")

        // Scroll to the very end: once it settles the last lane sits flush with the
        // bottom of the scroll area — no blank space (that only shows while overscrolling).
        for _ in 0..<3 { start.press(forDuration: 0.05, thenDragTo: end) }
        Thread.sleep(forTimeInterval: 2)
        shot("lanes_2_end")
        let scrollArea = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let lastTrack = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(scrollArea.exists && lastTrack.exists)
        XCTAssertEqual(lastTrack.frame.maxY, scrollArea.frame.maxY, accuracy: 1.5,
                       "after scrolling to the end the last lane must sit at the bottom with no gap")

        // A horizontal drag over the lanes must still scrub (the ScrollView must not swallow it).
        let from = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
        let to = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertNotEqual(timeline.label, timeBefore, "a horizontal drag over the lanes must scrub")
    }
}
