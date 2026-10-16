import XCTest
@testable import NeonixEditor

/// `MoveClipCommand` and `ClipMove.resolve`: free clips move in time and between lanes of their own kind; anything else fails closed.
final class MoveClipTests: XCTestCase {
    private func layer(_ id: String, order: Int, start: Double, duration: Double = 1000) -> V2Layer {
        V2Layer(id: id, order: order, frame: V2Frame(width: 360, height: 640), transform: .identity,
                timing: V2Timing(start: start, duration: duration), payload: .video(V2VideoPayload(assetId: "a")))
    }

    private func project(_ layers: [V2Layer]) -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: layers)
    }

    private func order(_ p: V2Project, _ id: String) -> Int? { p.layers.first { $0.id == id }?.order }
    private func start(_ p: V2Project, _ id: String) -> Double? { p.layers.first { $0.id == id }?.timing.start }

    func testMovesInTimeWithinItsLane() {
        let p = project([layer("main", order: 0, start: 0, duration: 5000), layer("sticker-1", order: 1, start: 0)])
        let moved = MoveClipCommand(layerId: "sticker-1", start: 2500, target: .lane(1)).apply(to: p)
        XCTAssertEqual(start(moved, "sticker-1"), 2500)
        XCTAssertEqual(order(moved, "sticker-1"), 1)
    }

    func testStartIsClampedAtZero() {
        let p = project([layer("sticker-1", order: 1, start: 500)])
        XCTAssertEqual(start(MoveClipCommand(layerId: "sticker-1", start: -300, target: .lane(1)).apply(to: p), "sticker-1"), 0)
    }

    func testMovesToAnotherLaneOfTheSameKind() {
        let p = project([layer("sticker-1", order: 1, start: 0), layer("sticker-2", order: 2, start: 3000)])
        let moved = MoveClipCommand(layerId: "sticker-1", start: 0, target: .lane(2)).apply(to: p)
        XCTAssertEqual(order(moved, "sticker-1"), 2)
    }

    func testLaneOfAnotherKindOrAnOverlapFailsClosed() {
        let p = project([layer("sticker-1", order: 1, start: 0), layer("overlay-1", order: 2, start: 0), layer("sticker-2", order: 3, start: 500)])
        let otherKind = MoveClipCommand(layerId: "sticker-1", start: 0, target: .lane(2)).apply(to: p)
        XCTAssertEqual(order(otherKind, "sticker-1"), 1)
        let overlap = MoveClipCommand(layerId: "sticker-1", start: 0, target: .lane(3)).apply(to: p)
        XCTAssertEqual(order(overlap, "sticker-1"), 1)
    }

    func testNewLaneShiftsTheLanesFromThereDown() {
        let p = project([layer("main", order: 0, start: 0, duration: 5000), layer("sticker-1", order: 1, start: 0),
                         layer("overlay-1", order: 2, start: 0)])
        let moved = MoveClipCommand(layerId: "sticker-1", start: 100, target: .newLane(at: 2)).apply(to: p)
        XCTAssertEqual(order(moved, "sticker-1"), 2)
        XCTAssertEqual(order(moved, "overlay-1"), 3)
        XCTAssertEqual(order(moved, "main"), 0)
        XCTAssertEqual(start(moved, "sticker-1"), 100)
    }

    func testNewLaneAtOrAboveTheMainLaneFailsClosed() {
        let p = project([layer("main", order: 0, start: 0, duration: 5000), layer("sticker-1", order: 1, start: 0)])
        XCTAssertEqual(order(MoveClipCommand(layerId: "sticker-1", start: 0, target: .newLane(at: 0)).apply(to: p), "sticker-1"), 1)
    }

    func testTheMainLanesClipsCannotBeMoved() {
        let p = project([layer("main", order: 0, start: 0, duration: 5000), layer("sticker-1", order: 1, start: 0)])
        let moved = MoveClipCommand(layerId: "main", start: 1000, target: .lane(1)).apply(to: p)
        XCTAssertEqual(start(moved, "main"), 0)
        XCTAssertEqual(order(moved, "main"), 0)
    }

    func testResolvePrefersAFittingLaneElseOpensANewOne() {
        let layers = [layer("main", order: 0, start: 0, duration: 5000), layer("sticker-1", order: 1, start: 0),
                      layer("overlay-1", order: 2, start: 0), layer("sticker-2", order: 3, start: 0)]
        let bands: [(order: Int, minY: CGFloat, maxY: CGFloat)] = [(0, 0, 48), (1, 52, 82), (2, 86, 124), (3, 128, 158)]
        let moving = layers[1]
        // Over its own lane: stays.
        XCTAssertEqual(ClipMove.resolve(layers: layers, moving: moving, start: 0, bands: bands, y: 60), .lane(1))
        // Over the overlay lane: wrong kind -> a new lane before the first lane whose middle is below, i.e. after it.
        XCTAssertEqual(ClipMove.resolve(layers: layers, moving: moving, start: 0, bands: bands, y: 118), .newLane(at: 3))
        XCTAssertEqual(ClipMove.resolve(layers: layers, moving: moving, start: 0, bands: bands, y: 90), .newLane(at: 2))
        // Over a lane of its kind but occupied at that time: new lane.
        XCTAssertEqual(ClipMove.resolve(layers: layers, moving: moving, start: 500, bands: bands, y: 150), .newLane(at: 4))
        // Far above (over the main lane): never at or above the main lane.
        XCTAssertEqual(ClipMove.resolve(layers: layers, moving: moving, start: 0, bands: bands, y: -20), .newLane(at: 1))
        // Below everything: after the last lane.
        XCTAssertEqual(ClipMove.resolve(layers: layers, moving: moving, start: 0, bands: bands, y: 300), .newLane(at: 4))
    }
}
