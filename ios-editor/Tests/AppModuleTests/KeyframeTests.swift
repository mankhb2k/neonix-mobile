import XCTest
@testable import NeonixEditor

/// Transform keyframes (`TransformKeyframes`): six tracks sharing times, clip-local ms, graphs on the segment start,
/// split / left-trim behaviour, and the auto-keyframe in `SetTransformCommand`.
final class KeyframeTests: XCTestCase {
    private let asset = V2ImageAsset(id: "sticker-a", uri: "a.png", mimeType: "image/png", width: 100, height: 100, integrity: nil)

    /// One sticker layer "sticker-1" starting at 1000 ms, 4000 ms long.
    private func project() -> V2Project {
        let base = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        return AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 1000, durationMs: 4000).apply(to: base)
    }

    private func layer(_ p: V2Project) -> V2Layer { p.layers.first { $0.id == "sticker-1" }! }

    private func keyframed(at locals: [Double]) -> V2Project {
        var p = project()
        for t in locals { p = AddKeyframeCommand(layerId: "sticker-1", atMs: 1000 + t).apply(to: p) }
        return p
    }

    func testAddingAKeyframeWritesOneKeyframeOnEachOfTheSixTracks() {
        let l = layer(keyframed(at: [500]))
        let tracks = (l.tracks ?? []).filter { TransformKeyframes.paths.contains($0.path) }
        XCTAssertEqual(Set(tracks.map(\.path)), TransformKeyframes.paths)
        XCTAssertEqual(tracks.count, 6)
        for track in tracks { XCTAssertEqual(track.keyframes.count, 1, track.path) }
        XCTAssertEqual(TransformKeyframes.times(of: l), [500], "times are clip-local")
    }

    func testAKeyframeNearAnExistingOneIsNotAddedAgain() {
        let p = keyframed(at: [500])
        let again = AddKeyframeCommand(layerId: "sticker-1", atMs: 1000 + 510).apply(to: p)
        XCTAssertEqual(TransformKeyframes.times(of: layer(again)), [500])
        let other = AddKeyframeCommand(layerId: "sticker-1", atMs: 1000 + 2000).apply(to: p)
        XCTAssertEqual(TransformKeyframes.times(of: layer(other)), [500, 2000])
    }

    func testRemovingTheLastKeyframeBakesItsValuesIntoTheStaticTransform() {
        var p = keyframed(at: [500])
        p = SetTransformCommand(layerId: "sticker-1", values: { var v = TransformValues(layer: layer(p), atMs: 1500); v.x = 120; v.opacity = 0.5; return v }(), atMs: 1500).apply(to: p)
        p = RemoveKeyframeCommand(layerId: "sticker-1", atMs: 1500).apply(to: p)
        let l = layer(p)
        XCTAssertNil(l.tracks)
        XCTAssertEqual(l.transform.translate.x, 120, accuracy: 0.001)
        XCTAssertEqual(l.opacity ?? 1, 0.5, accuracy: 0.001)
    }

    func testEditingAKeyframedLayerWritesAKeyframeAtThePlayheadAndInterpolates() {
        var p = keyframed(at: [0])                                   // x = 0 at local 0
        var values = TransformValues(layer: layer(p), atMs: 1000 + 2000)
        values.x = 100
        p = SetTransformCommand(layerId: "sticker-1", values: values, atMs: 1000 + 2000).apply(to: p)   // auto keyframe at local 2000
        XCTAssertEqual(TransformKeyframes.times(of: layer(p)), [0, 2000])
        XCTAssertEqual(sampleLayer(layer(p), atMs: 1000).translateX, 0, accuracy: 0.001)
        XCTAssertEqual(sampleLayer(layer(p), atMs: 1000 + 1000).translateX, 50, accuracy: 0.5, "linear in between")
        XCTAssertEqual(sampleLayer(layer(p), atMs: 1000 + 2000).translateX, 100, accuracy: 0.001)
        XCTAssertEqual(layer(p).transform.translate.x, 0, "the static transform is untouched")
    }

    func testAGraphIsStoredOnTheSegmentStartAndChangesTheCurve() {
        var p = keyframed(at: [0])
        var values = TransformValues(layer: layer(p), atMs: 3000); values.x = 100
        p = SetTransformCommand(layerId: "sticker-1", values: values, atMs: 3000).apply(to: p)
        let linearMid = sampleLayer(layer(p), atMs: 2000).translateX
        XCTAssertEqual(TransformKeyframes.segmentStart(of: layer(p), atMs: 2000), 0)
        XCTAssertNil(TransformKeyframes.segmentStart(of: layer(p), atMs: 3500), "past the last keyframe there is no segment")
        let easeIn = LabEasing.catalogue.first { $0.id == "cubic-in" }!
        p = SetKeyframeEasingCommand(layerId: "sticker-1", segmentStartMs: 0, easing: easeIn.v2).apply(to: p)
        XCTAssertLessThan(sampleLayer(layer(p), atMs: 2000).translateX, linearMid, "Cubic In starts slow")
        XCTAssertEqual(LabEasing(v2: TransformKeyframes.easing(of: layer(p), segmentStart: 0)).id, "cubic-in")
        XCTAssertEqual(LabEasing(v2: nil), .original)
    }

    func testMirrorSurvivesATransformEditOnAKeyframedLayer() {
        var p = MirrorLayerCommand(layerId: "sticker-1").apply(to: keyframed(at: [0]))
        var values = TransformValues(layer: layer(p), atMs: 1000); values.scale = 2
        p = SetTransformCommand(layerId: "sticker-1", values: values, atMs: 1000).apply(to: p)
        XCTAssertEqual(sampleLayer(layer(p), atMs: 1000).scaleX, -2, accuracy: 0.001)
        XCTAssertEqual(sampleLayer(layer(p), atMs: 1000).scaleY, 2, accuracy: 0.001)
    }

    func testSplitInsideTheAnimationAddsAKeyframeAtEachSideOfTheCut() {
        var p = keyframed(at: [500, 1500, 3000])
        p = SplitClipCommand(layerId: "sticker-1", atMs: 1000 + 2000).apply(to: p)
        let first = p.layers.first { $0.id == "sticker-1" }!
        let second = p.layers.first { $0.id != "sticker-1" && $0.id.hasPrefix("sticker-1") }!
        XCTAssertEqual(TransformKeyframes.times(of: first), [500, 1500, 2000], "a keyframe at the end of the first half")
        XCTAssertEqual(TransformKeyframes.times(of: second), [0, 1000], "a keyframe at the start of the second half, re-timed")
    }

    func testSplitOutsideTheAnimatedRangeAddsNothing() {
        var p = keyframed(at: [2500, 3500])
        p = SplitClipCommand(layerId: "sticker-1", atMs: 1000 + 1000).apply(to: p)
        let first = p.layers.first { $0.id == "sticker-1" }!
        let second = p.layers.first { $0.id != "sticker-1" && $0.id.hasPrefix("sticker-1") }!
        XCTAssertTrue(TransformKeyframes.times(of: first).isEmpty)
        XCTAssertEqual(TransformKeyframes.times(of: second), [1500, 2500])
    }

    /// The two halves, played one after the other, must trace the original curve, linear or eased.
    func testSplitKeepsTheMovementContinuousForALinearAndAnEasedSegment() {
        for easingId in ["original", "cubic-in", "back-out"] {
            var p = keyframed(at: [0])
            var values = TransformValues(layer: layer(p), atMs: 1000 + 4000); values.x = 200
            p = SetTransformCommand(layerId: "sticker-1", values: values, atMs: 1000 + 4000).apply(to: p)
            let easing = LabEasing.catalogue.first { $0.id == easingId }?.v2
            p = SetKeyframeEasingCommand(layerId: "sticker-1", segmentStartMs: 0, easing: easing).apply(to: p)
            let original = layer(p)
            let split = SplitClipCommand(layerId: "sticker-1", atMs: 1000 + 1500).apply(to: p)
            let first = split.layers.first { $0.id == "sticker-1" }!
            let second = split.layers.first { $0.id != "sticker-1" && $0.id.hasPrefix("sticker-1") }!
            for t in stride(from: 0.0, through: 4000.0, by: 250.0) {
                let want = sampleLayer(original, atMs: 1000 + t).translateX
                let got = t <= 1500 ? sampleLayer(first, atMs: 1000 + t).translateX : sampleLayer(second, atMs: 1000 + t).translateX
                XCTAssertEqual(got, want, accuracy: 0.05, "\(easingId) at \(t) ms")
            }
        }
    }

    func testALeftTrimMovesKeyframesWithThePictureARightTrimDoesNot() {
        let p = keyframed(at: [1000, 2000])
        let left = TrimClipCommand(layerId: "sticker-1", start: 1000 + 600, duration: 4000 - 600, trimStart: nil, trimEnd: nil).apply(to: p)
        XCTAssertEqual(TransformKeyframes.times(of: layer(left)), [400, 1400])
        let right = TrimClipCommand(layerId: "sticker-1", start: 1000, duration: 3000, trimStart: nil, trimEnd: nil).apply(to: p)
        XCTAssertEqual(TransformKeyframes.times(of: layer(right)), [1000, 2000])
    }

    func testOnlyKeyframesInsideTheClipAreDrawnOnTheTimeline() {
        let p = keyframed(at: [1000, 2000])
        let left = TrimClipCommand(layerId: "sticker-1", start: 1000 + 1500, duration: 4000 - 1500, trimStart: nil, trimEnd: nil).apply(to: p)
        XCTAssertEqual(TransformKeyframes.visibleTimelineTimes(of: layer(left)), [1000 + 1500 + 500], "the first keyframe went before the clip's start")
    }
}
