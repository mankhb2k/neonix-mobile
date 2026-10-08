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
}
