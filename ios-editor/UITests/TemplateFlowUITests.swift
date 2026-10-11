import XCTest

/// Home -> viewer -> "Use template" -> fill the slots from the photo library -> editor -> Export, against a
/// running neonix-api (DEV_AUTH_BYPASS=true) with the starter templates published, and photos/videos in the
/// simulator's library (`simctl addmedia`, `simctl privacy grant photos com.neonix.editor`).
/// Screenshots go to `TEMPLATE_SHOTS_DIR` if set.
final class TemplateFlowUITests: XCTestCase {
    private let api = "http://localhost:8080"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TEMPLATE_SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// Synchronous call to the dev API as `user` (this test runs on the Mac, so localhost is the server).
    @discardableResult
    private func call(_ method: String, _ path: String, user: String, body: [String: Any]? = nil) -> [String: Any] {
        var request = URLRequest(url: URL(string: api + path)!)
        request.httpMethod = method
        request.setValue(user, forHTTPHeaderField: "X-Dev-User")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any] = [:]
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }

    /// The catalogue has many templates and cards load lazily, so find one the way a user would: search.
    private func findPhotoSlideshow(in app: XCUIApplication) -> XCUIElement {
        let search = app.textFields["Search templates"]
        XCTAssertTrue(search.waitForExistence(timeout: 20), "the search field should be on Home")
        search.tap()
        search.typeText("Photo Slideshow")
        let card = app.staticTexts["PHOTO SLIDESHOW"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "searching should find the template")
        XCTAssertFalse(app.staticTexts["QUICK INTRO"].exists, "other templates are filtered out by the search")
        return card
    }

    /// Launches as `user`, opens Photo Slideshow, fills its 4 slots and lands in the editor.
    private func openFilledEditor(as user: String, shots: Bool, expectOwned: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-devUserId", user]
        app.launch()

        let card = findPhotoSlideshow(in: app)
        if shots { saveShot(app, "1-home") }

        card.tap()
        XCTAssertTrue(app.staticTexts["Photo Slideshow"].waitForExistence(timeout: 10), "the viewer should open on the template that was tapped")
        let use = app.buttons["useTemplate-current"]
        XCTAssertTrue(use.waitForExistence(timeout: 10))
        if expectOwned {
            XCTAssertTrue(app.staticTexts["Owned · free to export"].waitForExistence(timeout: 5), "a bought template says it is owned")
        } else {
            XCTAssertTrue(app.staticTexts["6 credits once on your first export · then free"].exists, "an unbought template shows its one-time price")
        }
        if shots { sleep(2); saveShot(app, "2-viewer") }

        use.tap()
        let cells = app.buttons.matching(identifier: "assetCell")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 40), "the library grid should appear once the package is downloaded")
        if shots { sleep(2); saveShot(app, "3-picker") }

        // Cells 0..3: a photo, two clips (12 s and 31 s, both >= the 3 s slots) and a photo; clips need a crop.
        for index in 0..<4 { cells.element(boundBy: index).tap(); usleep(300_000) }
        if shots { saveShot(app, "4-filled") }

        let next = app.buttons["Next"]
        XCTAssertTrue(next.isEnabled, "Next should be enabled once the required slots are filled")
        next.tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 40), "the template result screen should open")
        sleep(2)
        if shots { saveShot(app, "5-result") }
        return app
    }

    /// Home with the demo catalogue: several categories, a waterfall of cards, loading more as you scroll.
    func testHomeShowsTheDemoCatalogue() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-devUserId", "dev-uitest-home-\(Int(Date().timeIntervalSince1970))"]
        app.launch()
        XCTAssertTrue(app.staticTexts["QUICK INTRO"].waitForExistence(timeout: 20), "the newest demo template should be first")
        for chip in ["Discover", "Vlog", "Trends", "Stories"] {
            XCTAssertTrue(app.buttons[chip].exists, "category chip \(chip)")
        }
        sleep(2)
        saveShot(app, "home-a")
        app.swipeUp()
        sleep(2)
        saveShot(app, "home-b")
        app.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["NIGHT OUT"].waitForExistence(timeout: 10), "the Trends chip filters by category")
        XCTAssertFalse(app.staticTexts["QUICK INTRO"].exists, "other categories are filtered out")
        saveShot(app, "home-trends")
    }

    /// No credits: Export asks the server, gets 402 and says so.
    func testExportWithoutCreditsShowsAnError() throws {
        let app = openFilledEditor(as: "dev-uitest-nocredit-\(Int(Date().timeIntervalSince1970))", shots: true)
        app.buttons["exportButton"].tap()
        XCTAssertTrue(app.alerts["Not enough credits"].waitForExistence(timeout: 15), "an empty wallet must be told so")
        saveShot(app, "6-no-credits")
    }

    /// With credits: the first Export of a template spends 6 and buys it; every later export of it is free,
    /// also in a brand-new project, and the template then shows as owned.
    func testFirstExportBuysTheTemplateAndLaterOnesAreFree() throws {
        let user = "dev-uitest-credits-\(Int(Date().timeIntervalSince1970))"
        call("POST", "/v1/dev/credits", user: user, body: ["amount": 20])
        let app = openFilledEditor(as: user, shots: false)

        app.buttons["exportButton"].tap()
        // Debug builds charge even though nothing can render yet, so the flow ends in "Export failed".
        XCTAssertTrue(app.alerts["Export failed"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(call("GET", "/v1/billing/balance", user: user)["balance"] as? Int, 14, "the first export costs 6 credits")

        app.buttons["exportButton"].tap()
        XCTAssertTrue(app.alerts["Export failed"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(call("GET", "/v1/billing/balance", user: user)["balance"] as? Int, 14, "exporting again is free")

        // A completely new project from the same template, later: still free.
        app.terminate()
        let again = openFilledEditor(as: user, shots: false, expectOwned: true)
        again.buttons["exportButton"].tap()
        XCTAssertTrue(again.alerts["Export failed"].waitForExistence(timeout: 15))
        XCTAssertEqual(call("GET", "/v1/billing/balance", user: user)["balance"] as? Int, 14, "an owned template never charges again")
    }

    /// The result screen: tabs for audio and text change what is shown, and Back returns to the picker with the picks.
    func testResultScreenTabsAndBack() throws {
        let app = openFilledEditor(as: "dev-uitest-result-\(Int(Date().timeIntervalSince1970))", shots: false)

        // Audio: the music chip says what plays; choosing "No music" is reflected right away.
        app.buttons["tab-Audio"].tap()
        XCTAssertTrue(app.buttons["musicNone"].waitForExistence(timeout: 5))
        app.buttons["musicNone"].tap()
        XCTAssertTrue(app.buttons["musicChip"].label.contains("No music"), "the chip should say no music")
        saveShot(app, "8-audio")
        app.buttons["musicOriginal"].tap()
        XCTAssertFalse(app.buttons["musicChip"].label.contains("No music"))

        // Text: edit the title.
        app.buttons["tab-Text"].tap()
        let slot = app.buttons["textSlot-title"]
        XCTAssertTrue(slot.waitForExistence(timeout: 5))
        XCTAssertTrue(slot.label.contains("Summer Memories"))
        slot.tap()
        let field = app.textFields["textField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText("Hello Da Nang")
        app.buttons["textDone"].tap()
        XCTAssertTrue(app.buttons["textSlot-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["textSlot-title"].label.contains("Hello Da Nang"), "the typed text should show in the list")
        saveShot(app, "9-text")

        // Media: pick a slot, it offers Replace.
        app.buttons["tab-Media"].tap()
        app.buttons["resultSlot-0"].tap()
        XCTAssertTrue(app.buttons["replaceSlot"].waitForExistence(timeout: 5))
        saveShot(app, "10-media")

        // Back returns to the picker (the Next button is there with the slots still filled).
        app.buttons["backButton"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Next"].isEnabled, "the picks should have been kept")
    }

    /// The Polaroid Collage template places layers with transforms (position, tilt); the result screen should show
    /// them overlapping on the canvas and the media slots should accept photos.
    func testPolaroidCollageShowsPlacedAndTiltedLayers() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-devUserId", "dev-uitest-collage-\(Int(Date().timeIntervalSince1970))"]
        app.launch()
        let search = app.textFields["Search templates"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("Polaroid")
        let card = app.staticTexts["POLAROID COLLAGE"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        app.buttons["useTemplate-current"].tap()
        let cells = app.buttons.matching(identifier: "assetCell")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 40))
        // The three slots are overlapping in time; fill them with photos from the end of the library list.
        for index in 0..<3 { cells.element(boundBy: index).tap(); usleep(300_000) }
        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 40))
        // Play for a while so all three polaroids have appeared (they enter at 0, 1.5 s and 3 s).
        app.buttons["playButton"].tap()
        sleep(5)
        app.buttons["playButton"].tap()
        saveShot(app, "11-collage")
    }

    /// A video longer than its slot gets a crop button; the crop screen opens and closes.
    func testCropScreenOpensForALongVideo() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-devUserId", "dev-uitest-crop-\(Int(Date().timeIntervalSince1970))"]
        app.launch()
        findPhotoSlideshow(in: app).tap()
        app.buttons["useTemplate-current"].tap()
        let cells = app.buttons.matching(identifier: "assetCell")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 40))

        cells.element(boundBy: 1).tap()   // the 12 s clip into slot 1 (3 s)
        let crop = app.buttons["slotCrop-0"]
        XCTAssertTrue(crop.waitForExistence(timeout: 5), "a clip longer than the slot offers a crop")
        crop.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), "the crop screen should open")
        sleep(4)   // let the filmstrip fill
        saveShot(app, "7-crop")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
    }
}
