import XCTest

/// Holding a trim handle near a screen edge keeps the timeline going (slow level, then fast level right at the edge),
/// the playhead runs with it, and lifting stops everything (`TrimAutoScroll`).
final class TrimAutoScrollUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Opens the sample, selects its "Text" clip, drags that clip's right handle to `edgeInset` pt from the right
    /// screen edge and holds `holdSeconds` there. Returns the playhead time (ms) before, after the hold, and 0.6 s after lifting.
    private func holdRightHandle(edgeInset: Double, holdSeconds: TimeInterval) -> (before: Double, held: Double, rested: Double, handleX: Double, width: Double, pxPerMs: Double) {
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
        window.withOffset(CGVector(dx: width / 2 + pxPerMs * 2500, dy: lane.frame.midY)).tap()

        let right = app.descendants(matching: .any)["trim-handle-trailing"].firstMatch
        XCTAssertTrue(right.waitForExistence(timeout: 5), "selecting a clip must show its trim handles")
        let before = Double(timeline.label) ?? 0
        let y = right.frame.midY
        let from = window.withOffset(CGVector(dx: right.frame.midX, dy: y))
        let to = window.withOffset(CGVector(dx: width - edgeInset, dy: y))
        from.press(forDuration: 0.3, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: holdSeconds)
        let held = Double(timeline.label) ?? 0
        Thread.sleep(forTimeInterval: 0.6)
        let rested = Double(timeline.label) ?? 0
        return (before, held, rested, Double(right.frame.midX), width, pxPerMs)
    }

    func testHoldingAtTheEdgeScrollsAndLiftingLandsTheEdgeOnThePlayhead() {
        let slow = holdRightHandle(edgeInset: 40, holdSeconds: 1.5)
        XCTAssertGreaterThan(slow.held - slow.before, 1000, "holding in the slow zone must move the playhead along")
        // The reading is taken after the finger lifted, i.e. after the 0.2 s glide: the dragged edge sits on the playhead
        // and nothing keeps moving afterwards.
        XCTAssertEqual(slow.handleX, slow.width / 2 + 14, accuracy: 8, "the handle ends up on the playhead")
        XCTAssertEqual(slow.rested, slow.held, accuracy: 50, "and the timeline is at rest")
    }

    func testTheFastLevelIsClearlyFasterThanTheSlowOne() {
        let slow = holdRightHandle(edgeInset: 40, holdSeconds: 1.2)
        let fast = holdRightHandle(edgeInset: 8, holdSeconds: 1.2)
        let slowMs = slow.held - slow.before, fastMs = fast.held - fast.before
        XCTAssertGreaterThan(slowMs, 500, "slow level must scroll")
        XCTAssertGreaterThan(fastMs, slowMs * 2, "fast level (480 pt/s) must beat slow (120 pt/s): \(fastMs) vs \(slowMs) ms")
    }

    func testAHandleNotNearAnEdgeDoesNotScroll() {
        let still = holdRightHandle(edgeInset: 160, holdSeconds: 1.0)
        // No auto-scroll: the edge ended where the finger left it (grab point `width - 160`, its border 14 pt before
        // that), and on release the playhead lands exactly there. Auto-scroll would have carried it much further.
        // (~12 pt of slack is the gesture's own start-up drift; a second of slow-level auto-scroll would add ~4000 ms.)
        // The handle's position is not checked: this clip ends up shorter than its 28 pt minimum width on screen.
        let expected = still.before + (still.width - 160 - 14 - still.width / 2) / still.pxPerMs
        XCTAssertEqual(still.held, expected, accuracy: 700, "no auto-scroll away from the edges")
    }
}

/// Main-lane magnet: after a left trim of the first main-lane clip is released, the clip goes back to 0 (no hole).
final class MainLaneMagnetUITests: XCTestCase {
    func testLeftTrimOfTheFirstMainClipSnapsBackToZeroOnRelease() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        let main = app.descendants(matching: .any)["lane-main"].firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let centerX = app.windows.firstMatch.frame.midX
        window.withOffset(CGVector(dx: centerX + 60, dy: main.frame.midY)).tap()

        let left = app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5), "selecting the clip must show its trim handles")
        let before = left.frame.midX
        let y = left.frame.midY
        window.withOffset(CGVector(dx: before, dy: y))
            .press(forDuration: 0.3, thenDragTo: window.withOffset(CGVector(dx: before + 100, dy: y)))
        // The hole closes with a 0.2 s animation after the finger lifts.
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(left.frame.midX, before, accuracy: 6, "the trimmed clip must be back at the start of the lane, not 100 pt later")
    }
}

/// During a left trim the main lane may go before t0; when the finger lifts the head is back at 0.
final class MainLaneNegativeTrimUITests: XCTestCase {
    func testExtendingTheFirstClipLeftOfZeroWorksAndSnapsBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let timeline = app.otherElements["timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        timeline.pinch(withScale: 0.3, velocity: -1.5)
        let laneScroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        if laneScroll.exists { laneScroll.swipeDown(); laneScroll.swipeDown() }
        let main = app.descendants(matching: .any)["lane-main"].firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: app.windows.firstMatch.frame.midX + 30, dy: main.frame.midY)).tap()

        let left = app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        let right = app.descendants(matching: .any)["trim-handle-trailing"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        XCTAssertTrue(right.waitForExistence(timeout: 5), "zoomed out, the whole clip including its right handle is on screen")
        let y = left.frame.midY
        let leftAtZero = left.frame.midX
        let rightBefore = right.frame.midX

        // 1. Trim 100 pt off the start: the head snaps back to 0, the clip is 100 pt shorter.
        window.withOffset(CGVector(dx: leftAtZero, dy: y))
            .press(forDuration: 0.3, thenDragTo: window.withOffset(CGVector(dx: leftAtZero + 100, dy: y)))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(left.frame.midX, leftAtZero, accuracy: 6)
        let rightShort = right.frame.midX
        XCTAssertEqual(rightShort, rightBefore - 100, accuracy: 10, "the clip got 100 pt shorter")

        // 2. Drag the head 60 pt to the LEFT of t0 (revealing the footage just trimmed): it must be allowed, and on
        //    release the head is at 0 again with the clip 60 pt longer.
        window.withOffset(CGVector(dx: leftAtZero, dy: y))
            .press(forDuration: 0.3, thenDragTo: window.withOffset(CGVector(dx: leftAtZero - 60, dy: y)))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(left.frame.midX, leftAtZero, accuracy: 6, "on release the head is back at t0")
        XCTAssertEqual(right.frame.midX, rightShort + 60, accuracy: 10, "the clip got 60 pt longer: the left drag reached before t0")
    }
}
