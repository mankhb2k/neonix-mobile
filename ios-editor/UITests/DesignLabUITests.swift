import XCTest

/// Opens Account > Developer > Design Lab and tries the Transform and Adjust sheets: the ruler, the round buttons inside.
/// Screenshots go to `TEMPLATE_SHOTS_DIR` if set.
final class DesignLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func saveShot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TEMPLATE_SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func openLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        // "Design Lab" is in the Developer section, at the bottom of the list.
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Design Lab should be listed under Developer")
        link.tap()
        let experiment = app.staticTexts["Transform controls"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        saveShot(app, "lab-0-opened")
        XCTAssertTrue(app.buttons["labClose"].waitForExistence(timeout: 10), "the lab should open full screen")
        return app
    }

    private func readout(_ app: XCUIApplication) -> String { app.staticTexts["rulerReadout"].label }

    /// Tapping a round button opens the sheet; the ruler in it changes the value; the buttons in it switch parameter.
    func testPopupSheetRulerAndButtons() throws {
        let app = openLab()
        XCTAssertFalse(app.staticTexts["rulerReadout"].exists, "closed until a button is tapped")
        saveShot(app, "lab-1-closed")

        app.buttons["chip-rotation"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "tapping a button opens the sheet with the ruler")
        XCTAssertEqual(readout(app), "0°")
        saveShot(app, "lab-2-popup")

        // Drag the ruler: the value changes.
        let ruler = app.descendants(matching: .any)["ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeLeft(velocity: .slow)
        XCTAssertNotEqual(readout(app), "0°", "dragging the ruler changes the value")
        let afterDrag = readout(app)
        saveShot(app, "lab-3-ruler-dragged")

        // The round buttons inside the sheet switch the parameter without closing it, each with its own ruler.
        app.buttons["sheetChip-scale"].tap()
        XCTAssertEqual(readout(app), "100%")
        app.buttons["sheetChip-x"].tap()
        XCTAssertEqual(readout(app), "0")
        app.buttons["sheetChip-rotation"].tap()
        XCTAssertEqual(readout(app), afterDrag, "the rotation was kept")

        // Double tap puts just this parameter back to neutral.
        app.buttons["sheetChip-rotation"].doubleTap()
        XCTAssertEqual(readout(app), "0°")

        app.buttons["popupDone"].tap()
        XCTAssertFalse(app.staticTexts["rulerReadout"].waitForExistence(timeout: 2), "Done closes the sheet")
    }

    /// Runs both customer video fixtures through the device-backed chroma lab, saving the actual iPhone frames.
    func testChromaKeyOnTwoStagedRealVideos() throws {
        func attachCurrentShot(_ app: XCUIApplication, name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let app = XCUIApplication()
        app.launchArguments += ["-appLanguage", "english"]
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.descendants(matching: .any)["lab-chroma-key"]
        for _ in 0..<8 where !experiment.isHittable { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["chromaClose"].waitForExistence(timeout: 10))

        for name in ["demo-nguoi1.MOV", "demo-nguoi2.MOV"] {
            let staged = app.buttons["chromaStaged-\(name)"]
            XCTAssertTrue(staged.waitForExistence(timeout: 10), "staged video \(name) should be available")
            staged.tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))
            let stage = app.descendants(matching: .any).matching(identifier: "chromaStage").firstMatch
            XCTAssertTrue(stage.waitForExistence(timeout: 10))
            app.buttons["Current V2"].tap()

            app.buttons["chromaPicker"].tap()
            // The second source is landscape letterboxed in the portrait stage; pick from the picture, not its matte bars.
            let point = name == "demo-nguoi1.MOV"
                ? CGVector(dx: 0.08, dy: 0.12)
                : CGVector(dx: 0.90, dy: 0.42)
            stage.coordinate(withNormalizedOffset: point).tap()
            sleep(1)
            let matrixTime = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ms/frame'")).firstMatch.label
            print("CHROMA \(name) Current V2: \(matrixTime)")
            attachCurrentShot(app, name: "chroma-\(name)-matrix")

            app.buttons["Color cube"].tap()
            sleep(1)
            let cubeTime = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ms/frame'")).firstMatch.label
            print("CHROMA \(name) Color cube: \(cubeTime)")
            attachCurrentShot(app, name: "chroma-\(name)-cube")
        }
    }

    /// Compares the current matrix, a graph composed from supported V2 primitives, and Color Cube at multiple
    /// exact points in the raw green-screen clip. The readout assertion guards against silently sampling the wrong time.
    func testChromaKeyAcrossGreenScreenFootage() throws {
        func attachCurrentShot(_ app: XCUIApplication, name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let app = XCUIApplication()
        app.launchArguments += ["-appLanguage", "english"]
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.descendants(matching: .any)["lab-chroma-key"]
        for _ in 0..<8 where !experiment.isHittable { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["chromaClose"].waitForExistence(timeout: 10))

        let name = "GreenScreen Raw footage.mp4"
        let staged = app.buttons["chromaStaged-\(name)"]
        XCTAssertTrue(staged.waitForExistence(timeout: 10), "the new green-screen footage should be staged on device")
        staged.tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))

        let stage = app.descendants(matching: .any).matching(identifier: "chromaStage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))

        // Pick one clean green patch once and keep it fixed for every sampled time and method.
        app.sliders["chromaIntensity"].adjust(toNormalizedSliderPosition: 0.8)
        app.buttons["chromaPicker"].tap()
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.40)).tap()
        sleep(1)

        let sampleTimes: [Double] = [3, 10, 20, 30, 40]
        let timeSlider = app.sliders["chromaVideoTime"]
        XCTAssertTrue(timeSlider.waitForExistence(timeout: 5), "the clip time slider should be available")
        let timeReadout = app.staticTexts["chromaTimeReadout"]
        let renderReadout = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ms/frame'")).firstMatch
        let variants: [(method: String, name: String, shadow: CGFloat?)] = [
            ("Current V2", "current-v2", nil),
            ("V2 graph", "v2-graph", nil),
            ("Color cube", "color-cube", 0),
            ("Color cube", "color-cube-shadow", 0.5),
        ]

        for seconds in sampleTimes {
            // Use the lab's exact seek points; XCTest slider gestures can land several seconds away on device.
            let previousFrame = stage.value as? String ?? ""
            app.buttons["chromaSeek-\(Int(seconds))"].tap()
            let expectedTime = String(format: "%.1f s", seconds)
            let timeAtTarget = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", expectedTime),
                object: timeReadout
            )
            XCTAssertEqual(XCTWaiter.wait(for: [timeAtTarget], timeout: 5), .completed,
                           "the video time readout should confirm the requested \(expectedTime) sample")

            let decodedFrame = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value != %@", previousFrame),
                object: stage
            )
            XCTAssertEqual(XCTWaiter.wait(for: [decodedFrame], timeout: 10), .completed,
                           "a new source frame should decode at \(expectedTime)")

            for variant in variants {
                app.buttons[variant.method].tap()
                if let shadow = variant.shadow {
                    app.sliders["chromaShadow"].adjust(toNormalizedSliderPosition: shadow)
                    if shadow == 0 {
                        let shadowPercent = Int(app.staticTexts["chromaShadowValue"].label) ?? 100
                        XCTAssertLessThanOrEqual(shadowPercent, 2,
                                                 "the base Color Cube comparison keeps shadow matching at the slider minimum")
                    }
                }
                sleep(1)
                XCTAssertTrue(renderReadout.exists, "\(variant.name) should render at \(expectedTime)")
                print("CHROMA GreenScreen Raw footage.mp4 @\(expectedTime) \(variant.name): \(renderReadout.label)")
                attachCurrentShot(app, name: "chroma-green-screen-\(Int(seconds))s-\(variant.name)")
            }
        }
    }

    func testPinchOnTheStageMovesTheLayerWhileTheSheetIsOpen() throws {
        let app = openLab()
        app.buttons["chip-scale"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5))
        XCTAssertEqual(readout(app), "100%")
        app.descendants(matching: .any)["labStage"].pinch(withScale: 1.8, velocity: 1)
        XCTAssertNotEqual(readout(app), "100%", "pinching the stage changes the scale and the ruler follows")
        saveShot(app, "lab-4-pinched")
    }

    // MARK: Adjust lab

    private func openAdjustLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Adjust controls"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["adjClose"].waitForExistence(timeout: 10), "the Adjust lab should open full screen")
        return app
    }

    func testAdjustScrollLayoutScrollsAndMarksChangedControls() throws {
        let app = openAdjustLab()
        sleep(1)
        saveShot(app, "adj-0-closed")
        app.buttons["adjAction-Adjust"].tap()
        XCTAssertTrue(app.staticTexts["rulerReadout"].waitForExistence(timeout: 5), "Adjust opens the sheet")
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "0")
        saveShot(app, "adj-1-scroll")

        // Drag the ruler: the value changes and the button for it shows the change.
        app.descendants(matching: .any)["ruler"].swipeLeft(velocity: .slow)
        XCTAssertNotEqual(app.staticTexts["rulerReadout"].label, "0")

        // A control at the far end of the row is reachable by scrolling, and selecting it recentres the row.
        app.descendants(matching: .any)["chipsScroll"].swipeLeft()
        let noise = app.buttons["sheetChip-noise"]
        XCTAssertTrue(noise.waitForExistence(timeout: 5))
        noise.tap()
        XCTAssertEqual(app.staticTexts["rulerReadout"].label, "0")
        XCTAssertTrue(app.navigationBars["Noise"].waitForExistence(timeout: 5), "the sheet is now editing Noise")
        saveShot(app, "adj-2-noise")
        app.buttons["adjDone"].tap()
        XCTAssertFalse(app.staticTexts["rulerReadout"].waitForExistence(timeout: 2))
    }

    func testAdjustGroupsLayoutShowsOneGroupAtATime() throws {
        let app = openAdjustLab()
        app.segmentedControls["adjVariantPicker"].buttons["Groups"].tap()
        app.buttons["adjAction-Adjust"].tap()
        XCTAssertTrue(app.buttons["group-Light"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["groupChip-brightness"].exists)
        XCTAssertFalse(app.buttons["groupChip-saturation"].exists, "other groups' buttons are not on screen")
        saveShot(app, "adj-3-groups-light")

        app.buttons["group-Color"].tap()
        XCTAssertTrue(app.buttons["groupChip-saturation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["groupChip-brightness"].exists)
        XCTAssertTrue(app.navigationBars["Saturation"].exists, "switching group selects its first control")
        saveShot(app, "adj-4-groups-color")

        app.buttons["group-Detail"].tap()
        XCTAssertTrue(app.buttons["groupChip-noise"].waitForExistence(timeout: 5), "all five Detail buttons fit without scrolling")
        XCTAssertTrue(app.buttons["groupChip-noise"].isHittable)
    }

    // MARK: Filter lab

    private func openFilterLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Filter picker"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["filterClose"].waitForExistence(timeout: 10), "the filter lab opens full screen")
        return app
    }

    /// The three layouts: pick a filter, the stage follows; the Intensity ruler changes the strength; categories filter the list.
    func testFilterLabGridPicksAFilterAndScalesIt() throws {
        let app = openFilterLab()
        app.buttons["filterAction-Filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-warm"].waitForExistence(timeout: 5), "the grid lists the filters")
        XCTAssertTrue(app.buttons["filterCell-none"].exists, "None is the first cell")
        saveShot(app, "filter-A-grid")

        XCTAssertFalse(app.descendants(matching: .any)["ruler"].exists, "no Intensity control while no filter is picked")
        app.buttons["filterCell-warm"].tap()
        XCTAssertEqual(app.staticTexts["filterStageName"].label, "Warm 100%")
        XCTAssertTrue(app.descendants(matching: .any)["ruler"].waitForExistence(timeout: 5), "picking a filter shows Intensity")
        app.descendants(matching: .any)["ruler"].swipeRight(velocity: .slow)
        XCTAssertNotEqual(app.staticTexts["filterStageName"].label, "Warm 100%", "the Intensity ruler changes the strength")
        saveShot(app, "filter-A-warm")

        // A category narrows the grid.
        app.buttons["filterChip-B&W"].tap()
        XCTAssertTrue(app.buttons["filterCell-mono"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filterCell-warm"].exists, "Warm is not in B&W")

        app.buttons["filterCell-none"].tap()
        XCTAssertEqual(app.staticTexts["filterStageName"].label, "No filter")
        XCTAssertFalse(app.descendants(matching: .any)["ruler"].waitForExistence(timeout: 1), "choosing None hides Intensity again")
        app.buttons["filterDone"].tap()
        XCTAssertFalse(app.buttons["filterCell-mono"].waitForExistence(timeout: 2))
    }

    /// The compact Intensity slider leaves room for a second grid row in the same 340 pt sheet.
    func testFilterLabSliderIntensityFitsMoreOfTheGrid() throws {
        let app = openFilterLab()
        app.buttons["Slider"].tap()
        app.buttons["filterAction-Filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-warm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["filterSlider"].exists, "hidden until a filter is picked")
        saveShot(app, "filter-A-none-no-slider")
        app.buttons["filterCell-warm"].tap()
        XCTAssertTrue(app.sliders["filterSlider"].waitForExistence(timeout: 5))
        app.sliders["filterSlider"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertNotEqual(app.staticTexts["filterStageName"].label, "Warm 100%", "the slider changes the strength")
        // The second row of the grid is (partly) on screen: a cell from row 2 is hittable or at least exists.
        XCTAssertTrue(app.buttons["filterCell-crisp"].exists || app.buttons["filterCell-film400"].exists)
        saveShot(app, "filter-A-slider")
    }

    func testFilterLabTallAndRowLayouts() throws {
        let app = openFilterLab()
        app.buttons["B Grid+"].tap()
        app.buttons["filterAction-Filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-warm"].waitForExistence(timeout: 5))
        saveShot(app, "filter-B-grid-plus")
        app.buttons["filterDone"].tap()

        app.buttons["C Row"].tap()
        app.buttons["filterAction-Filter"].tap()
        XCTAssertTrue(app.buttons["filterCell-cool"].waitForExistence(timeout: 5), "the row lists the filters too")
        app.buttons["filterCell-cool"].tap()
        XCTAssertEqual(app.staticTexts["filterStageName"].label, "Cool 100%")
        saveShot(app, "filter-C-row")
    }

    /// Keyframe lab: the three graph pickers change the segment's graph; the editor opens full screen from each.
    func testKeyframeLabPicksGraphsInAllThreeLayouts() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Keyframes & graphs"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["keyframeClose"].waitForExistence(timeout: 10))

        // A: row
        app.buttons["keyframeAction-Graphs"].tap()
        XCTAssertTrue(app.buttons["graphTile-cubic-in"].waitForExistence(timeout: 5))
        saveShot(app, "keyframe-A-row")
        app.buttons["graphTile-cubic-in"].tap()
        XCTAssertTrue(app.staticTexts["Cubic In"].exists, "the strip names the segment's graph")
        app.buttons["graphDone"].tap()

        // B: grid
        app.buttons["B Grid+"].tap()
        app.buttons["keyframeAction-Graphs"].tap()
        XCTAssertTrue(app.buttons["graphChip-Back"].waitForExistence(timeout: 5))
        app.buttons["graphChip-Back"].tap()
        XCTAssertTrue(app.buttons["graphTile-back-out"].waitForExistence(timeout: 5))
        saveShot(app, "keyframe-B-grid")
        app.buttons["graphTile-back-out"].tap()
        app.buttons["graphDone"].tap()

        // C: big curve
        app.buttons["C Big curve"].tap()
        app.buttons["keyframeAction-Graphs"].tap()
        XCTAssertTrue(app.buttons["graphEdit"].waitForExistence(timeout: 5))
        saveShot(app, "keyframe-C-big")

        // Editor
        app.buttons["graphEdit"].tap()
        XCTAssertTrue(app.buttons["graphEditorDone"].waitForExistence(timeout: 5))
        saveShot(app, "keyframe-editor")
        app.buttons["graphEditorDone"].tap()
        XCTAssertTrue(app.staticTexts["Custom"].waitForExistence(timeout: 5), "the edited graph is named Custom")
    }

    /// Text lab: both layouts, the Font and Style tabs, a font and a preset change the stage text.
    func testTextLabShowsFontAndStyleTabsInBothLayouts() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Text picker"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["textLabClose"].waitForExistence(timeout: 10))

        app.buttons["textAction-Edit text"].tap()
        XCTAssertTrue(app.textFields["textField"].waitForExistence(timeout: 5))
        saveShot(app, "text-A-font")
        app.buttons["textTab-Style"].tap()
        XCTAssertTrue(app.buttons["stylePreset-red-outline"].waitForExistence(timeout: 5))
        app.buttons["stylePreset-red-outline"].tap()
        saveShot(app, "text-A-style")
        app.buttons["textTab-Font"].tap()
        XCTAssertTrue(app.buttons["fontCell-Georgia-Bold"].waitForExistence(timeout: 5))
        app.buttons["fontCell-Georgia-Bold"].tap()
        app.buttons["textDone"].tap()

        app.buttons["B Field at bottom"].tap()
        app.buttons["textAction-Edit text"].tap()
        XCTAssertTrue(app.textFields["textField"].waitForExistence(timeout: 5))
        saveShot(app, "text-B-font")
        app.buttons["textTab-Style"].tap()
        sleep(1)
        saveShot(app, "text-B-style")
    }

    func testTextLabFieldAcceptsTyping() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        link.tap()
        app.staticTexts["Text picker"].tap()
        app.buttons["textAction-Edit text"].tap()
        let field = app.textFields["textField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        sleep(1)
        saveShot(app, "text-typing-focus")
        field.typeText("Hello")
        sleep(1)
        saveShot(app, "text-typing-after")
        XCTAssertEqual(field.value as? String, "Hello", "the field starts empty, so typing is not appended to a default")
    }

    /// Device measurement helper (docked panel, variant C): open the field, type, show a tab, open the field again, close.
    /// `KeyboardBench` writes the head's y per frame into `Documents/keyboard_bench.txt`.
    func testTextLabDockedPanelCycle() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        link.tap()
        app.staticTexts["Text picker"].tap()
        XCTAssertTrue(app.buttons["textLabClose"].waitForExistence(timeout: 10))
        app.buttons["C Docked"].tap()
        for mode in ["Collapse", "Pinned"] {
            app.buttons[mode].tap()
            app.buttons["textAction-Edit text"].tap()
            let field = app.descendants(matching: .any).matching(identifier: "textField").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
            saveShot(app, "docked-rest-\(mode)")
            field.tap()
            sleep(2)
            saveShot(app, "docked-typing-\(mode)")
            app.buttons["textTab-Font"].tap()   // keyboard down, content back
            sleep(2)
            field.tap()
            sleep(2)
            app.buttons["textHideKeyboard"].tap()   // the check mark became "fold the keyboard" while typing
            XCTAssertTrue(app.buttons["textDone"].waitForExistence(timeout: 5))
            app.buttons["textDone"].tap()
            sleep(1)
        }
    }

    /// The Audio waveform lab opens from the list and switches between its three drawings.
    func testAudioWaveformLabShowsItsThreeDrawings() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Audio waveform"]
        for _ in 0..<3 where !experiment.exists { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["audioWaveClose"].waitForExistence(timeout: 10), "the lab opens full screen")
        XCTAssertTrue(app.descendants(matching: .any)["audioWaveBig"].waitForExistence(timeout: 5))
        for (index, name) in ["A Smooth", "B Peaks · top", "C Peaks · both"].enumerated() {
            app.buttons[name].tap()
            usleep(400_000)
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = "audiowave-\(index)"; a.lifetime = .keepAlways; add(a)
            saveShot(app, "audiowave-\(index)")
        }
        app.buttons["audioWaveClose"].tap()
        XCTAssertTrue(app.staticTexts["Audio waveform"].waitForExistence(timeout: 5), "closing returns to the list")
    }

    /// The Audio fade lab opens from the list and switches between its three drawings.
    func testAudioFadeLabShowsItsThreeDrawings() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Audio fade"]
        for _ in 0..<3 where !experiment.exists { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["audioFadeClose"].waitForExistence(timeout: 10), "the lab opens full screen")
        XCTAssertTrue(app.descendants(matching: .any)["audioFadeClip48"].waitForExistence(timeout: 5))
        for (index, name) in ["A Wave as is", "B Scaled wave", "C Scaled + shade"].enumerated() {
            app.buttons[name].tap()
            usleep(400_000)
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = "audiofade-\(index)"; a.lifetime = .keepAlways; add(a)
        }
        for (index, name) in ["Dark body", "Light body", "Two-tone 10/45"].enumerated() {
            app.buttons[name].tap()
            usleep(400_000)
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = "audiofade-body-\(index)"; a.lifetime = .keepAlways; add(a)
        }
        app.buttons["audioFadeClose"].tap()
        XCTAssertTrue(app.staticTexts["Audio fade"].waitForExistence(timeout: 5), "closing returns to the list")
    }

    /// The Sound FX lab: each layout lists the sounds, a tap plays one, Use downloads (once) and lands a clip at the playhead.
    func testSoundLabListsPlaysAndUsesSoundsInAllThreeLayouts() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Sound FX picker"]
        for _ in 0..<3 where !experiment.exists { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["soundClose"].waitForExistence(timeout: 10), "the lab opens full screen")
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }

        // A: rows. Play, then Use a sound that is not downloaded yet (a pretend download, then the clip appears).
        app.buttons["soundOpen"].tap()
        XCTAssertTrue(app.buttons["soundPlay-sfx-pop"].waitForExistence(timeout: 5))
        app.buttons["soundPlay-sfx-riser"].tap()
        usleep(700_000)
        shot("sound-A-playing")
        app.buttons["soundUse-sfx-whoosh-fast"].tap()
        XCTAssertTrue(app.staticTexts["Added Whoosh Fast"].waitForExistence(timeout: 5), "Use downloads, then adds the clip")
        shot("sound-A-added")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "soundAdded").count >= 1)
        app.buttons["soundChip-ui"].tap()
        XCTAssertFalse(app.buttons["soundPlay-sfx-boom"].waitForExistence(timeout: 1), "the UI chip hides the impacts")
        app.buttons["soundDone"].tap()

        // B: waveform rows.
        app.buttons["B Waveform"].tap()
        app.buttons["soundOpen"].tap()
        XCTAssertTrue(app.buttons["soundPlay-sfx-pop"].waitForExistence(timeout: 5))
        app.buttons["soundPlay-sfx-success"].tap()
        usleep(500_000)
        shot("sound-B-playing")
        app.buttons["soundDone"].tap()

        // C: grid with a Use bar for the picked tile.
        app.buttons["C Grid"].tap()
        app.buttons["soundOpen"].tap()
        XCTAssertTrue(app.buttons["soundTile-sfx-pop"].waitForExistence(timeout: 5))
        app.buttons["soundChip-game"].tap()
        XCTAssertTrue(app.buttons["soundTile-sfx-coin"].waitForExistence(timeout: 3))
        app.buttons["soundTile-sfx-coin"].tap()
        XCTAssertTrue(app.buttons["soundUse-sfx-coin"].waitForExistence(timeout: 3), "picking a tile shows its Use bar")
        usleep(300_000)
        shot("sound-C-picked")
        app.buttons["soundUse-sfx-coin"].tap()
        XCTAssertTrue(app.staticTexts["Added Coin"].waitForExistence(timeout: 5))
    }

    /// The Recorder lab: record (simulated), stop into the review, play, Add lands a take at the playhead; the no-mic state.
    func testRecorderLabRecordsReviewsAndAddsATake() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Recorder popup"]
        for _ in 0..<3 where !experiment.exists { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["recorderClose"].waitForExistence(timeout: 10))
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }

        app.buttons["recorderOpen"].tap()
        XCTAssertTrue(app.buttons["recorderButton"].waitForExistence(timeout: 5))
        shot("recorder-ready")
        app.buttons["recorderButton"].tap()
        sleep(3)
        shot("recorder-recording")
        XCTAssertNotEqual(app.staticTexts["recorderTime"].label, "00:00.00", "the time runs while recording")
        app.buttons["recorderButton"].tap()   // stop
        XCTAssertTrue(app.buttons["recorderAdd"].waitForExistence(timeout: 5), "stopping turns the popup into the review")
        app.buttons["recorderPlay"].tap()
        usleep(900_000)
        shot("recorder-review-playing")
        app.buttons["recorderPlay"].tap()
        app.buttons["recorderAdd"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["recorderTake"].waitForExistence(timeout: 5), "Add puts the take on the timeline")

        // No mic access.
        app.buttons["recorderMenu"].tap()
        app.buttons["Simulate no mic access"].tap()
        app.buttons["recorderOpen"].tap()
        XCTAssertTrue(app.buttons["recorderSettings"].waitForExistence(timeout: 5))
        shot("recorder-no-mic")
    }

    /// The Crop lab: in each of the three layouts the frame can be resized by a corner, an aspect locks it, Rotate and Reset work.
    func testCropLabFrameAspectRotateAndResetInAllThreeLayouts() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Crop"]
        for _ in 0..<3 where !experiment.exists { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["cropClose"].waitForExistence(timeout: 10))
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func frame() -> [Double] {
            ((app.descendants(matching: .any)["cropStage"].firstMatch.value as? String) ?? "").split(separator: ",").compactMap { Double($0) }
        }
        let stage = app.descendants(matching: .any)["cropStage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        usleep(800_000)   // the photo is loaded
        let full = frame()
        XCTAssertEqual(full.count, 4)

        // A: drag the top-left corner in, the frame gets smaller; an aspect makes it that shape; Reset puts it back.
        let origin = stage.coordinate(withNormalizedOffset: .zero)
        let corner = origin.withOffset(CGVector(dx: full[0] + 4, dy: full[1] + 4))
        corner.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: full[0] + 90, dy: full[1] + 120)))
        usleep(300_000)
        let smaller = frame()
        XCTAssertLessThan(smaller[2], full[2] - 40, "dragging a corner made the frame narrower")
        shot("crop-A-resized")
        app.buttons["cropAspect-1:1"].tap()
        usleep(500_000)
        let square = frame()
        XCTAssertEqual(square[2], square[3], accuracy: 2, "1:1 makes the frame square")
        app.descendants(matching: .any)["ruler"].swipeLeft(velocity: .slow)
        XCTAssertNotEqual(app.staticTexts["rulerReadout"].label, "0°", "the Rotate ruler turns the picture")
        shot("crop-A-aspect-rotate")
        app.buttons["cropReset"].tap()
        usleep(500_000)
        XCTAssertEqual(frame()[2], full[2], accuracy: 2, "Reset puts the frame back")

        // B: the sheet.
        app.buttons["B Sheet"].tap()
        app.buttons["cropOpen"].tap()
        XCTAssertTrue(app.buttons["sheetAspect-16:9"].waitForExistence(timeout: 5))
        app.buttons["sheetAspect-16:9"].tap()
        usleep(500_000)
        let wide = frame()
        XCTAssertGreaterThan(wide[2], wide[3], "16:9 is wider than tall")
        shot("crop-B-aspect")
        app.buttons["cropParam-rotate"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ruler"].waitForExistence(timeout: 5))
        shot("crop-B-rotate")
        app.buttons["cropFlip"].tap()
        app.buttons["cropSheetDone"].tap()

        // C: Photos style.
        app.buttons["C Photos"].tap()
        XCTAssertTrue(app.buttons["cropAspectMenu"].waitForExistence(timeout: 5))
        app.buttons["cropReset"].tap()
        shot("crop-C")
    }

    /// The Mask lab: four shapes on the stage in each of the three layouts, Invert, a ruler, the sheet's sections and the sliders.
    func testMaskLabShapesRulersAndAllThreeLayouts() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Account"].tap()
        let link = app.staticTexts["Design Lab"]
        for _ in 0..<5 where !link.exists { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let experiment = app.staticTexts["Mask"]
        for _ in 0..<3 where !experiment.exists { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()
        XCTAssertTrue(app.buttons["maskClose"].waitForExistence(timeout: 10))
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func stage() -> [Double] { ((app.descendants(matching: .any)["maskStage"].firstMatch.value as? String) ?? "").split(separator: ",").compactMap { Double($0) } }
        usleep(1_000_000)

        // A: the sheet with the round shape icons below; every shape, the corner handle, a ruler, a slider and Invert.
        app.buttons["maskOpen"].tap()
        XCTAssertTrue(app.buttons["iconShape-circle"].waitForExistence(timeout: 5))
        for shape in ["horizontal", "mirror", "circle", "rectangle"] {
            app.buttons["iconShape-\(shape)"].tap()
            usleep(500_000)
            shot("mask-A-\(shape)")
        }
        XCTAssertEqual(stage().count, 5)

        // The corner handle (top-left, outside the rectangle): pulled in along the diagonal it rounds the corners, and it follows the finger.
        let frame = app.descendants(matching: .any)["maskStage"].firstMatch.frame
        let box = frame.insetBy(dx: 14, dy: 14)
        let aspect = 853.0 / 1280.0
        let displayWidth = min(Double(box.width), Double(box.height) * aspect), displayHeight = displayWidth / aspect
        let originX = Double(box.midX) - displayWidth / 2, originY = Double(box.midY) - displayHeight / 2
        let state = stage()
        let short = min(displayWidth, displayHeight)
        let handleX = originX + state[0] * displayWidth - (state[2] * short / 2 + 20)
        let handleY = originY + state[1] * displayHeight - (state[3] * short / 2 + 20)
        XCTAssertEqual(state[4], 0, accuracy: 0.001, "square corners to begin with")
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        window.withOffset(CGVector(dx: handleX, dy: handleY)).press(forDuration: 0.05, thenDragTo: window.withOffset(CGVector(dx: handleX + 70, dy: handleY + 70)))
        usleep(400_000)
        XCTAssertGreaterThan(stage()[4], 0.3, "pulling the corner handle in rounds the corners")
        shot("mask-A-rounded")

        // Position is two-way: the ruler moves the mask. Feather is one-way: a slider.
        app.buttons["iconChip-position"].tap()
        let before = stage()
        app.descendants(matching: .any).matching(identifier: "ruler").element(boundBy: 0).swipeLeft(velocity: .slow)
        usleep(400_000)
        XCTAssertNotEqual(stage()[0], before[0], "the X ruler moves the mask")
        app.buttons["iconChip-feather"].tap()
        XCTAssertTrue(app.sliders["iconSlider-feather"].waitForExistence(timeout: 3))
        app.sliders["iconSlider-feather"].adjust(toNormalizedSliderPosition: 0.3)
        shot("mask-A-feather")
        app.buttons["iconInvert"].tap()
        usleep(400_000)
        shot("mask-A-inverted")
        app.buttons["iconShape-none"].tap()
        app.buttons["maskSheetDone"].tap()

        // B: the sheet.
        app.buttons["B Sheet"].tap()
        app.buttons["maskOpen"].tap()
        XCTAssertTrue(app.buttons["sheetTile-circle"].waitForExistence(timeout: 5))
        app.buttons["sheetTile-circle"].tap()
        usleep(500_000)
        shot("mask-B-circle")
        app.buttons["maskSection-size"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ruler"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["maskAxis"].exists, "Width / Height share one ruler behind a switch")
        shot("mask-B-size")
        app.buttons["maskSection-invert"].tap()
        app.buttons["maskSheetDone"].tap()

        // C: sliders.
        app.buttons["C Sliders"].tap()
        app.buttons["maskOpen"].tap()
        XCTAssertTrue(app.buttons["sliderTile-mirror"].waitForExistence(timeout: 5))
        app.buttons["sliderTile-mirror"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ruler"].firstMatch.waitForExistence(timeout: 3), "Position is two-way: the ruler")
        XCTAssertFalse(app.sliders["maskSlider-x"].exists)
        shot("mask-C-position")
        app.buttons["sliderChip-feather"].tap()
        XCTAssertTrue(app.sliders["maskSlider-feather"].waitForExistence(timeout: 3), "Feather is one-way: a slider")
        shot("mask-C-feather")
    }
}
