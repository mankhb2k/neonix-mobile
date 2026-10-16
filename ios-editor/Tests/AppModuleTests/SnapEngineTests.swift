import XCTest
@testable import NeonixEditor

/// `SnapEngine.resolve`: 8 pt to capture, 14 pt to let go, the closest edge/point wins.
final class SnapEngineTests: XCTestCase {
    private let px = 0.1   // 10 ms per point

    func testAnEdgeWithinEightPointsSnapsAndOneBeyondDoesNot() {
        let near = SnapEngine.resolve(edges: [1000], points: [1070], pxPerMs: px, held: nil)   // 7 pt
        XCTAssertEqual(near, SnapEngine.Result(deltaMs: 70, point: 1070))
        let far = SnapEngine.resolve(edges: [1000], points: [1090], pxPerMs: px, held: nil)    // 9 pt
        XCTAssertEqual(far, SnapEngine.Result(deltaMs: 0, point: nil))
    }

    func testOnceSnappedItHoldsUntilFourteenPoints() {
        let held = SnapEngine.resolve(edges: [1120], points: [1000], pxPerMs: px, held: 1000)  // 12 pt away, held
        XCTAssertEqual(held, SnapEngine.Result(deltaMs: -120, point: 1000))
        let released = SnapEngine.resolve(edges: [1150], points: [1000], pxPerMs: px, held: 1000)   // 15 pt: let go
        XCTAssertEqual(released, SnapEngine.Result(deltaMs: 0, point: nil))
    }

    func testTheClosestEdgeAndPointWin() {
        // A clip 1000...1500: its end is 20 ms (2 pt) from 1520, its start 60 ms (6 pt) from 940.
        let r = SnapEngine.resolve(edges: [1000, 1500], points: [940, 1520], pxPerMs: px, held: nil)
        XCTAssertEqual(r, SnapEngine.Result(deltaMs: 20, point: 1520))
    }

    func testAKeyframeEdgeCanSnapLikeAClipEdge() {
        // Edges: start 0, end 3000 and a keyframe at 1500 that sits 40 ms (4 pt) from the playhead point 1540.
        let r = SnapEngine.resolve(edges: [0, 3000, 1500], points: [1540], pxPerMs: px, held: nil)
        XCTAssertEqual(r, SnapEngine.Result(deltaMs: 40, point: 1540))
    }

    func testThresholdsFollowTheZoomNotTheTime() {
        // The same 50 ms gap is 5 pt zoomed in (snaps) and 0.5 pt zoomed out (also snaps), but 100 ms is 10 pt zoomed in (no).
        XCTAssertNotNil(SnapEngine.resolve(edges: [0], points: [50], pxPerMs: 0.1, held: nil).point)
        XCTAssertNil(SnapEngine.resolve(edges: [0], points: [100], pxPerMs: 0.1, held: nil).point)
        XCTAssertNotNil(SnapEngine.resolve(edges: [0], points: [900], pxPerMs: 0.008, held: nil).point)   // 7.2 pt
    }

    func testNothingToSnapToLeavesTheEdgeAlone() {
        XCTAssertEqual(SnapEngine.resolve(edges: [500], points: [], pxPerMs: px, held: nil), SnapEngine.Result(deltaMs: 0, point: nil))
    }
}
