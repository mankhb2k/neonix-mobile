import XCTest
@testable import NeonixEditor

final class VideoTimeMappingTests: XCTestCase {
    private func makeVideoLayer(start: Double, duration: Double, trimStart: Double?, rate: Double? = nil) -> V2Layer {
        V2Layer(
            id: "clip",
            order: 0,
            frame: V2Frame(width: 360, height: 640),
            transform: .identity,
            timing: V2Timing(start: start, duration: duration),
            payload: .video(V2VideoPayload(assetId: "asset", trimStart: trimStart, playbackRate: rate))
        )
    }

    func testSourceTimeIncludesTrimStart() throws {
        // A clip left-trimmed by 2s, placed at 1s on the timeline.
        let mapping = try XCTUnwrap(VideoTimeMapping(layer: makeVideoLayer(start: 1000, duration: 5000, trimStart: 2000)))
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: 1000), 2000)
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: 3500), 4500)
        // Clamped to the clip's own range on both sides.
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: 0), 2000)
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: 99_000), 7000)
    }

    func testTimelineTimeIsInverseOfSourceTime() throws {
        let mapping = try XCTUnwrap(VideoTimeMapping(layer: makeVideoLayer(start: 1000, duration: 5000, trimStart: 2000, rate: 2)))
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: 2000), 4000)
        XCTAssertEqual(mapping.timelineMs(atSourceMs: 4000), 2000)
    }

    func testSplitHalvesAreContinuousButADifferentTrimIsNot() throws {
        let original = makeVideoLayer(start: 0, duration: 8000, trimStart: 2000)
        let project = V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
            assets: [],
            layers: [original]
        )
        let split = SplitClipCommand(layerId: "clip", atMs: 3000).apply(to: project)
        let first = try XCTUnwrap(VideoTimeMapping(layer: split.layers[0]))
        let second = try XCTUnwrap(VideoTimeMapping(layer: split.layers[1]))
        XCTAssertTrue(first.isContinuous(with: second))

        let retrimmed = try XCTUnwrap(VideoTimeMapping(layer: makeVideoLayer(start: 3000, duration: 5000, trimStart: 0)))
        XCTAssertFalse(first.isContinuous(with: retrimmed))
    }

    func testNonVideoLayerHasNoMapping() {
        let group = V2Layer(
            id: "g",
            order: 1,
            frame: V2Frame(width: 100, height: 40),
            transform: .identity,
            timing: V2Timing(start: 0, duration: 1000),
            payload: .group(render3d: nil)
        )
        XCTAssertNil(VideoTimeMapping(layer: group))
    }
}
