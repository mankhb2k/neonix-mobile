import XCTest

/// Volume on a video clip: disabled while the video has no sound track (the sample clips have none), and for one that has sound the popup has the
/// Volume slider alone - no Fade. The sample clips are silent, so `EDITOR_VIDEO_HAS_SOUND` (Debug) makes the editor treat the selected video as having sound.
final class VideoVolumeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openSelectedVideo(hasSound: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if hasSound { app.launchEnvironment["EDITOR_VIDEO_HAS_SOUND"] = "1" }
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        app.buttons["tool-edit"].tap()   // selects the clip under the playhead
        XCTAssertTrue(app.buttons["action-volume"].waitForExistence(timeout: 5))
        return app
    }

    func testVolumeStaysDisabledForAVideoWithoutSound() {
        let app = openSelectedVideo(hasSound: false)
        usleep(800_000)   // the sound probe has finished
        XCTAssertFalse(app.buttons["action-volume"].isEnabled)
    }

    func testVolumePopupOnAVideoWithSoundHasNoFadeAndTheSliderGoesBothWays() {
        let app = openSelectedVideo(hasSound: true)
        let volume = app.buttons["action-volume"]
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: volume)
        wait(for: [enabled], timeout: 5)
        volume.tap()

        let slider = app.sliders["volumeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the Volume popup opens")
        XCTAssertFalse(app.buttons["volumeMode-Fade"].exists, "a video has no Fade")
        XCTAssertFalse(app.sliders["fadeInSlider"].exists)
        let soundOn = app.descendants(matching: .any)["videoSoundOn"].firstMatch
        let soundOff = app.descendants(matching: .any)["videoSoundOff"].firstMatch
        XCTAssertTrue(soundOn.waitForExistence(timeout: 3) && soundOff.exists, "two icons under the slider: sound on and muted")
        XCTAssertTrue(soundOn.isSelected && !soundOff.isSelected, "sound is lit at 1x")
        soundOff.tap()   // they only show the state: tapping changes nothing
        XCTAssertEqual(app.staticTexts["volumeReadout"].label, "1×")
        let readout = app.staticTexts["volumeReadout"]
        XCTAssertEqual(readout.label, "1×")
        usleep(800_000)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "video-volume"; a.lifetime = .keepAlways; add(a)

        slider.adjust(toNormalizedSliderPosition: 0.9)
        usleep(500_000)
        XCTAssertNotEqual(readout.label, "1×")
        app.buttons["volume-reset"].tap()
        usleep(500_000)
        XCTAssertEqual(readout.label, "1×", "Reset goes back to as recorded")
        for _ in 0..<3 where readout.label != "Mute" { slider.adjust(toNormalizedSliderPosition: 0); usleep(400_000) }
        XCTAssertEqual(readout.label, "Mute")
        XCTAssertTrue(soundOff.isSelected && !soundOn.isSelected, "at 0 the muted icon lights up")
        let muted = XCTAttachment(screenshot: app.screenshot()); muted.name = "video-volume-muted"; muted.lifetime = .keepAlways; add(muted)
        slider.adjust(toNormalizedSliderPosition: 0.25)
        usleep(500_000)
        XCTAssertTrue(soundOn.isSelected && !soundOff.isSelected, "above 0 the sound icon is lit again")
        app.buttons["volumeDone"].tap()
        XCTAssertFalse(slider.waitForExistence(timeout: 2), "Done closes the popup")
        XCTAssertTrue(app.buttons["action-volume"].waitForExistence(timeout: 3), "back on the clip's row")
    }

    /// The speaker on the main lane turns the lane's own sound off and on (its label says which).
    func testTheMainLaneSpeakerTogglesTheClipSound() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        let speaker = app.buttons["mainLaneMute"]
        XCTAssertTrue(speaker.waitForExistence(timeout: 15))
        XCTAssertEqual(speaker.label, "Mute clip sound")
        speaker.tap()
        let muted = expectation(for: NSPredicate(format: "label == 'Unmute clip sound'"), evaluatedWith: speaker)
        wait(for: [muted], timeout: 5)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "main-lane-muted"; a.lifetime = .keepAlways; add(a)
        speaker.tap()
        let back = expectation(for: NSPredicate(format: "label == 'Mute clip sound'"), evaluatedWith: speaker)
        wait(for: [back], timeout: 5)
    }

    func testCoverEditorOpensAndSavesSelectedFrame() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()

        let editCover = app.buttons["editCover"]
        XCTAssertTrue(editCover.waitForExistence(timeout: 15))
        editCover.tap()

        let save = app.buttons["coverSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["coverClose"].exists)
        XCTAssertTrue(app.buttons["coverUndo"].exists)
        XCTAssertTrue(app.buttons["coverCompare"].exists)
        XCTAssertTrue(app.buttons["coverUpload"].exists)
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)
        wait(for: [enabled], timeout: 10)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "cover-editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        save.tap()
        XCTAssertFalse(save.waitForExistence(timeout: 3), "Save closes the cover editor")
    }
}
