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
