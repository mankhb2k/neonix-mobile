import XCTest

/// Remove BG on a selected photo (an overlay of "Trip to Paris", preselected by `EDITOR_SELECT`): the clip row's Remove BG replaces the row with
/// None / Auto removal / Choose subject / Chroma key.
final class RemoveBackgroundUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAutoRemovalAndChooseSubjectOnAPhoto() {
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_SELECT"] = "overlay-photo-1"
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        let row = app.descendants(matching: .any)["selectionToolbar"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the photo is selected")
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        for _ in 0..<6 where !app.buttons["action-remove-bg"].isHittable { row.swipeLeft() }
        app.buttons["action-remove-bg"].tap()
        XCTAssertTrue(app.buttons["removeBg-auto"].waitForExistence(timeout: 5), "the modes replace the row")
        for mode in ["none", "auto", "point"] { XCTAssertTrue(app.buttons["removeBg-\(mode)"].exists, mode) }
        XCTAssertTrue(app.buttons["removeBg-chroma"].exists, "Chroma key is part of Remove BG")
        shot("removebg-list")

        app.buttons["removeBg-auto"].tap()
        usleep(2_500_000)
        shot("removebg-auto")
        app.buttons["removeBg-auto"].tap()   // the picked tile: the popup
        XCTAssertTrue(app.buttons["removeBgDone"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["removeBgPicker"].exists, "Auto has no picker")
        app.sliders["removeBgFeather"].adjust(toNormalizedSliderPosition: 0.3)
        app.buttons["removeBgInvert"].tap()
        usleep(1_500_000)
        shot("removebg-popup-auto")
        app.buttons["removeBgDone"].tap()
        XCTAssertFalse(app.buttons["removeBgDone"].waitForExistence(timeout: 2))

        app.buttons["removeBg-point"].tap()   // opens the popup with the picker
        XCTAssertTrue(app.descendants(matching: .any)["removeBgPicker"].waitForExistence(timeout: 5), "Choose subject shows the picture to tap")
        usleep(2_000_000)
        app.descendants(matching: .any).matching(identifier: "removeBgPicker").firstMatch.tap()
        usleep(1_500_000)
        shot("removebg-popup-point")
        app.buttons["removeBgDone"].tap()

        app.buttons["removeBg-none"].tap()
        app.buttons["toolbarBack"].tap()
        XCTAssertTrue(app.buttons["action-remove-bg"].waitForExistence(timeout: 5), "« is back on the clip's row")
    }

    func testChromaKeyAppliesAndEditsFromTheRemoveBackgroundList() {
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_SELECT"] = "overlay-photo-1"
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        let row = app.descendants(matching: .any)["selectionToolbar"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the photo is selected")
        for _ in 0..<6 where !app.buttons["action-remove-bg"].isHittable { row.swipeLeft() }
        app.buttons["action-remove-bg"].tap()
        XCTAssertTrue(app.buttons["removeBg-chroma"].waitForExistence(timeout: 5))
        app.buttons["removeBg-chroma"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["chromaKeyColor"].waitForExistence(timeout: 5))
        let sampler = app.descendants(matching: .any)["chromaColorSampler"]
        XCTAssertTrue(sampler.waitForExistence(timeout: 5))
        let keyColor = app.descendants(matching: .any)["chromaKeyColor"]
        let samplerReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: sampler)
        XCTAssertEqual(XCTWaiter.wait(for: [samplerReady], timeout: 10), .completed, "The empty loupe appears centered with the popup before sampling")
        XCTAssertEqual(keyColor.value as? String, "No color selected", "Opening the picker does not apply a default key color")
        let popupScreenshot = XCTAttachment(screenshot: app.screenshot())
        popupScreenshot.name = "chroma-key-popup-with-picker"
        popupScreenshot.lifetime = .keepAlways
        add(popupScreenshot)
        // overlay-photo-1 occupies the upper-right part of this composition; sample within that selected layer.
        let start = sampler.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.22))
        let end = sampler.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.30))
        start.press(forDuration: 0.15, thenDragTo: end)
        XCTAssertEqual(sampler.value as? String, "Active", "The loupe stays available while following the drag")
        XCTAssertNotEqual(keyColor.value as? String, "No color selected", "Dragging samples a color and activates the key")
        XCTAssertTrue(app.sliders["chromaSimilarity"].waitForExistence(timeout: 5))
        app.sliders["chromaSimilarity"].adjust(toNormalizedSliderPosition: 0.55)
        app.sliders["chromaShadow"].adjust(toNormalizedSliderPosition: 0.35)
        app.sliders["chromaSmoothness"].adjust(toNormalizedSliderPosition: 0.4)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "production-chroma-key-photo"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["chromaDone"].tap()
        XCTAssertTrue(app.buttons["removeBg-chroma"].waitForExistence(timeout: 5))
    }

    func testChromaKeySamplesTheVideoPixelUnderThePicker() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Selfie (Remove BG test)"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        app.buttons["tool-edit"].tap()
        let row = app.descendants(matching: .any)["selectionToolbar"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<8 where !app.buttons["action-remove-bg"].isHittable { row.swipeLeft() }
        app.buttons["action-remove-bg"].tap()
        XCTAssertTrue(app.buttons["removeBg-chroma"].waitForExistence(timeout: 5))
        app.buttons["removeBg-chroma"].tap()
        app.buttons["chromaReset"].tap()
        let keyColor = app.descendants(matching: .any)["chromaKeyColor"]
        XCTAssertEqual(keyColor.value as? String, "No color selected", "Reset the test fixture before sampling")

        let sampler = app.descendants(matching: .any)["chromaColorSampler"]
        XCTAssertTrue(sampler.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: sampler)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        // The clip is portrait in a square stage. This stage point maps to a clean wall pixel near source (0.2, 0.24).
        let start = sampler.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50))
        let point = sampler.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.24))
        start.press(forDuration: 0.15, thenDragTo: point)
        let afterDrag = XCTAttachment(screenshot: app.screenshot())
        afterDrag.name = "chroma-video-after-background-drag"
        afterDrag.lifetime = .keepAlways
        add(afterDrag)
        let sampledColor = keyColor.value as? String ?? ""
        XCTAssertTrue(sampledColor.hasPrefix("#"), "A valid sample should return an RGB color")
        let rgb = Int(sampledColor.dropFirst(), radix: 16) ?? 0
        let red = (rgb >> 16) & 0xFF
        let green = (rgb >> 8) & 0xFF
        XCTAssertGreaterThan(red, 200, "The sampled wall pixel should be bright; sampled \(sampledColor)")
        XCTAssertGreaterThan(green, 220, "The top-left wall pixel is pale green, not a face pixel; sampled \(sampledColor)")
    }
}
