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
        XCTAssertEqual(start, 0.096, accuracy: 0.001, "default scale is half a second per 48 pt")
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

/// Trim handles: the edge must follow the finger 1:1 (the drag is measured in a
/// fixed coordinate space — in the handle's own, which moves with the clip, it
/// covered only half the finger's travel and flickered), and a trim must not
/// scrub the playhead.
final class TimelineTrimUITests: XCTestCase {
    func testHandlesFollowTheFingerWithoutScrubbing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_NO_SNAP"] = "1"   // this test measures 1:1 travel; snapping (SnapEngine) would pull the edge to a nearby point
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        // Zoom out so the short "Text" clip (start 1 s, 3 s long in the
        // sample) and both its handles are fully on screen.
        timeline.pinch(withScale: 0.3, velocity: -1.5)
        let pxPerMs = Double((timeline.value as? String) ?? "") ?? .nan
        XCTAssertFalse(pxPerMs.isNaN)
        // The synthetic pinch can nudge the lanes' scroll view: bring them back to the top.
        let laneScroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        if laneScroll.exists { laneScroll.swipeDown(); laneScroll.swipeDown() }
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let playheadX = app.windows.firstMatch.frame.midX
        window.withOffset(CGVector(dx: playheadX + pxPerMs * 2500, dy: lane.frame.midY)).tap()
        let timeBefore = timeline.label

        let right = app.descendants(matching: .any)["trim-handle-trailing"].firstMatch
        XCTAssertTrue(right.waitForExistence(timeout: 5), "selecting a clip must show its trim handles")
        let rightBefore = right.frame.midX
        let y = right.frame.midY
        window.withOffset(CGVector(dx: rightBefore, dy: y))
            .press(forDuration: 0.3, thenDragTo: window.withOffset(CGVector(dx: rightBefore - 20, dy: y)))
        // On release the playhead goes to the edge that was dragged: the clip's tail, 20 pt earlier than before.
        Thread.sleep(forTimeInterval: 0.8)
        let centerX = app.windows.firstMatch.frame.midX
        XCTAssertEqual(right.frame.minX, centerX, accuracy: 6, "after a right trim the playhead sits on the clip's end")
        // The handle lies outside the clip (its inner edge is the clip's end), so the end was 7 pt left of the handle's middle; the playhead
        // lands one frame (1/30 s) before the end.
        let endBefore = (Double(timeBefore) ?? 0) + (rightBefore - 7 - centerX) / pxPerMs
        XCTAssertEqual(Double(timeline.label) ?? .nan, endBefore - 20 / pxPerMs - 1000 / 30, accuracy: 120, "and it is 20 pt of time earlier than the old end")

        let left = app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(left.exists)
        let timeBeforeLeft = Double(timeline.label) ?? 0
        let leftBefore = left.frame.midX
        window.withOffset(CGVector(dx: leftBefore, dy: y))
            .press(forDuration: 0.3, thenDragTo: window.withOffset(CGVector(dx: leftBefore + 20, dy: y)))
        // ... and after a left trim it sits on the clip's head, 20 pt of time later than the old start.
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(left.frame.maxX, centerX, accuracy: 6, "after a left trim the playhead sits on the clip's start")
        let startBefore = timeBeforeLeft + (leftBefore + 7 - centerX) / pxPerMs
        XCTAssertEqual(Double(timeline.label) ?? .nan, startBefore + 20 / pxPerMs, accuracy: 120)
    }
}

/// A touch on a gliding timeline brakes it: after a fast swipe the playhead keeps
/// moving, and once a finger lands it comes to rest and stays there.
final class TimelineBrakeUITests: XCTestCase {
    func testTouchDuringAGlideBringsTheTimelineToRest() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))

        timeline.swipeLeft(velocity: .fast)
        let afterSwipe = Double(timeline.label) ?? 0
        XCTAssertGreaterThan(afterSwipe, 0, "the swipe must have moved the playhead")
        // Still gliding: the clock keeps advancing for a while after the finger is gone.
        Thread.sleep(forTimeInterval: 0.3)
        let gliding = Double(timeline.label) ?? 0
        XCTAssertGreaterThan(gliding, afterSwipe, "the timeline should still be gliding after the swipe")

        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        Thread.sleep(forTimeInterval: 0.8)
        let rested = Double(timeline.label) ?? 0
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(Double(timeline.label) ?? -1, rested, accuracy: 1, "a touch must bring the glide to rest")
    }
}

/// The fullscreen player bar's scrubber: hold + drag must seek, and the bar must
/// leave its "scrubbing" state when the finger lifts (a hold with no movement included).
final class FullscreenScrubUITests: XCTestCase {
    private func openFullscreen() -> (XCUIApplication, XCUIElement) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let enter = app.buttons["enter-fullscreen"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15))
        enter.tap()
        let scrubber = app.descendants(matching: .any)["fullscreen-scrubber"].firstMatch
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        return (app, scrubber)
    }

    func testHoldAndDragSeeksAndTheBarReturnsToItsRestingState() {
        let (app, scrubber) = openFullscreen()
        let start = Double(scrubber.value as? String ?? "") ?? -1
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.5)
        let after = Double(scrubber.value as? String ?? "") ?? -1
        XCTAssertGreaterThan(after, start + 10_000, "dragging the thumb must seek (\(start) → \(after))")
        XCTAssertTrue(app.buttons["fullscreen-play"].waitForExistence(timeout: 3), "the bar must leave its scrubbing state once the finger lifts")
    }

    func testHoldWithoutMovingStillEndsTheScrub() {
        let (app, scrubber) = openFullscreen()
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["fullscreen-play"].waitForExistence(timeout: 3), "a hold with no movement must not leave the bar stuck in scrubbing")
    }

    func testDragWhilePlayingAndDraggingTwiceBothSeek() {
        let (app, scrubber) = openFullscreen()
        app.buttons["fullscreen-play"].tap()
        Thread.sleep(forTimeInterval: 1)
        func value() -> Double { Double(scrubber.value as? String ?? "") ?? -1 }
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.4, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.4)
        let first = value()
        NSLog("FSDBG first=\(first)")
        XCTAssertGreaterThan(first, 40_000, "seeking while playing must work")
        XCTAssertTrue(app.buttons["fullscreen-play"].waitForExistence(timeout: 3), "stuck in scrubbing after the first drag")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.4, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.4)
        let second = value()
        NSLog("FSDBG second=\(second)")
        XCTAssertLessThan(second, first - 20_000, "a second drag must seek back")
        XCTAssertTrue(app.buttons["fullscreen-play"].waitForExistence(timeout: 3), "stuck in scrubbing after the second drag")
    }

    /// Grab the thumb and drag straight away (no pause), before the video was ever played.
    func testImmediateDragBeforeAnyPlaybackSeeks() {
        let (app, scrubber) = openFullscreen()
        func value() -> Double { Double(scrubber.value as? String ?? "") ?? -1 }
        let start = value()
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.5)
        NSLog("FSDBG immediate start=\(start) after=\(value())")
        XCTAssertGreaterThan(value(), start + 10_000, "an immediate drag on the progress bar must seek")
        XCTAssertTrue(app.buttons["fullscreen-play"].waitForExistence(timeout: 3), "bar stuck in scrubbing")
    }

    /// Grabbing the track in the middle must not jump there: time moves only by the travel.
    func testGrabbingInTheMiddleDoesNotJump() {
        let (_, scrubber) = openFullscreen()
        func value() -> Double { Double(scrubber.value as? String ?? "") ?? -1 }
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.4)
        let afterSmall = value()
        NSLog("FSDBG middle grab after=\(afterSmall)")
        XCTAssertLessThan(afterSmall, 15_000, "a 6% drag from t0 must move about 6% of the duration, not jump to the middle")
        XCTAssertGreaterThan(afterSmall, 0)
        // And back: dragging left returns toward t0.
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(value(), 0, accuracy: 1, "dragging back past t0 clamps at zero")
    }

    /// Screenshot while the finger is still down, a hair past t0 (visual check of the filled part).
    func testScreenshotWhileScrubbingNearZero() {
        let (app, scrubber) = openFullscreen()
        guard let dir = ProcessInfo.processInfo.environment["ZOOM_SHOTS_DIR"] else { return }
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 1, dy: 0))
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            let shot = app.screenshot()
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fs_scrub_near0.png"))
        }
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2.5)
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// A touch that barely moves (1 pt) must not move the time.
    func testSmallTouchJitterDoesNotMoveTheTime() {
        let (_, scrubber) = openFullscreen()
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 2, dy: 0)))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(Double(scrubber.value as? String ?? "") ?? -1, 0, accuracy: 1, "a 2 pt wobble is inside the dead zone")
    }

    /// At t ≠ 0, does a plain touch (no movement) change the time or the drawn fill?
    func testTouchAwayFromZeroMeasure() {
        let (app, scrubber) = openFullscreen()
        guard let dir = ProcessInfo.processInfo.environment["ZOOM_SHOTS_DIR"] else { return }
        func value() -> Double { Double(scrubber.value as? String ?? "") ?? -1 }
        let a = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.8)
        let before = value()
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fs_idle.png"))
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fs_touch.png"))
        }
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 2.5)
        Thread.sleep(forTimeInterval: 0.4)
        NSLog("FSDBG touch before=\(before) after=\(value())")
    }
}
