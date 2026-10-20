import XCTest

/// One unbroken walk through the editor for screen recording (no relaunch, a pause after every step): open a project, then on the picture clip Transform ->
/// Adjust -> Filter, then on the audio clip Volume -> Fade. Run it alone and record the simulator:
///   xcrun simctl io booted recordVideo demo.mp4      (Ctrl-C to stop)
/// `DEMO_PACE` (a number, default 1) stretches or shrinks every pause.
final class EditorFeaturesDemoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private let pace = Double(ProcessInfo.processInfo.environment["DEMO_PACE"] ?? "") ?? 1

    /// A pause so the viewer can see what just happened.
    private func beat(_ seconds: Double = 1.2) { usleep(UInt32(seconds * pace * 1_000_000)) }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Swipes a scrolling row of buttons until `button` can be tapped (left first, then back right).
    private func reveal(_ button: XCUIElement, in row: XCUIElement) {
        for _ in 0..<6 where !button.isHittable { row.swipeLeft() }
        for _ in 0..<8 where !button.isHittable { row.swipeRight() }
        XCTAssertTrue(button.isHittable, "\(button.identifier) should be reachable")
    }

    private func ruler(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["ruler"] }

    func testTransformAdjustFilterThenVolumeAndFadeInOneRun() throws {
        let app = XCUIApplication()
        app.launch()
        beat()

        // MARK: Open the project
        app.buttons["Folder"].tap()
        beat()
        let project = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15), "the editor opens")
        beat(2)

        // MARK: Select the picture clip (Edit takes the clip under the playhead)
        app.buttons["tool-edit"].tap()
        XCTAssertTrue(app.buttons["action-transform"].waitForExistence(timeout: 5))
        beat()

        // MARK: Transform
        app.buttons["action-transform"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "the Transform sheet opens")
        beat()
        ruler(app).swipeLeft(velocity: .slow)                           // Position X
        beat()
        app.buttons["transform-y"].tap(); beat(0.6)
        ruler(app).swipeRight(velocity: .slow); beat()
        app.buttons["transform-scale"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat()                    // a different scale
        shot("demo-transform-scaled")
        app.buttons["transform-rotation"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat()
        app.buttons["transform-opacity"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat()
        app.buttons["transform-reset"].tap()                              // everything back
        beat(1.5)
        app.buttons["transformDone"].tap()
        XCTAssertTrue(app.buttons["action-adjust"].waitForExistence(timeout: 5), "back on the clip's row")
        beat()

        // MARK: Adjust
        app.buttons["action-adjust"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "the Adjust sheet opens")
        beat()
        let adjustRow = app.descendants(matching: .any)["adjustButtons"]
        app.buttons["adjust-brightness"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat()
        app.buttons["adjust-contrast"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat()
        app.buttons["adjust-saturation"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat()
        shot("demo-adjust")
        reveal(app.buttons["adjust-vignette"], in: adjustRow)
        app.buttons["adjust-vignette"].tap(); beat(0.6)
        ruler(app).swipeLeft(velocity: .slow); beat(1.5)
        app.buttons["adjustDone"].tap()
        XCTAssertTrue(app.buttons["action-filter"].waitForExistence(timeout: 5), "back on the clip's row")
        beat()

        // MARK: Filter
        let clipRow = app.descendants(matching: .any)["selectionToolbar"]
        reveal(app.buttons["action-filter"], in: clipRow)
        app.buttons["action-filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-none"].waitForExistence(timeout: 5), "the Filter grid opens")
        beat(1.5)
        app.buttons["filterCell-warm"].tap(); beat(1.5)
        app.buttons["filterCell-mono"].tap()
        XCTAssertTrue(app.sliders["filterSlider"].waitForExistence(timeout: 5), "Intensity shows once a filter is picked")
        beat()
        app.sliders["filterSlider"].adjust(toNormalizedSliderPosition: 0.4); beat()
        app.sliders["filterSlider"].adjust(toNormalizedSliderPosition: 1); beat()
        shot("demo-filter")
        app.buttons["filterChip-B&W"].tap(); beat()
        app.buttons["filterCell-noir"].tap(); beat(1.5)
        app.buttons["filterReset"].tap(); beat(1.5)
        app.buttons["filterDone"].tap()
        XCTAssertTrue(app.buttons["toolbarBack"].waitForExistence(timeout: 5), "back on the clip's row")
        beat()

        // MARK: Deselect, then the audio clip
        app.buttons["toolbarBack"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 5))
        beat()
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        beat()
        let width = Double(app.windows.firstMatch.frame.width)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5), "tapping the audio clip selects it")
        beat(1.5)

        // MARK: Volume
        reveal(app.buttons["action-volume"], in: app.descendants(matching: .any)["selectionToolbar"])
        app.buttons["action-volume"].tap()
        let slider = app.sliders["volumeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the Volume popup opens")
        beat(1.5)
        slider.adjust(toNormalizedSliderPosition: 0.8); beat()           // louder
        slider.adjust(toNormalizedSliderPosition: 0.25); beat()          // quieter
        shot("demo-volume")
        slider.adjust(toNormalizedSliderPosition: 0.1); beat()
        app.buttons["volume-reset"].tap(); beat(1.2)                     // back to 1x

        // MARK: Fade (same popup)
        app.buttons["volumeMode-Fade"].tap()
        let fadeIn = app.sliders["fadeInSlider"]
        XCTAssertTrue(fadeIn.waitForExistence(timeout: 5), "Fade is in the same popup")
        beat()
        fadeIn.adjust(toNormalizedSliderPosition: 0.5); beat()
        app.sliders["fadeOutSlider"].adjust(toNormalizedSliderPosition: 0.3); beat()
        shot("demo-fade")
        app.buttons["volumeDone"].tap()
        XCTAssertFalse(app.sliders["fadeInSlider"].waitForExistence(timeout: 2), "Done closes the popup")
        beat(2.5)   // the clip's body now curves down at both ends
        shot("demo-audio-clip-with-fades")
    }
}
