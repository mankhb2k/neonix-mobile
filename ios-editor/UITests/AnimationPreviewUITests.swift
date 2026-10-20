import CoreImage
import XCTest

/// The Animation sheet's tiles play the preset on the preview picture (a screenshot is kept for a look).
final class AnimationPreviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTheAnimationSheetShowsLiveTiles() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let timeline = app.otherElements["timeline"]
        timeline.pinch(withScale: 0.3, velocity: -1.5)
        let pxPerMs = Double((timeline.value as? String) ?? "") ?? .nan
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        if scroll.exists { scroll.swipeDown(); scroll.swipeDown() }
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: Double(app.windows.firstMatch.frame.width) / 2 + pxPerMs * 2500, dy: lane.frame.midY)).tap()
        let animation = app.buttons["action-animation"]
        XCTAssertTrue(animation.waitForExistence(timeout: 5))
        for _ in 0..<6 where !animation.isHittable {
            let row = app.descendants(matching: .any)["selectionToolbar"]
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        }
        animation.tap()
        XCTAssertTrue(app.descendants(matching: .any)["animationGrid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["animationCell-fade"].waitForExistence(timeout: 5), "the preset tiles are there")
        sleep(1)
        for (index, tab) in ["In", "Out", "Combo"].enumerated() {
            app.buttons["animationTab-\(tab)"].tap()
            usleep(900_000)
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = "animation-tiles-\(index)"; a.lifetime = .keepAlways; add(a)
        }
    }

    func testTransitionPickerOffersMixFadePushAndDuration() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))

        let timeline = app.otherElements["timeline"]
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5))
        app.buttons["action-split"].tap()
        app.buttons["toolbarBack"].tap()

        let cutButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'transition-'")).firstMatch
        XCTAssertTrue(cutButton.waitForExistence(timeout: 5), "splitting the main video creates a transition control at the cut")
        let cutShot = XCTAttachment(screenshot: app.screenshot())
        cutShot.name = "timeline-cut-before-transition"
        cutShot.lifetime = .keepAlways
        add(cutShot)
        cutButton.tap()

        XCTAssertTrue(app.buttons["transitionCell-none"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transitionCell-mix"].exists)
        XCTAssertTrue(app.buttons["transitionCell-fade-black"].exists)
        XCTAssertTrue(app.buttons["transitionCell-push"].exists)
        let pickerShot = XCTAttachment(screenshot: app.screenshot())
        pickerShot.name = "transition-picker-mix-fade-push"
        pickerShot.lifetime = .keepAlways
        add(pickerShot)
        app.buttons["transitionCell-fade-black"].tap()
        XCTAssertTrue(app.sliders["transitionDuration"].exists)
        app.buttons["transitionCell-push"].tap()
        XCTAssertTrue(app.buttons["transitionCell-push"].isSelected)
        app.buttons["transitionDone"].tap()
        XCTAssertFalse(app.buttons["transitionDone"].waitForExistence(timeout: 2))
        XCTAssertTrue(cutButton.waitForExistence(timeout: 5))
        XCTAssertEqual(cutButton.label, "Edit transition")
        let timelineShot = XCTAttachment(screenshot: app.screenshot())
        timelineShot.name = "timeline-push-transition-applied"
        timelineShot.lifetime = .keepAlways
        add(timelineShot)

        let startMs = Double(timeline.label ?? "") ?? 0
        let playback = app.buttons["playback-toggle"]
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        playback.tap()
        usleep(250_000)
        XCTAssertGreaterThan(try previewCenterBrightness(app), 30,
                             "the live preview should keep showing a frame while Push is crossing the cut")
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(timeline.label ?? "") ?? startMs) >= startMs + 900
        }, object: nil)
        let playbackResult = XCTWaiter.wait(for: [advanced], timeout: 8)
        XCTAssertEqual(playbackResult, .completed,
                       "playback should continue through and beyond the transition; start=\(startMs), now=\(timeline.label ?? "nil")")
        XCTAssertGreaterThan(try previewCenterBrightness(app), 30,
                             "the incoming clip should remain visible after the transition window")
        let playbackShot = XCTAttachment(screenshot: app.screenshot())
        playbackShot.name = "playhead-after-transition"
        playbackShot.lifetime = .keepAlways
        add(playbackShot)
    }

    private func previewCenterBrightness(_ app: XCUIApplication) throws -> Int {
        guard let cgImage = app.screenshot().image.cgImage else {
            XCTFail("could not capture the simulator preview")
            return 0
        }
        let window = app.windows.firstMatch.frame
        let scaleY = CGFloat(cgImage.height) / max(window.height, 1)
        // StagePreview sits above the timeline; its center is inside the video for the portrait demo project.
        let center = CGRect(x: CGFloat(cgImage.width) / 2 - 18,
                            y: window.height * 0.38 * scaleY - 18,
                            width: 36, height: 36)
        let input = CIImage(cgImage: cgImage)
        let average = try XCTUnwrap(CIFilter(name: "CIAreaAverage"))
        average.setValue(input, forKey: kCIInputImageKey)
        average.setValue(CIVector(cgRect: center), forKey: kCIInputExtentKey)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(try XCTUnwrap(average.outputImage), toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
        return Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
    }
}
