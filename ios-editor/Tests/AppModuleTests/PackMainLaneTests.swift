import XCTest
@testable import NeonixEditor

/// The main-lane magnet (`PackMainLaneCommand`, and `DeleteClipCommand` on a main-lane clip).
final class PackMainLaneTests: XCTestCase {
    private func layer(_ id: String, order: Int = 0, start: Double, duration: Double, video: Bool = true) -> V2Layer {
        V2Layer(
            id: id, order: order, frame: V2Frame(width: 360, height: 640), transform: .identity,
            timing: V2Timing(start: start, duration: duration),
            payload: video ? .video(V2VideoPayload(assetId: "a")) : .group(render3d: nil)
        )
    }

    private func project(_ layers: [V2Layer]) -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: layers)
    }

    private func starts(_ p: V2Project) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: p.layers.map { ($0.id, $0.timing.start) })
    }

    func testAfterALeftTrimTheFirstClipGoesBackToZeroAndTheRestFollow() {
        // The first clip was trimmed from the left: it now starts at 4500 and is 1500 long (hole 0-4500).
        let p = project([layer("a", start: 4500, duration: 1500), layer("b", start: 6000, duration: 2000)])
        let packed = PackMainLaneCommand().apply(to: p)
        XCTAssertEqual(starts(packed), ["a": 0, "b": 1500])
        XCTAssertEqual(packed.layers.first { $0.id == "a" }?.timing.duration, 1500, "durations are untouched")
    }

    func testAHoleInTheMiddleIsClosed() {
        let p = project([layer("a", start: 0, duration: 1000), layer("b", start: 1800, duration: 1000), layer("c", start: 2800, duration: 500)])
        XCTAssertEqual(starts(PackMainLaneCommand().apply(to: p)), ["a": 0, "b": 1000, "c": 2000])
    }

    func testOrderComesFromStartNotFromArrayPosition() {
        let p = project([layer("late", start: 3000, duration: 500), layer("early", start: 1000, duration: 500)])
        XCTAssertEqual(starts(PackMainLaneCommand().apply(to: p)), ["early": 0, "late": 500])
    }

    func testOnlyTheMainLaneIsPacked() {
        let overlayText = layer("t", order: 2, start: 3000, duration: 1000, video: false)
        let overlayVideo = layer("v2", order: 3, start: 5000, duration: 1000)
        let p = project([layer("a", start: 2000, duration: 1000), overlayText, overlayVideo])
        let packed = starts(PackMainLaneCommand().apply(to: p))
        XCTAssertEqual(packed["a"], 0)
        XCTAssertEqual(packed["t"], 3000, "text keeps its time")
        XCTAssertEqual(packed["v2"], 5000, "other lanes keep their time")
    }

    func testPackingTwiceChangesNothingMore() {
        let p = project([layer("a", start: 700, duration: 1000), layer("b", start: 2500, duration: 1000)])
        let once = PackMainLaneCommand().apply(to: p)
        XCTAssertEqual(starts(PackMainLaneCommand().apply(to: once)), starts(once))
    }

    func testAnAlreadyPackedLaneAndAnEmptyProjectAreUntouched() {
        let packed = project([layer("a", start: 0, duration: 1000), layer("b", start: 1000, duration: 1000)])
        XCTAssertEqual(starts(PackMainLaneCommand().apply(to: packed)), ["a": 0, "b": 1000])
        XCTAssertTrue(PackMainLaneCommand().apply(to: project([])).layers.isEmpty)
    }

    func testDeletingAMainLaneClipClosesTheHoleButDeletingAnOverlayDoesNot() {
        let overlay = layer("o", order: 1, start: 4000, duration: 1000, video: false)
        let p = project([layer("a", start: 0, duration: 1000), layer("b", start: 1000, duration: 1000), layer("c", start: 2000, duration: 1000), overlay])
        XCTAssertEqual(starts(DeleteClipCommand(layerId: "b").apply(to: p)), ["a": 0, "c": 1000, "o": 4000])

        let other = project([layer("a", start: 0, duration: 1000), layer("c", start: 1000, duration: 1000), overlay, layer("t2", order: 1, start: 6000, duration: 500, video: false)])
        XCTAssertEqual(starts(DeleteClipCommand(layerId: "o").apply(to: other))["t2"], 6000)
    }

    // MARK: negative times while dragging (main-lane magnet)

    private func clip(_ id: String, _ start: Double, _ duration: Double) -> V2Layer { layer(id, start: start, duration: duration) }

    func testReflowKeepsEverythingAtOrAboveZeroByDefault() {
        // B's left edge dragged to 500 pushes A (1000 long) to -500: the default floor shifts the whole lane right.
        let result = reflowLane(laneClips: [clip("a", 0, 1000), clip("b", 1000, 2000)], draggedLayerId: "b",
                                newDraggedStart: 500, newDraggedDuration: 2500)
        XCTAssertEqual(result.siblingStarts["a"], 0)
        XCTAssertEqual(result.draggedStart, 1000)
    }

    func testMainLaneModeLetsTheLaneGoNegativeAndPackBringsItBack() {
        let result = reflowLane(laneClips: [clip("a", 0, 1000), clip("b", 1000, 2000)], draggedLayerId: "b",
                                newDraggedStart: 500, newDraggedDuration: 2500, floorAtZero: false)
        XCTAssertEqual(result.siblingStarts["a"], -500, "the clip in front is pushed past t0")
        XCTAssertEqual(result.draggedStart, 500)

        // What the drag leaves in the project, then the finger lifts:
        let dragged = project([layer("a", start: -500, duration: 1000), layer("b", start: 500, duration: 2500)])
        XCTAssertEqual(starts(PackMainLaneCommand().apply(to: dragged)), ["a": 0, "b": 1000])
    }

    func testTheFirstClipExtendedLeftOfZeroIsPackedToZero() {
        let dragged = project([layer("a", start: -1700, duration: 4000), layer("b", start: 2300, duration: 1000)])
        let packed = PackMainLaneCommand().apply(to: dragged)
        XCTAssertEqual(starts(packed), ["a": 0, "b": 4000])
        XCTAssertEqual(packed.layers.first { $0.id == "a" }?.timing.duration, 4000)
    }

    // MARK: where the playhead lands after a trim

    func testLeftHandleLandsOnTheClipStart() {
        let clip = layer("a", start: 2500, duration: 4000)
        XCTAssertEqual(trimLandingTimeMs(isLeadingHandle: true, layer: clip, fps: 30), 2500)
    }

    func testRightHandleLandsOneFrameBeforeTheClipEnd() {
        let clip = layer("a", start: 2500, duration: 4000)
        XCTAssertEqual(trimLandingTimeMs(isLeadingHandle: false, layer: clip, fps: 30), 6500 - 1000.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(trimLandingTimeMs(isLeadingHandle: false, layer: clip, fps: 60), 6500 - 1000.0 / 60, accuracy: 1e-9)
    }

    func testARightHandleNeverLandsBeforeTheClipStart() {
        let tiny = layer("a", start: 1000, duration: 10)   // shorter than one frame
        XCTAssertEqual(trimLandingTimeMs(isLeadingHandle: false, layer: tiny, fps: 30), 1000)
        XCTAssertEqual(trimLandingTimeMs(isLeadingHandle: false, layer: tiny, fps: 0), 1000, "a bogus fps must not blow up")
    }
}
