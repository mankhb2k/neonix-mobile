import XCTest
@testable import NeonixEditor

/// Covers the Phase 1 slice of the "Bottom nav tools" roadmap: each
/// `EditorCommand`'s `apply(to:)`, plus `EditorHistory`'s undo/redo
/// round-trip — matching `ProtocolCodableTests`' precedent of testing pure
/// logic directly rather than only through the simulator.
final class EditorCommandTests: XCTestCase {
    private func makeProject(width: Double = 360, height: Double = 640, background: String = "#101820") -> V2Project {
        V2Project(
            composition: V2Composition(width: width, height: height, fps: 30, background: background),
            assets: [],
            layers: []
        )
    }

    func testSetAspectRatioCommandChangesOnlyCompositionDimensions() {
        let project = makeProject()
        let result = SetAspectRatioCommand(width: 480, height: 480).apply(to: project)

        XCTAssertEqual(result.composition.width, 480)
        XCTAssertEqual(result.composition.height, 480)
        // Everything else on the composition — and the rest of the
        // project — stays untouched, matching the "behaves like a crop"
        // design confirmed with the user: no layer/transform changes.
        XCTAssertEqual(result.composition.background, project.composition.background)
        XCTAssertEqual(result.composition.fps, project.composition.fps)
        XCTAssertEqual(result.layers.count, project.layers.count)
    }

    func testSetBackgroundColorCommandChangesOnlyBackground() {
        let project = makeProject()
        let result = SetBackgroundColorCommand(hex: "#FFFFFF").apply(to: project)

        XCTAssertEqual(result.composition.background, "#FFFFFF")
        XCTAssertEqual(result.composition.width, project.composition.width)
        XCTAssertEqual(result.composition.height, project.composition.height)
    }

    func testEditorHistoryUndoRedoRoundTrips() {
        var history = EditorHistory()
        let original = makeProject(background: "#101820")

        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)

        history.record(current: original)
        let edited = SetBackgroundColorCommand(hex: "#FFFFFF").apply(to: original)

        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)

        let undone = history.undo(current: edited)
        XCTAssertEqual(undone?.composition.background, "#101820")
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)

        let redone = history.redo(current: undone!)
        XCTAssertEqual(redone?.composition.background, "#FFFFFF")
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testRecordingANewEditClearsRedoHistory() {
        var history = EditorHistory()
        let original = makeProject()
        history.record(current: original)
        let firstEdit = SetBackgroundColorCommand(hex: "#FFFFFF").apply(to: original)
        _ = history.undo(current: firstEdit)
        XCTAssertTrue(history.canRedo)

        // A fresh edit after undoing invalidates the redo stack — same
        // convention every undo/redo stack uses.
        history.record(current: original)
        XCTAssertFalse(history.canRedo)
    }

    private func makeVideoLayer(id: String = "clip1", start: Double = 0, duration: Double = 8000, trimStart: Double? = 0) -> V2Layer {
        V2Layer(
            id: id,
            order: 0,
            frame: V2Frame(width: 360, height: 640),
            transform: .identity,
            timing: V2Timing(start: start, duration: duration),
            payload: .video(V2VideoPayload(assetId: "asset1", trimStart: trimStart))
        )
    }

    func testSplitClipCommandProducesTwoCorrectlyTimedLayersWithShiftedTrimStart() {
        let original = makeVideoLayer(duration: 8000, trimStart: 2000)
        let project = makeProject().withLayers([original])

        let result = SplitClipCommand(layerId: "clip1", atMs: 3000).apply(to: project)

        XCTAssertEqual(result.layers.count, 2)
        let first = result.layers[0]
        let second = result.layers[1]

        XCTAssertEqual(first.id, "clip1")
        XCTAssertEqual(first.timing.start, 0)
        XCTAssertEqual(first.timing.duration, 3000)

        XCTAssertNotEqual(second.id, "clip1")
        XCTAssertEqual(second.timing.start, 3000)
        XCTAssertEqual(second.timing.duration, 5000)
        // Same lane — `order` carried over unchanged from the original.
        XCTAssertEqual(second.order, original.order)

        guard case .video(let secondPayload) = second.payload else {
            return XCTFail("expected second half to stay a video payload")
        }
        // trimStart is in the same ms units as timing — shifts forward by
        // exactly the first half's duration so the second half keeps
        // playing from the right source point.
        XCTAssertEqual(secondPayload.trimStart, 5000)
    }

    func testSplitClipCommandIsNoOpWhenSplitPointIsOutsideClipRange() {
        let original = makeVideoLayer(start: 0, duration: 8000)
        let project = makeProject().withLayers([original])

        let atStart = SplitClipCommand(layerId: "clip1", atMs: 0).apply(to: project)
        XCTAssertEqual(atStart.layers.count, 1)

        let atEnd = SplitClipCommand(layerId: "clip1", atMs: 8000).apply(to: project)
        XCTAssertEqual(atEnd.layers.count, 1)

        let pastEnd = SplitClipCommand(layerId: "clip1", atMs: 9000).apply(to: project)
        XCTAssertEqual(pastEnd.layers.count, 1)

        let unknownLayer = SplitClipCommand(layerId: "nope", atMs: 3000).apply(to: project)
        XCTAssertEqual(unknownLayer.layers.count, 1)
    }

    func testDeleteClipCommandRemovesOnlyTheTargetedLayer() {
        let keep = makeVideoLayer(id: "keep")
        let remove = makeVideoLayer(id: "remove")
        let project = makeProject().withLayers([keep, remove])

        let result = DeleteClipCommand(layerId: "remove").apply(to: project)

        XCTAssertEqual(result.layers.count, 1)
        XCTAssertEqual(result.layers.first?.id, "keep")
    }

    func testTrimClipCommandWritesTimingAndVideoTrimFieldsVerbatim() {
        let original = makeVideoLayer(start: 0, duration: 8000, trimStart: 2000)
        let project = makeProject().withLayers([original])

        // The command itself does no clamping/validation — that's the
        // drag gesture's job (`TimelineView`'s left/right handle math) —
        // so this just confirms it writes exactly what it's given.
        let result = TrimClipCommand(layerId: "clip1", start: 500, duration: 6000, trimStart: 2500, trimEnd: 9000).apply(to: project)

        XCTAssertEqual(result.layers.count, 1)
        let layer = result.layers[0]
        XCTAssertEqual(layer.timing.start, 500)
        XCTAssertEqual(layer.timing.duration, 6000)

        guard case .video(let payload) = layer.payload else {
            return XCTFail("expected a video payload")
        }
        XCTAssertEqual(payload.trimStart, 2500)
        XCTAssertEqual(payload.trimEnd, 9000)
    }

    func testTrimClipCommandIsNoOpForUnknownLayer() {
        let project = makeProject().withLayers([makeVideoLayer()])
        let result = TrimClipCommand(layerId: "nope", start: 0, duration: 1000, trimStart: nil, trimEnd: nil).apply(to: project)
        XCTAssertEqual(result.layers.count, 1)
        XCTAssertEqual(result.layers.first?.timing.duration, 8000)
    }

    // MARK: - Âm thanh (audio playback foundation + "Thêm nhạc")

    private func makeAudioAsset(id: String = "song1") -> V2AudioAsset {
        V2AudioAsset(id: id, uri: "\(id).m4a", mimeType: "audio/mp4", duration: 5000)
    }

    func testAddAudioClipCommandAppendsAssetAndPlacesOnAnEmptyTrack() {
        let project = makeProject()
        let asset = makeAudioAsset()

        let result = AddAudioClipCommand(asset: asset, durationMs: 5000, atMs: 1000).apply(to: project)

        XCTAssertEqual(result.assets.count, 1)
        XCTAssertEqual(result.assets.first?.id, "song1")
        XCTAssertEqual(result.audio.tracks.count, 1)
        let clip = result.audio.tracks[0].clips.first
        XCTAssertEqual(clip?.assetId, "song1")
        XCTAssertEqual(clip?.timing.start, 1000)
        XCTAssertEqual(clip?.timing.duration, 5000)
    }

    func testAddAudioClipCommandOpensANewTrackWhenEveryExistingTrackOverlaps() {
        let existingClip = V2AudioClip(
            id: "existing", assetId: "song0",
            timing: V2AudioClipTiming(start: 0, duration: 5000),
            trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1
        )
        let existingTrack = V2AudioTrack(id: "track0", gainDb: nil, pan: 0, muted: false, clips: [existingClip])
        let project = makeProject().withAudio(V2AudioDomain(sampleRate: 48000, tracks: [existingTrack]))

        // Overlaps the existing track's only clip (0-5000), so a new track opens.
        let result = AddAudioClipCommand(asset: makeAudioAsset(), durationMs: 3000, atMs: 2000).apply(to: project)

        XCTAssertEqual(result.audio.tracks.count, 2)
        XCTAssertEqual(result.audio.tracks[0].clips.count, 1)
        XCTAssertEqual(result.audio.tracks[1].clips.count, 1)
        XCTAssertEqual(result.audio.tracks[1].clips.first?.timing.start, 2000)
    }

    func testAddAudioClipCommandSharesATrackWhenItDoesNotOverlap() {
        let existingClip = V2AudioClip(
            id: "existing", assetId: "song0",
            timing: V2AudioClipTiming(start: 0, duration: 2000),
            trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1
        )
        let existingTrack = V2AudioTrack(id: "track0", gainDb: nil, pan: 0, muted: false, clips: [existingClip])
        let project = makeProject().withAudio(V2AudioDomain(sampleRate: 48000, tracks: [existingTrack]))

        // Starts after the existing clip ends (2000) — same track.
        let result = AddAudioClipCommand(asset: makeAudioAsset(), durationMs: 3000, atMs: 2000).apply(to: project)

        XCTAssertEqual(result.audio.tracks.count, 1)
        XCTAssertEqual(result.audio.tracks[0].clips.count, 2)
    }

    func testAddAudioClipCommandWritesTrimForExtractedAudio() {
        // Trích xuất exports a video asset's *whole* audio once, so the
        // placed clip needs its own trim to show only the matching slice.
        let asset = V2AudioAsset(id: "extracted-clip1", uri: "extracted-clip1.m4a", mimeType: "audio/mp4", duration: 8000)
        let project = makeProject()

        let result = AddAudioClipCommand(asset: asset, durationMs: 5000, atMs: 1000, trimStartMs: 2000, trimEndMs: 7000).apply(to: project)

        let clip = result.audio.tracks.first?.clips.first
        XCTAssertEqual(clip?.trim.start, 2000)
        XCTAssertEqual(clip?.trim.end, 7000)
        XCTAssertEqual(clip?.timing.start, 1000)
        XCTAssertEqual(clip?.timing.duration, 5000)
    }

    func testAddAudioClipCommandDoesNotDuplicateAnAssetAlreadyPresent() {
        // Hiệu ứng âm thanh reuses the same command with a stable preset
        // asset id — tapping the same sound effect twice must share one
        // `project.assets` entry, not append a duplicate every time.
        let preset = SoundEffectPreset(id: "sfx-pop", title: "Pop", filename: "sfx-pop.wav", durationMs: 150, systemImage: "circle.fill")
        let asset = SoundEffectCatalog.asset(for: preset)
        var project = makeProject()

        project = AddAudioClipCommand(asset: asset, durationMs: 150, atMs: 0).apply(to: project)
        XCTAssertEqual(project.assets.count, 1)

        project = AddAudioClipCommand(asset: asset, durationMs: 150, atMs: 1000).apply(to: project)
        XCTAssertEqual(project.assets.count, 1)
        XCTAssertEqual(project.audio.tracks.flatMap(\.clips).count, 2)
    }

    func testDeleteAudioClipCommandRemovesOnlyTheTargetedClip() {
        let keep = V2AudioClip(id: "keep", assetId: "a", timing: V2AudioClipTiming(start: 0, duration: 1000), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1)
        let remove = V2AudioClip(id: "remove", assetId: "a", timing: V2AudioClipTiming(start: 2000, duration: 1000), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1)
        let track = V2AudioTrack(id: "track0", gainDb: nil, pan: 0, muted: false, clips: [keep, remove])
        let project = makeProject().withAudio(V2AudioDomain(sampleRate: 48000, tracks: [track]))

        let result = DeleteAudioClipCommand(clipId: "remove").apply(to: project)

        XCTAssertEqual(result.audio.tracks[0].clips.count, 1)
        XCTAssertEqual(result.audio.tracks[0].clips.first?.id, "keep")
    }

    func testSetAudioClipVolumeCommandWritesGainDbOnTheTargetedClipOnly() {
        let a = V2AudioClip(id: "a", assetId: "x", timing: V2AudioClipTiming(start: 0, duration: 1000), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1)
        let b = V2AudioClip(id: "b", assetId: "x", timing: V2AudioClipTiming(start: 2000, duration: 1000), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1)
        let track = V2AudioTrack(id: "track0", gainDb: nil, pan: 0, muted: false, clips: [a, b])
        let project = makeProject().withAudio(V2AudioDomain(sampleRate: 48000, tracks: [track]))

        let result = SetAudioClipVolumeCommand(clipId: "a", gainDb: -12).apply(to: project)

        XCTAssertEqual(result.audio.tracks[0].clips.first { $0.id == "a" }?.gainDb, -12)
        XCTAssertNil(result.audio.tracks[0].clips.first { $0.id == "b" }?.gainDb)
    }

    // MARK: - Văn bản (Thêm chữ)

    private func textContent(of layer: V2Layer?) -> String? {
        guard case .text(let payload) = layer?.payload else { return nil }
        return payload.source.text
    }

    func testAddTextLayerCommandCompilesARealTextLayerAtThePlayhead() {
        let project = makeProject()

        let result = AddTextLayerCommand(layerId: "text1", text: "Hello", atMs: 500).apply(to: project)

        XCTAssertEqual(result.layers.count, 1)
        let layer = result.layers.first
        XCTAssertEqual(layer?.id, "text1")
        XCTAssertEqual(layer?.type, "text")
        XCTAssertEqual(layer?.timing.start, 500)
        XCTAssertEqual(layer?.timing.duration, AddTextLayerCommand.defaultDurationMs)
        XCTAssertEqual(textContent(of: layer), "Hello")
        // A real compile, not a placeholder — at least one shaped chunk
        // with a real origin (CLAUDE.md's "Text layout stays atomic" rule).
        if case .text(let payload) = layer?.payload {
            XCTAssertFalse(payload.chunks.isEmpty)
            XCTAssertNotNil(payload.chunks.first?.x)
        } else {
            XCTFail("expected a text payload")
        }
    }

    func testAddTextLayerCommandOpensANewLaneWhenTheExistingOneOverlaps() {
        let project = makeProject()
        let first = AddTextLayerCommand(layerId: "text1", text: "A", atMs: 0).apply(to: project)

        // Overlaps "text1" (0-3000ms), so it needs its own lane.
        let second = AddTextLayerCommand(layerId: "text2", text: "B", atMs: 1000).apply(to: first)

        let orders = Set(second.layers.map(\.order))
        XCTAssertEqual(orders.count, 2)
    }

    func testAddTextLayerCommandSharesALaneWhenItDoesNotOverlap() {
        let project = makeProject()
        let first = AddTextLayerCommand(layerId: "text1", text: "A", atMs: 0).apply(to: project)

        // Starts after "text1" ends (3000ms) — same lane.
        let second = AddTextLayerCommand(layerId: "text2", text: "B", atMs: 3000).apply(to: first)

        let orders = Set(second.layers.map(\.order))
        XCTAssertEqual(orders.count, 1)
    }

    func testSetTextContentCommandReplacesContentWithoutMovingTheClip() {
        let project = makeProject()
        let added = AddTextLayerCommand(layerId: "text1", text: "Hello", atMs: 500).apply(to: project)

        let result = SetTextContentCommand(layerId: "text1", text: "Goodbye").apply(to: added)

        let layer = result.layers.first
        XCTAssertEqual(textContent(of: layer), "Goodbye")
        XCTAssertEqual(layer?.timing.start, 500)
        XCTAssertEqual(layer?.timing.duration, AddTextLayerCommand.defaultDurationMs)
        XCTAssertEqual(layer?.order, added.layers.first?.order)
    }

    func testSetTextContentCommandIsNoOpForUnknownOrNonTextLayer() {
        let videoLayer = makeVideoLayer()
        let project = makeProject().withLayers([videoLayer])

        let unknownResult = SetTextContentCommand(layerId: "nope", text: "x").apply(to: project)
        XCTAssertEqual(unknownResult.layers.count, 1)

        let wrongTypeResult = SetTextContentCommand(layerId: "clip1", text: "x").apply(to: project)
        XCTAssertEqual(wrongTypeResult.layers.first?.id, "clip1")
        if case .video = wrongTypeResult.layers.first?.payload {} else {
            XCTFail("expected the video layer to stay untouched")
        }
    }

    // MARK: - Tuỳ chỉnh

    func testSetAdjustCommandWritesAStableFilterIdAndReplacesOnASecondCall() {
        let project = makeProject().withLayers([makeVideoLayer()])

        let first = SetAdjustCommand(layerId: "clip1", values: AdjustValues(brightness: 0.2, contrast: 1, saturation: 1, exposure: 0)).apply(to: project)
        XCTAssertEqual(first.filters?.count, 1)
        let filterId = first.layers.first?.filter
        XCTAssertNotNil(filterId)
        XCTAssertEqual(first.filters?.first?.id, filterId)

        // A second, different value replaces the same filter entry rather
        // than appending a duplicate.
        let second = SetAdjustCommand(layerId: "clip1", values: AdjustValues(brightness: 0.4, contrast: 1, saturation: 1, exposure: 0)).apply(to: first)
        XCTAssertEqual(second.filters?.count, 1)
        XCTAssertEqual(second.layers.first?.filter, filterId)
    }

    func testSetAdjustCommandWithNeutralValuesClearsTheFilter() {
        let project = makeProject().withLayers([makeVideoLayer()])
        let adjusted = SetAdjustCommand(layerId: "clip1", values: AdjustValues(brightness: 0.2, contrast: 1, saturation: 1, exposure: 0)).apply(to: project)
        XCTAssertEqual(adjusted.filters?.count, 1)

        let reset = SetAdjustCommand(layerId: "clip1", values: AdjustValues()).apply(to: adjusted)
        XCTAssertNil(reset.layers.first?.filter)
        XCTAssertNil(reset.filters)
    }

    func testSetAdjustCommandIsNoOpForUnknownLayer() {
        let project = makeProject().withLayers([makeVideoLayer()])
        let result = SetAdjustCommand(layerId: "nope", values: AdjustValues(brightness: 0.3, contrast: 1, saturation: 1, exposure: 0)).apply(to: project)
        XCTAssertNil(result.filters)
        XCTAssertNil(result.layers.first?.filter)
    }

    /// Only touching Vignette should compile exactly 1 primitive (the lone
    /// `feVignette`) — not a padded chain of mostly-neutral presets for
    /// every slider group this tool has.
    func testSetAdjustCommandOnlyCompilesPresetsForSlidersThatActuallyMoved() {
        let project = makeProject().withLayers([makeVideoLayer()])

        var vignetteOnly = AdjustValues()
        vignetteOnly.vignette = 0.5
        let vignetteResult = SetAdjustCommand(layerId: "clip1", values: vignetteOnly).apply(to: project)
        XCTAssertEqual(vignetteResult.filters?.first?.primitives.count, 1)

        var sharpenOnly = AdjustValues()
        sharpenOnly.sharpen = 0.4
        let sharpenResult = SetAdjustCommand(layerId: "clip1", values: sharpenOnly).apply(to: project)
        XCTAssertEqual(sharpenResult.filters?.first?.primitives.count, 1)

        // Touching a basics-group slider (hue, part of `colorAdjust`) *and*
        // Vignette compiles both presets into the same filter's primitive
        // chain: `colorAdjust`'s own 4 primitives (hue/sat/exposure/tone)
        // + 1 `feVignette`.
        var combo = AdjustValues()
        combo.hue = 30
        combo.vignette = 0.5
        let comboResult = SetAdjustCommand(layerId: "clip1", values: combo).apply(to: project)
        XCTAssertEqual(comboResult.filters?.first?.primitives.count, 5)
    }

    /// Curves — a non-identity `curvePoints` array (the real draggable
    /// graph's own output, not a scalar slider) should be detected as
    /// non-neutral and compile to exactly 1 `feComponentTransfer`
    /// primitive, carrying the points array through verbatim.
    func testSetAdjustCommandCompilesCurvePointsVerbatim() {
        let project = makeProject().withLayers([makeVideoLayer()])
        var curved = AdjustValues()
        curved.curvePoints = [0, 0.3, 0.5, 0.6, 1]

        let result = SetAdjustCommand(layerId: "clip1", values: curved).apply(to: project)

        XCTAssertEqual(result.filters?.first?.primitives.count, 1)
        guard case .feComponentTransfer(_, let functions) = result.filters?.first?.primitives.first else {
            return XCTFail("expected a feComponentTransfer primitive")
        }
        guard case .table(let values) = functions.r else {
            return XCTFail("expected a table transfer function")
        }
        XCTAssertEqual(values, [0, 0.3, 0.5, 0.6, 1])
    }
}
