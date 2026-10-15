import XCTest
@testable import NeonixEditor

/// Speed, Normal: the command (duration, lane ripple, keyframes), what Split does at a rate, and the ruler's mapping.
final class SpeedTests: XCTestCase {
    private func video(_ id: String, start: Double, duration: Double, trimStart: Double = 0, rate: Double? = nil) -> V2Layer {
        V2Layer(
            id: id, order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
            timing: V2Timing(start: start, duration: duration),
            payload: .video(V2VideoPayload(assetId: "asset", trimStart: trimStart, playbackRate: rate))
        )
    }

    /// A(0-4000) B(4000-8000) C(8000-10000) on one lane.
    private func lane() -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [
            video("A", start: 0, duration: 4000), video("B", start: 4000, duration: 4000, trimStart: 1000), video("C", start: 8000, duration: 2000),
        ])
    }

    private func layer(_ p: V2Project, _ id: String) -> V2Layer { p.layers.first { $0.id == id }! }
    private func rate(_ l: V2Layer) -> Double { VideoTimeMapping(layer: l)?.rate ?? 0 }

    func testFasterIsShorterAndTheFootageStaysTheSame() {
        let p = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: lane())
        let b = layer(p, "B")
        XCTAssertEqual(b.timing.duration, 2000)
        XCTAssertEqual(rate(b), 2)
        guard case .video(let payload) = b.payload else { return XCTFail() }
        XCTAssertEqual(payload.trimStart, 1000, "the clip still starts at the same frame of the file")
        XCTAssertEqual(payload.trimStart! + b.timing.duration * 2, 5000, "and ends at the same one (1000 + 4000)")
        let back = SetClipSpeedCommand(layerId: "B", rate: 1).apply(to: p)
        XCTAssertEqual(layer(back, "B").timing.duration, 4000)
        guard case .video(let restored) = layer(back, "B").payload else { return XCTFail() }
        XCTAssertNil(restored.playbackRate, "1x is stored as no rate")
        let slow = SetClipSpeedCommand(layerId: "B", rate: 0.5).apply(to: lane())
        XCTAssertEqual(layer(slow, "B").timing.duration, 8000)
    }

    func testTheLaneFollowsInBothDirections() {
        let fast = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: lane())
        XCTAssertEqual(layer(fast, "A").timing.start, 0)
        XCTAssertEqual(layer(fast, "B").timing.start, 4000)
        XCTAssertEqual(layer(fast, "C").timing.start, 6000, "the later clip closes the gap")
        let slow = SetClipSpeedCommand(layerId: "B", rate: 0.5).apply(to: lane())
        XCTAssertEqual(layer(slow, "C").timing.start, 12000, "and makes room")
        XCTAssertEqual(layer(slow, "A").timing.duration, 4000); XCTAssertEqual(layer(slow, "C").timing.duration, 2000)
    }

    func testAClipThatAlreadyHasARateChangesFromThatRate() {
        var p = lane()
        p = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: p)        // 2000 ms
        p = SetClipSpeedCommand(layerId: "B", rate: 4).apply(to: p)        // the same 4000 ms of footage at 4x
        XCTAssertEqual(layer(p, "B").timing.duration, 1000)
        XCTAssertEqual(rate(layer(p, "B")), 4)
        XCTAssertEqual(layer(p, "C").timing.start, 5000)
    }

    func testKeyframesScaleWithTheClip() throws {
        var p = lane()
        p = AddKeyframeCommand(layerId: "B", atMs: 6000).apply(to: p)   // the playhead: 2000 ms into B, which starts at 4000
        XCTAssertEqual(TransformKeyframes.times(of: layer(p, "B")), [2000])
        let fast = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: p)
        XCTAssertEqual(TransformKeyframes.times(of: layer(fast, "B")), [1000], "the keyframe stays on the same picture")
    }

    func testFailsClosedAndRespectsTheRange() {
        let p = lane()
        XCTAssertEqual(SetClipSpeedCommand(layerId: "missing", rate: 2).apply(to: p).layers.map(\.timing.duration), p.layers.map(\.timing.duration))
        XCTAssertEqual(SetClipSpeedCommand(layerId: "B", rate: 1).apply(to: p).layers.map(\.timing.duration), p.layers.map(\.timing.duration), "no change, no work")
        XCTAssertEqual(rate(layer(SetClipSpeedCommand(layerId: "B", rate: 50).apply(to: p), "B")), 9, "never above 9x")
        XCTAssertEqual(rate(layer(SetClipSpeedCommand(layerId: "B", rate: 0.01).apply(to: p), "B")), 0.1)
        let text = AddTextLayerCommand(layerId: "T", text: "Hi", atMs: 0).apply(to: p)
        XCTAssertEqual(SetClipSpeedCommand(layerId: "T", rate: 2).apply(to: text).layers.map(\.timing.duration), text.layers.map(\.timing.duration), "text has no speed")
        let tiny = V2Project(composition: p.composition, assets: [], layers: [video("S", start: 0, duration: 10)])
        XCTAssertGreaterThanOrEqual(layer(SetClipSpeedCommand(layerId: "S", rate: 9).apply(to: tiny), "S").timing.duration, 1000.0 / 30 - 1e-9, "never under one frame")
    }

    func testSplitAtARateMovesTheSourceByRateTimesTheCut() {
        let p = V2Project(composition: lane().composition, assets: [], layers: [video("V", start: 0, duration: 4000, trimStart: 1000, rate: 2)])
        let split = SplitClipCommand(layerId: "V", atMs: 1000).apply(to: p)
        XCTAssertEqual(split.layers.count, 2)
        XCTAssertEqual(split.layers[0].timing.duration, 1000); XCTAssertEqual(split.layers[1].timing.duration, 3000)
        guard case .video(let second) = split.layers[1].payload else { return XCTFail() }
        XCTAssertEqual(second.trimStart, 3000, "1000 + 1000 ms of timeline x 2")
        XCTAssertEqual(second.playbackRate, 2, "both halves keep the speed")
        let mapping = VideoTimeMapping(layer: split.layers[1])!
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: 1000), 3000, accuracy: 1e-9, "the second half picks up exactly where the first left off")
    }

    func testAnAnimationFollowsTheNewLength() {
        var p = lane()
        p = SetAnimationCommand(layerId: "B", slot: .out, presetId: "fade", durationMs: 500).apply(to: p)
        p = AnimationWrappers.normalized(SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: p))
        let wrapper = p.layers.first { $0.id.hasPrefix("B~anim~") }!
        XCTAssertEqual(wrapper.timing.duration, 2000, "the wrapper mirrors the clip, so the exit still ends at the clip's end")
    }

    func testTheSpeedRulerIsLinearOneTickPerTenthOfAnX() {
        let ruler = RulerMapping.speed
        XCTAssertEqual(ruler.tickCount, 90, "0.1x ... 9x in steps of 0.1x")
        XCTAssertEqual(ruler.value(0), 0.1); XCTAssertEqual(ruler.value(89), 9)
        XCTAssertEqual(ruler.index(1), 9, "1x is the tenth tick: nine ticks to its left (0.9x ... 0.1x)")
        XCTAssertEqual(ruler.value(ruler.index(1) - 1), 0.9); XCTAssertEqual(ruler.value(ruler.index(1) - 9), 0.1)
        XCTAssertEqual(ruler.value(ruler.index(1) + 1), 1.1); XCTAssertEqual(ruler.value(ruler.index(1) + 2), 1.2)
        for i in 1..<ruler.tickCount { XCTAssertEqual(ruler.value(i) - ruler.value(i - 1), 0.1, accuracy: 1e-9, "every tick is exactly 0.1x") }
        XCTAssertTrue(ruler.isMajor(9)); XCTAssertTrue(ruler.isMajor(19)); XCTAssertFalse(ruler.isMajor(10))
    }
}
