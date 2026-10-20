import XCTest

/// Selecting an audio clip shows its row: Split, Volume, Fade, Delete, Duplicate, Beat, Speed (Fade and Beat are labels only so far).
final class AudioClipRowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSelectingAnAudioClipShowsItsRowAndFadeOpensThePopup() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        XCTAssertTrue(app.buttons["action-split"].waitForExistence(timeout: 5), "tapping the audio clip selects it")
        XCTAssertTrue(app.descendants(matching: .any)["trim-handle-leading"].firstMatch.waitForExistence(timeout: 5), "a selected audio clip has trim handles")
        XCTAssertTrue(app.descendants(matching: .any)["trim-handle-trailing"].firstMatch.exists)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "audio-clip-row"; a.lifetime = .keepAlways; add(a)

        // The order of the row is covered by `ClipToolTests.testAnAudioClipHasSoundTools`; here: the labels are on screen.
        let fade = app.buttons["action-fade"]
        for _ in 0..<6 where !fade.isHittable {
            let row = app.descendants(matching: .any)["selectionToolbar"]
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        fade.tap()
        XCTAssertTrue(app.sliders["fadeInSlider"].waitForExistence(timeout: 5), "Fade opens the Volume / Fade popup on Fade")
        XCTAssertTrue(app.sliders["fadeOutSlider"].exists)
    }

    /// Dragging an audio clip's left handle moves the clip's start (and the picture of its waveform follows).
    func testDraggingAnAudioClipsLeftHandleTrimsIt() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        let handle = app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let before = handle.frame.midX
        let from = window.withOffset(CGVector(dx: handle.frame.midX + 4, dy: handle.frame.midY))
        from.press(forDuration: 0.1, thenDragTo: window.withOffset(CGVector(dx: handle.frame.midX + 64, dy: handle.frame.midY)))
        let after = app.descendants(matching: .any)["trim-handle-leading"].firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        // ~60 pt of travel minus the touch slop, then up to 8 pt of snapping.
        XCTAssertGreaterThan(after.frame.midX - before, 25, "the left edge followed the finger")
        XCTAssertLessThan(after.frame.midX - before, 75)
    }

    /// Volume opens a popup with a slider (0 ... 10 times, a mark for 1 in the middle) that goes both ways, a Fade side with two sliders in the same popup, and
    /// Reset; Done closes it.
    func testVolumePopupSliderGoesBothWaysAndFadeIsInTheSamePopup() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        let volume = app.buttons["action-volume"]
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
        for _ in 0..<4 where !volume.isHittable {
            let row = app.descendants(matching: .any)["selectionToolbar"]
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        }
        volume.tap()

        let readout = app.staticTexts["volumeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5), "Volume opens a popup")
        XCTAssertEqual(readout.label, "1×", "it opens on the clip as recorded")
        let slider = app.sliders["volumeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        usleep(800_000)   // the popup has finished presenting
        XCTAssertEqual(slider.normalizedSliderPosition, 0.5, accuracy: 0.03, "the thumb opens on the mark for 1, in the middle")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "volume-popup"; shot.lifetime = .keepAlways; add(shot)

        slider.adjust(toNormalizedSliderPosition: 1)
        usleep(500_000)
        XCTAssertEqual(readout.label, "10×", "the right end is ten times")
        slider.adjust(toNormalizedSliderPosition: 0)
        usleep(500_000)
        XCTAssertEqual(readout.label, "Mute", "the left end is silence")
        slider.adjust(toNormalizedSliderPosition: 0.25)
        usleep(500_000)
        XCTAssertTrue(readout.label.hasPrefix("0."), "the lowering half reads 0.xx (\(readout.label))")
        let moved = XCTAttachment(screenshot: app.screenshot()); moved.name = "volume-popup-moved"; moved.lifetime = .keepAlways; add(moved)
        app.buttons["volume-reset"].tap()
        usleep(500_000)
        XCTAssertEqual(readout.label, "1×", "Reset goes back to 1")

        // The Fade side of the same popup.
        app.buttons["volumeMode-Fade"].tap()
        let fadeIn = app.sliders["fadeInSlider"]
        XCTAssertTrue(fadeIn.waitForExistence(timeout: 5), "Fade is in the same popup")
        XCTAssertEqual(app.staticTexts["fadeInReadout"].label, "Off")
        fadeIn.adjust(toNormalizedSliderPosition: 1)
        usleep(500_000)
        XCTAssertEqual(app.staticTexts["fadeInReadout"].label, "10.0 s", "a long clip fades for at most 10 s")
        app.sliders["fadeOutSlider"].adjust(toNormalizedSliderPosition: 0.5)
        usleep(500_000)
        let half = Double(app.staticTexts["fadeOutReadout"].label.replacingOccurrences(of: " s", with: "")) ?? -1
        XCTAssertTrue((4.0...6.5).contains(half), "about halfway along a 10 s limit (\(half) s)")
        let shot2 = XCTAttachment(screenshot: app.screenshot()); shot2.name = "fade-popup"; shot2.lifetime = .keepAlways; add(shot2)
        app.buttons["volume-reset"].tap()
        usleep(500_000)
        XCTAssertEqual(app.staticTexts["fadeOutReadout"].label, "Off")

        // Fades again, then Done: the clip's body curves down at both ends.
        app.sliders["fadeInSlider"].adjust(toNormalizedSliderPosition: 0.5)
        app.sliders["fadeOutSlider"].adjust(toNormalizedSliderPosition: 0.3)
        usleep(500_000)
        app.buttons["volumeDone"].tap()
        XCTAssertFalse(app.sliders["fadeInSlider"].waitForExistence(timeout: 2), "Done closes the popup")
        sleep(1)
        let clipShot = XCTAttachment(screenshot: app.screenshot()); clipShot.name = "audio-clip-fades"; clipShot.lifetime = .keepAlways; add(clipShot)
    }

    /// Split on a selected audio clip cuts it in two at the playhead: dim at the clip's start (the cut would leave an empty half), live inside the clip.
    func testSplitCutsAnAudioClipAtThePlayhead() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        let split = app.buttons["action-split"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        XCTAssertFalse(split.isEnabled, "the playhead is on the clip's start: nothing to cut")

        // Move the playhead into the clip (drag the ruler sideways).
        let timeline = app.otherElements["timeline"]
        let ruler = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.06))
        ruler.press(forDuration: 0.02, thenDragTo: ruler.withOffset(CGVector(dx: -150, dy: 0)), withVelocity: .default, thenHoldForDuration: 0)
        usleep(900_000)
        XCTAssertTrue(split.isEnabled, "the playhead is inside the clip now")
        func audioClips() -> Int {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'audio-clip-'")).count
        }
        XCTAssertEqual(audioClips(), 1)
        split.tap()
        usleep(900_000)
        XCTAssertEqual(audioClips(), 2, "the clip is cut in two")
        let splitShot = XCTAttachment(screenshot: app.screenshot()); splitShot.name = "audio-clip-split"; splitShot.lifetime = .keepAlways; add(splitShot)
        XCTAssertFalse(app.buttons["action-split"].exists, "the selection is cleared, like after splitting a picture clip")
    }

    /// Long press + drag on an audio clip moves it among the audio tracks: dragged below the last track it becomes a track of its own (the old, emptied
    /// track goes), dragged up over the picture lanes it still lands in the audio section (never in a picture lane).
    func testLongPressAndDragMovesAnAudioClipToANewTrack() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        func audioTracks() -> Int {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'audio-track-'")).count
        }
        XCTAssertEqual(audioTracks(), 1)

        // Sideways, same track: it stays "track-1".
        let from = window.withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY))
        from.press(forDuration: 0.6, thenDragTo: window.withOffset(CGVector(dx: width / 2 + 100, dy: track.frame.midY)))
        usleep(800_000)
        XCTAssertTrue(app.descendants(matching: .any)["audio-track-track-1"].exists, "a sideways move keeps the clip in its track")

        // Below the last track: a new track (the id changes, the emptied one is gone, still one audio track).
        let track2 = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        let grab = window.withOffset(CGVector(dx: width / 2 + 100, dy: track2.frame.midY))
        grab.press(forDuration: 0.6, thenDragTo: window.withOffset(CGVector(dx: width / 2 + 100, dy: track2.frame.midY + 45)))
        usleep(900_000)
        XCTAssertFalse(app.descendants(matching: .any)["audio-track-track-1"].exists, "the clip went to a new track and the emptied one is gone")
        XCTAssertEqual(audioTracks(), 1)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "audio-moved-new-track"; shot.lifetime = .keepAlways; add(shot)
    }

    /// A clip held near the bottom of the lanes scrolls them (the picture lanes and the audio tracks are one scroll).
    func testHoldingAClipNearTheBottomOfTheLanesScrollsThem() {
        let app = XCUIApplication()
        app.launchEnvironment["EDITOR_EXTRA_LANES"] = "8"
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let timeline = app.otherElements["timeline"]
        timeline.pinch(withScale: 0.3, velocity: -1.5)
        let pxPerMs = Double((timeline.value as? String) ?? "") ?? .nan
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        scroll.swipeDown(); scroll.swipeDown()
        let lane = app.descendants(matching: .any)["lane-1"].firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        let width = Double(app.windows.firstMatch.frame.width)
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        // The audio row is below the visible lanes; it is not touched by the move, so its position says how far the lanes scrolled (the clip itself ends up
        // in another lane after the drop).
        let audio = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        let before = Double(audio.frame.minY)
        let bottom = Double(scroll.frame.maxY) - 8
        window.withOffset(CGVector(dx: width / 2 + pxPerMs * 2500, dy: lane.frame.midY))
            .press(forDuration: 0.6, thenDragTo: window.withOffset(CGVector(dx: width / 2 + pxPerMs * 2500, dy: bottom)), withVelocity: .slow, thenHoldForDuration: 1.5)
        usleep(600_000)
        let after = Double(audio.frame.minY)
        XCTAssertLessThan(after, before - 40, "the lanes scrolled up on their own while the clip was held at the bottom (\(before) -> \(after))")
    }

    /// Lanes that all fit the screen have nothing to scroll, yet a held audio clip must be able to reach "a new track at the end": the lanes get one empty
    /// row of room while it is lifted, so they scroll up to show it (and the insert line), and the drop makes a second track.
    func testHoldingASplitAudioClipAtTheBottomMakesRoomForANewLastTrack() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Folder"].tap()
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["tool-edit"].waitForExistence(timeout: 15))
        let scroll = app.descendants(matching: .any)["lane-scroll"].firstMatch
        let track = app.descendants(matching: .any)["audio-track-track-1"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        for _ in 0..<4 where !track.isHittable { scroll.swipeUp() }
        let width = Double(app.windows.firstMatch.frame.width)
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: width / 2 + 40, dy: track.frame.midY)).tap()
        let timeline = app.otherElements["timeline"]
        let ruler = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.06))
        ruler.press(forDuration: 0.02, thenDragTo: ruler.withOffset(CGVector(dx: -150, dy: 0)), withVelocity: .default, thenHoldForDuration: 0)
        usleep(900_000)
        app.buttons["action-split"].tap()
        usleep(900_000)
        func audioTracks() -> Int {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'audio-track-'")).count
        }
        XCTAssertEqual(audioTracks(), 1)

        let before = Double(track.frame.minY)
        let bottom = Double(scroll.frame.maxY) - 8
        let shotTaken = expectation(description: "shot while held")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "audio-held-at-bottom"; shot.lifetime = .keepAlways; self.add(shot)
            shotTaken.fulfill()
        }
        window.withOffset(CGVector(dx: width / 2 + 80, dy: track.frame.midY))
            .press(forDuration: 0.6, thenDragTo: window.withOffset(CGVector(dx: width / 2 + 80, dy: bottom)), withVelocity: .slow, thenHoldForDuration: 2.0)
        wait(for: [shotTaken], timeout: 5)
        usleep(900_000)
        XCTAssertEqual(audioTracks(), 2, "dropped at the bottom: the clip is a track of its own at the end")
        XCTAssertGreaterThanOrEqual(Double(app.descendants(matching: .any)["audio-track-track-1"].firstMatch.frame.minY), before - 60)
    }
}
