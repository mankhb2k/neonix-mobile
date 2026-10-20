import XCTest

/// Marketing screenshots: walks the editor to 12 screens and saves each as a PNG in `marketing/screenshots/raw/` (and as a result-bundle attachment).
/// Not a regression test - run it by hand: `-only-testing:NeonixEditorUITests/MarketingShotsUITests` (a single `test01_...` while tuning one shot).
/// Set up the simulator first: `xcrun simctl status_bar booted override --time 9:41 ...`, and copy real footage into the app's `Documents/ImportedMedia`.
final class MarketingShotsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func shot(_ app: XCUIApplication, _ name: String) {
        sleep(2)   // let the stage frame and any animation settle
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        let dir = repo.appendingPathComponent("marketing/screenshots/raw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func open(soundsFixture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_MARKETING_DEMO"] = "1"
        if soundsFixture { app.launchEnvironment["SOUNDS_FIXTURE_DIR"] = repo.appendingPathComponent("public/preview/sounds").path }
        app.launch()
        app.buttons["Folder"].tap()
        let row = app.staticTexts["Trip to Paris"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        sleep(2)
        return app
    }

    /// Drags the timeline left (time forward) by a fraction of its width.
    private func scrub(_ app: XCUIApplication, by fraction: Double = 0.5) {
        let timeline = app.otherElements["timeline"]
        let from = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        // Slow and held at the end, so the release does not start a glide.
        from.press(forDuration: 0.05, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9 - fraction, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func reveal(_ button: XCUIElement, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["selectionToolbar"]
        for _ in 0..<6 where !button.isHittable { row.swipeLeft() }
        for _ in 0..<8 where !button.isHittable { row.swipeRight() }
        XCTAssertTrue(button.isHittable, "\(button.identifier) reachable")
    }

    /// Selects the picture clip under the playhead and opens one of its tools.
    private func openClipTool(_ app: XCUIApplication, _ id: String) {
        app.buttons["tool-edit"].tap()
        let button = app.buttons["action-\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        reveal(button, in: app)
        button.tap()
    }

    private func ruler(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["ruler"] }

    // MARK: 1 - the whole editor

    func test01_hero() {
        let app = open()
        scrub(app, by: 0.45)
        shot(app, "01-hero")
    }

    // MARK: 2, 3 - text

    private func addText(_ app: XCUIApplication, _ words: String) -> XCUIElement {
        app.buttons["tool-text"].tap()
        app.buttons["text-add"].tap()
        let field = app.textFields["textField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(words)
        app.buttons["textTab-Style"].tap()
        XCTAssertTrue(app.buttons["styleBadge-Background"].waitForExistence(timeout: 5))
        return field
    }

    /// Story-style label (the Background badge), shown as the result on the stage with the sheet closed.
    func test02_textLooks() {
        let app = open()
        scrub(app, by: 0.2)
        _ = addText(app, "Edit like a pro")
        if app.sliders["textSize"].exists { app.sliders["textSize"].adjust(toNormalizedSliderPosition: 0.6) }
        app.buttons["styleBadge-Background"].tap()
        app.buttons["backgroundStyle-hug"].tap()
        let colour = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'textBackground-#'")).element(boundBy: 5)
        if colour.waitForExistence(timeout: 3) { colour.tap() }
        app.buttons["textDone"].tap()
        shot(app, "02-text-looks")
    }

    /// White text with a cyan glow, large, sheet closed.
    func test03_textGlow() {
        let app = open()
        scrub(app, by: 0.2)
        _ = addText(app, "NEON")
        app.buttons["styleBadge-Text"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'textPreset-'")).element(boundBy: 0).tap()
        if app.sliders["textSize"].waitForExistence(timeout: 3) { app.sliders["textSize"].adjust(toNormalizedSliderPosition: 0.95) }
        app.buttons["styleBadge-Glow"].tap()
        let swatch = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'glowColor-#'")).element(boundBy: 12)
        if swatch.waitForExistence(timeout: 3) { swatch.tap() }
        if app.sliders["glowIntensity"].waitForExistence(timeout: 3) {
            app.sliders["glowIntensity"].adjust(toNormalizedSliderPosition: 1)
            app.sliders["glowBlur"].adjust(toNormalizedSliderPosition: 0.5)
        }
        app.buttons["textDone"].tap()
        shot(app, "03-text-glow")
    }

    // MARK: 4, 5, 6 - look of the clip

    func test04_filter() {
        let app = open()
        scrub(app, by: 0.15)
        app.buttons["tool-filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-none"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["filterCell-warm"].tap()
        if app.sliders["filterSlider"].waitForExistence(timeout: 3) { app.sliders["filterSlider"].adjust(toNormalizedSliderPosition: 0.85) }
        shot(app, "04-filter")
    }

    func test05_adjust() {
        let app = open()
        scrub(app, by: 0.15)
        let toolsY = app.buttons["tool-edit"].frame.midY
        let screenWidth = app.windows.firstMatch.frame.width
        for _ in 0..<5 where !(app.buttons["tool-adjust"].exists && app.buttons["tool-adjust"].frame.maxX < screenWidth - 10) {
            let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            window.withOffset(CGVector(dx: screenWidth * 0.85, dy: toolsY))
                .press(forDuration: 0.05, thenDragTo: window.withOffset(CGVector(dx: screenWidth * 0.15, dy: toolsY)))
        }
        app.buttons["tool-adjust"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5))
        app.buttons["adjust-contrast"].tap(); ruler(app).swipeLeft(velocity: .slow)
        app.buttons["adjust-saturation"].tap(); ruler(app).swipeLeft(velocity: .slow)
        app.buttons["adjust-vignette"].tap(); ruler(app).swipeLeft(velocity: .slow)
        app.buttons["adjust-saturation"].tap()
        shot(app, "05-adjust")
    }

    func test06_transform() {
        let app = open()
        scrub(app, by: 0.15)
        openClipTool(app, "transform")
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5))
        app.buttons["transform-scale"].tap(); ruler(app).swipeLeft(velocity: .slow)
        app.buttons["transform-rotation"].tap(); ruler(app).swipeLeft(velocity: .slow)
        shot(app, "06-transform")
    }

    // MARK: 7 - animation

    func test07_animation() {
        let app = open()
        scrub(app, by: 0.15)
        openClipTool(app, "animation")
        XCTAssertTrue(app.descendants(matching: .any)["animationGrid"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "07-animation")
    }

    // MARK: 8, 9 - speed

    func test08_speed() {
        let app = open()
        scrub(app, by: 0.15)
        openClipTool(app, "speed")
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5))
        ruler(app).swipeLeft(velocity: .slow)
        shot(app, "08-speed")
    }

    func test09_speedCurve() {
        let app = open()
        scrub(app, by: 0.15)
        openClipTool(app, "speed")
        app.buttons["speedMode-Curve"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["speedGraph"].waitForExistence(timeout: 5))
        for (index, up) in [(1, -2.2), (2, -3.2), (3, 2.2)] {
            let beat = app.descendants(matching: .any)["speedBeat-\(index)"]
            XCTAssertTrue(beat.waitForExistence(timeout: 5))
            beat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: beat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up)))
        }
        shot(app, "09-speed-curve")
    }

    // MARK: 10 - sound effects

    func test10_soundFX() {
        let app = open(soundsFixture: true)
        app.buttons["tool-audio"].tap()
        app.buttons["audio-sfx"].tap()
        XCTAssertTrue(app.buttons["soundPlay-sfx-whoosh-soft"].waitForExistence(timeout: 10))
        app.buttons["soundPlay-sfx-riser"].tap()
        usleep(900_000)
        shot(app, "10-sound-fx")
    }

    // MARK: 11 - crop

    func test11_crop() {
        let app = open()
        scrub(app, by: 0.15)
        openClipTool(app, "crop")
        XCTAssertTrue(app.buttons["cropDone"].waitForExistence(timeout: 5))
        sleep(1)
        if app.buttons["cropAspect-1:1"].exists { app.buttons["cropAspect-1:1"].tap() }
        shot(app, "11-crop")
    }

    // MARK: 12 - audio volume and fade

    func test12_audioFade() {
        let app = open()
        let clip = app.descendants(matching: .any)["audio-clip-audio-clip-1"].firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 5))
        clip.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5))
        let volume = app.buttons["action-volume"]
        reveal(volume, in: app)
        volume.tap()
        XCTAssertTrue(app.sliders["volumeSlider"].waitForExistence(timeout: 5))
        app.buttons["volumeMode-Fade"].tap()
        let fadeIn = app.sliders["fadeInSlider"]
        XCTAssertTrue(fadeIn.waitForExistence(timeout: 5))
        fadeIn.adjust(toNormalizedSliderPosition: 0.3)
        app.sliders["fadeOutSlider"].adjust(toNormalizedSliderPosition: 0.4)
        shot(app, "12-audio-fade")
    }
}
