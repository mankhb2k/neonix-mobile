import XCTest
@testable import NeonixEditor

/// Covers `TimelineView.swift`'s `reflowLane(...)`/`previousClipEnd(...)`/
/// `nextClipStart(...)` — the drag-to-trim ripple-reflow math (2026-10-08,
/// analyzed against a CapCut reference screenshot) — directly, the same
/// "test pure logic, not only through the simulator" precedent as
/// `EditorCommandTests`. These 3 functions were changed from `private` to
/// internal specifically so this file could reach them via `@testable
/// import` without needing a full gesture/view harness.
final class LaneReflowTests: XCTestCase {
    /// `reflowLane`/`previousClipEnd`/`nextClipStart` never inspect a
    /// layer's own `type`/payload — only `id`/`timing` — so every fixture
    /// here is a plain video layer regardless of what it conceptually
    /// represents in a given test.
    private func makeLayer(id: String, start: Double, duration: Double) -> V2Layer {
        V2Layer(
            id: id,
            frame: V2Frame(width: 360, height: 640),
            transform: .identity,
            timing: V2Timing(start: start, duration: duration),
            payload: .video(V2VideoPayload(assetId: "asset1"))
        )
    }

    func testReflowLaneCascadesForwardWhenExtendingRight() {
        // A: 0-100, B: 100-300, C: 300-400 — extend A to end at 150.
        let a = makeLayer(id: "a", start: 0, duration: 100)
        let b = makeLayer(id: "b", start: 100, duration: 200)
        let c = makeLayer(id: "c", start: 300, duration: 100)

        let result = reflowLane(laneClips: [a, b, c], draggedLayerId: "a", newDraggedStart: 0, newDraggedDuration: 150)

        XCTAssertEqual(result.draggedStart, 0)
        // B pushed later by exactly the 50ms overlap, duration untouched.
        XCTAssertEqual(result.siblingStarts["b"], 150)
        // C cascades too, gluing to B's new end (150 + 200 = 350).
        XCTAssertEqual(result.siblingStarts["c"], 350)
    }

    func testReflowLaneCascadesForwardWhenShrinking() {
        // Shrinking A to end at 50 should pull B (and C) back closer.
        let a = makeLayer(id: "a", start: 0, duration: 100)
        let b = makeLayer(id: "b", start: 100, duration: 200)
        let c = makeLayer(id: "c", start: 300, duration: 100)

        let result = reflowLane(laneClips: [a, b, c], draggedLayerId: "a", newDraggedStart: 0, newDraggedDuration: 50)

        XCTAssertEqual(result.siblingStarts["b"], 50)
        XCTAssertEqual(result.siblingStarts["c"], 250)
    }

    func testReflowLaneCascadesBackwardWhenExtendingLeftWithRoomToSpare() {
        // A: 0-100 (duration 100, but only 60ms "in use" conceptually —
        // modeled here as slack simply by starting B further out), B
        // (dragged): 150-350. Extending B's start earlier to 120 should
        // pull A's own position earlier to keep them glued (A's own
        // duration stays 100, so its start becomes 120 - 100 = 20).
        let a = makeLayer(id: "a", start: 0, duration: 100)
        let b = makeLayer(id: "b", start: 150, duration: 200)

        let result = reflowLane(laneClips: [a, b], draggedLayerId: "b", newDraggedStart: 120, newDraggedDuration: 230)

        XCTAssertEqual(result.draggedStart, 120)
        XCTAssertEqual(result.siblingStarts["a"], 20)
    }

    func testReflowLaneClampsAtZeroWhenNoSlackExists() {
        // A: 0-100, B (dragged): 100-300, tightly packed (no slack before
        // B at all). Trying to extend B's start to -30 has nowhere to
        // push A into (A would need to start at -130) — the whole
        // cascade should snap back so A lands at exactly 0, and B's own
        // resolved start reverts to its original 100 (no net movement).
        let a = makeLayer(id: "a", start: 0, duration: 100)
        let b = makeLayer(id: "b", start: 100, duration: 200)

        let result = reflowLane(laneClips: [a, b], draggedLayerId: "b", newDraggedStart: -30, newDraggedDuration: 330)

        XCTAssertEqual(result.siblingStarts["a"], 0)
        XCTAssertEqual(result.draggedStart, 100)
    }

    func testPreviousClipEndAndNextClipStartFindTheRightNeighbors() {
        let a = makeLayer(id: "a", start: 0, duration: 100)
        let b = makeLayer(id: "b", start: 500, duration: 100)
        let clips = [a, b]

        XCTAssertEqual(previousClipEnd(in: clips, before: "b", originalStart: 500), 100)
        XCTAssertEqual(nextClipStart(in: clips, after: "a", originalStart: 0), 500)
        XCTAssertNil(previousClipEnd(in: clips, before: "a", originalStart: 0))
        XCTAssertNil(nextClipStart(in: clips, after: "b", originalStart: 500))
    }

    func testIsPushLaneType() {
        XCTAssertTrue(isPushLaneType("video"))
        XCTAssertTrue(isPushLaneType("image"))
        XCTAssertFalse(isPushLaneType("text"))
        XCTAssertFalse(isPushLaneType("shape"))
    }
}
