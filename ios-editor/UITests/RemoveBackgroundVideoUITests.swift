import XCTest

/// Remove BG on a video (the "Selfie / Crowd (Remove BG test)" projects: demo-nguoi1/2.MOV in the app's Documents/ImportedMedia). Vision needs the iPhone's Neural Engine, so run
/// this on the device: Auto starts the job (a progress ring with a percentage and Cancel on the stage), Cancel takes Remove BG off, Auto again carries on from the frames
/// already cut, and when the ring is gone the person stands on the canvas background.
final class RemoveBackgroundVideoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        // Vision finds nothing on the simulator, so the cut is empty there; the flow itself (job, ring, Cancel) can still be tried with TEST_RUNNER_RBV_SIMULATOR=1.
        if ProcessInfo.processInfo.environment["RBV_SIMULATOR"] == nil { throw XCTSkip("Vision finds nothing on the simulator; run on the iPhone") }
        #endif
    }

    func testAutoRemovalShowsProgressCancelsAndFinishesOnRealFootage() { run(project: "Selfie (Remove BG test)", shots: "selfie") }

    /// The crowd clip (landscape, many people): the same flow, to see what Auto keeps.
    func testAutoRemovalOnTheCrowdClip() { run(project: "Crowd (Remove BG test)", shots: "crowd") }

    private func run(project: String, shots: String) {
        let app = XCUIApplication()
        app.launchEnvironment["REMOVEBG_CLEAR_MATTES"] = "1"
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts[project].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 20))
        app.buttons["tool-edit"].tap()   // the clip under the playhead (the selfie)
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = "\(shots)-\(name)"; a.lifetime = .keepAlways; add(a) }
        let row = app.descendants(matching: .any)["selectionToolbar"]
        for _ in 0..<8 where !app.buttons["action-remove-bg"].isHittable { row.swipeLeft() }
        app.buttons["action-remove-bg"].tap()
        XCTAssertTrue(app.buttons["removeBg-auto"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["removeBg-point"].exists, "Choose subject is for photos only")

        app.buttons["removeBg-auto"].tap()
        let card = app.descendants(matching: .any)["removeBgProgress"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the progress card shows while the frames are cut")
        usleep(3_000_000)
        shot("removebg-video-progress")
        XCTAssertTrue(app.descendants(matching: .any)["removeBgPercent"].exists)

        app.buttons["removeBgCancel"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        wait(for: [gone], timeout: 10)
        XCTAssertFalse(app.buttons["removeBg-auto"].isSelected, "Cancel takes Remove BG off the clip")
        shot("removebg-video-cancelled")

        app.buttons["removeBg-auto"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Auto again starts again")
        let finished = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        wait(for: [finished], timeout: 150)
        usleep(1_000_000)
        shot("removebg-video-done")

        app.buttons["removeBg-auto"].tap()   // the picked tile: the popup
        XCTAssertTrue(app.buttons["removeBgDone"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["removeBgPicker"].exists)
        app.sliders["removeBgFeather"].adjust(toNormalizedSliderPosition: 0.3)
        usleep(1_000_000)
        shot("removebg-video-popup")
        app.buttons["removeBgDone"].tap()
    }
}
