import XCTest
@testable import NeonixEditor

/// Overlay, Replace and Duplicate for video, photo and text clips.
final class MediaCommandTests: XCTestCase {
    private let photo = V2Asset.image(V2ImageAsset(id: "photo-1", uri: "a.jpg", width: 4000, height: 3000))
    private let tall = V2Asset.image(V2ImageAsset(id: "photo-2", uri: "b.jpg", width: 1000, height: 4000))
    private let movie = V2Asset.video(V2VideoAsset(id: "movie-1", uri: "m.mov", width: 1920, height: 1080, duration: 7500))

    private func video(_ id: String, order: Int = 0, start: Double, duration: Double, trimStart: Double = 0) -> V2Layer {
        V2Layer(id: id, order: order, frame: V2Frame(width: 360, height: 640), transform: .identity, timing: V2Timing(start: start, duration: duration),
                payload: .video(V2VideoPayload(assetId: "movie-0", trimStart: trimStart)))
    }

    /// A(0-4000) B(4000-8000) C(8000-10000) on the main lane.
    private func lane() -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [
            video("A", start: 0, duration: 4000), video("B", start: 4000, duration: 4000), video("C", start: 8000, duration: 2000),
        ])
    }

    private func layer(_ p: V2Project, _ id: String) -> V2Layer { p.layers.first { $0.id == id }! }

    // MARK: Overlay

    func testOverlayCopiesTheSelectedClipIntoAnOverlayLayerHalfSizeOnTop() {
        var p = lane()
        p = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: p)
        p = AddKeyframeCommand(layerId: "B", atMs: 5000).apply(to: p)
        p = CopyToOverlayCommand(layerId: "B", newLayerId: "overlay-1").apply(to: p)
        let o = layer(p, "overlay-1"), b = layer(p, "B")
        XCTAssertEqual(o.timing.start, b.timing.start); XCTAssertEqual(o.timing.duration, b.timing.duration, "the same place and length")
        guard case .video(let copy) = o.payload, case .video(let original) = b.payload else { return XCTFail() }
        XCTAssertEqual(copy.assetId, original.assetId); XCTAssertEqual(copy.playbackRate, 2, "the same footage and speed")
        XCTAssertEqual(o.transform.scale.x, 0.5); XCTAssertEqual(o.transform.scale.y, 0.5); XCTAssertEqual(o.transform.translate.x, 0, "half size, in the middle")
        XCTAssertNil(o.tracks, "no keyframes carried over")
        XCTAssertGreaterThan(o.order, b.order, "its own lane above the main one")
        XCTAssertEqual(p.layers.last?.id, "overlay-1", "drawn on top")
        XCTAssertEqual(layer(p, "B").timing.start, b.timing.start); XCTAssertEqual(TransformKeyframes.times(of: b), [1000], "the original is untouched")
        XCTAssertFalse(isPushLane(o), "a free clip"); XCTAssertTrue(isPushLane(b))
        XCTAssertEqual(primaryVideoLaneOrder(of: p.layers), 0, "the main lane is still the main lane")
    }

    func testOverlaysShareALaneOnlyWhenTheyDoNotOverlapInTime() {
        var p = CopyToOverlayCommand(layerId: "A", newLayerId: "overlay-1").apply(to: lane())     // 0 ... 4000
        p = CopyToOverlayCommand(layerId: "A", newLayerId: "overlay-2").apply(to: p)              // same time: a new lane
        p = CopyToOverlayCommand(layerId: "B", newLayerId: "overlay-3").apply(to: p)              // 4000 ...: shares the first lane
        XCTAssertNotEqual(layer(p, "overlay-1").order, layer(p, "overlay-2").order)
        XCTAssertEqual(layer(p, "overlay-1").order, layer(p, "overlay-3").order)
    }

    func testOverlayWorksOnAPhotoAndNotOnText() {
        let withPhoto = ReplaceClipCommand(layerId: "C", asset: photo).apply(to: lane())
        let p = CopyToOverlayCommand(layerId: "C", newLayerId: "overlay-p").apply(to: withPhoto)
        guard case .image(let image) = layer(p, "overlay-p").payload else { return XCTFail("a photo overlay") }
        XCTAssertEqual(image.assetId, "photo-1")
        let text = AddTextLayerCommand(layerId: "T", text: "Hi", atMs: 0).apply(to: lane())
        XCTAssertEqual(CopyToOverlayCommand(layerId: "T", newLayerId: "overlay-t").apply(to: text).layers.count, text.layers.count)
        XCTAssertEqual(CopyToOverlayCommand(layerId: "missing", newLayerId: "overlay-x").apply(to: lane()).layers.count, 3)
    }

    // MARK: The main lane after Replace

    func testAMainLaneThatBecomesAllPhotosIsStillTheMainLane() {
        // The only video of the main lane replaced by a photo (the timeline row used to shrink: no video, so no main lane).
        let single = V2Project(composition: lane().composition, assets: [], layers: [video("A", start: 0, duration: 4000)])
        let p = ReplaceClipCommand(layerId: "A", asset: photo).apply(to: single)
        XCTAssertEqual(layer(p, "A").type, "image")
        XCTAssertEqual(primaryVideoLaneOrder(of: p.layers), 0, "a photo clip of the main track keeps its lane the main lane")
        XCTAssertEqual(layer(p, "A").timing.duration, 4000); XCTAssertEqual(layer(p, "A").timing.start, 0, "the main lane keeps its length")
        // A sticker or an overlay never makes a lane the main one.
        let asset = V2ImageAsset(id: "s", uri: "s.png", width: 100, height: 100)
        let stickersOnly = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: V2Project(composition: lane().composition, assets: [], layers: []))
        XCTAssertNil(primaryVideoLaneOrder(of: stickersOnly.layers))
        // Deleting a photo of the main lane closes the hole, like a video.
        let two = ReplaceClipCommand(layerId: "A", asset: photo).apply(to: lane())
        let deleted = DeleteClipCommand(layerId: "A").apply(to: two)
        XCTAssertEqual(layer(deleted, "B").timing.start, 0, "the main-lane magnet works for photos too")
    }

    // MARK: Replace

    func testReplacingAVideoKeepsItsPlaceLengthAndSpeed() {
        var p = lane()
        p = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: p)          // B now 2000 ms, C moved up
        p = SetAnimationCommand(layerId: "B", slot: .in, presetId: "fade", durationMs: 300).apply(to: p)
        let before = layer(p, "B")
        let replaced = ReplaceClipCommand(layerId: "B", asset: movie).apply(to: p)
        let b = layer(replaced, "B")
        XCTAssertEqual(b.timing.start, before.timing.start); XCTAssertEqual(b.timing.duration, before.timing.duration)
        XCTAssertEqual(b.frame.width, before.frame.width); XCTAssertEqual(b.parentLayerId, before.parentLayerId, "its animation wrapper stays")
        guard case .video(let payload) = b.payload else { return XCTFail() }
        XCTAssertEqual(payload.assetId, "movie-1"); XCTAssertEqual(payload.trimStart, 0, "the new footage starts from its beginning")
        XCTAssertEqual(payload.playbackRate, 2, "and keeps the speed")
        XCTAssertTrue(replaced.assets.contains { $0.id == "movie-1" })
        XCTAssertEqual(layer(replaced, "C").timing.start, layer(p, "C").timing.start, "nothing else moves")
    }

    func testReplacingAcrossKindsKeepsTheTimingAndDropsWhatOnlyOneKindHas() {
        let toPhoto = ReplaceClipCommand(layerId: "A", asset: photo).apply(to: lane())
        guard case .image(let image) = layer(toPhoto, "A").payload else { return XCTFail("a photo now") }
        XCTAssertEqual(image.assetId, "photo-1"); XCTAssertEqual(layer(toPhoto, "A").timing.duration, 4000)
        let backToVideo = ReplaceClipCommand(layerId: "A", asset: movie).apply(to: toPhoto)
        guard case .video(let payload) = layer(backToVideo, "A").payload else { return XCTFail("a video again") }
        XCTAssertEqual(payload.assetId, "movie-1"); XCTAssertNil(payload.playbackRate)
        let text = AddTextLayerCommand(layerId: "T", text: "Hi", atMs: 0).apply(to: lane())
        XCTAssertEqual(ReplaceClipCommand(layerId: "T", asset: photo).apply(to: text).layers.map(\.id), text.layers.map(\.id), "text cannot be replaced")
        XCTAssertEqual(ReplaceClipCommand(layerId: "missing", asset: photo).apply(to: lane()).assets.count, 0)
    }

    // MARK: Duplicate

    func testDuplicatingAMainLaneClipPushesTheLaneLater() {
        let p = DuplicateClipCommand(layerId: "B", newLayerId: "B2").apply(to: lane())
        XCTAssertEqual(layer(p, "A").timing.start, 0)
        XCTAssertEqual(layer(p, "B").timing.start, 4000)
        XCTAssertEqual(layer(p, "B2").timing.start, 8000, "the copy follows its original")
        XCTAssertEqual(layer(p, "B2").timing.duration, 4000)
        XCTAssertEqual(layer(p, "C").timing.start, 12000, "and the clips after move later by its length")
        XCTAssertEqual(layer(p, "B2").order, layer(p, "B").order)
        XCTAssertEqual(p.layers.map(\.id), ["A", "B", "B2", "C"], "next to the original in the stack")
    }

    func testTheCopyCarriesSpeedKeyframesAndAnimations() throws {
        var p = lane()
        p = SetClipSpeedCommand(layerId: "B", rate: 2).apply(to: p)
        p = AddKeyframeCommand(layerId: "B", atMs: 5000).apply(to: p)
        p = SetAnimationCommand(layerId: "B", slot: .out, presetId: "zoom-out", durationMs: 400).apply(to: p)
        p = DuplicateClipCommand(layerId: "B", newLayerId: "B2").apply(to: p)
        XCTAssertEqual(VideoTimeMapping(layer: layer(p, "B2"))?.rate, 2)
        XCTAssertEqual(TransformKeyframes.times(of: layer(p, "B2")), TransformKeyframes.times(of: layer(p, "B")))
        XCTAssertEqual(AnimationWrappers.applied(for: "B2", in: p.layers)[.out]?.presetId, "zoom-out")
        XCTAssertEqual(layer(p, "B2").parentLayerId, "B2~anim~out~zoom-out~400", "wrappers of its own, not the original's")
        XCTAssertEqual(AnimationWrappers.applied(for: "B", in: p.layers).count, 1)
        let wrapper = layer(p, "B2~anim~out~zoom-out~400")
        XCTAssertEqual(wrapper.timing.start, layer(p, "B2").timing.start)
    }

    func testDuplicatingTextKeepsItsLookAndLane() {
        var values = TextStyleValues(composition: lane().composition)
        values.text = "Hello"; values.curve = 40; values.backgroundColor = "#FFFFFFff"; values.backgroundPadX = 0.5
        var p = AddTextLayerCommand(layerId: "T", text: "Hello", atMs: 0, style: values).apply(to: lane())
        p = DuplicateClipCommand(layerId: "T", newLayerId: "T2").apply(to: p)
        let copy = layer(p, "T2")
        XCTAssertEqual(copy.timing.start, 3000, "after the original's 3 s")
        XCTAssertEqual(TextStyleValues(layer: copy, composition: p.composition).curve, 40, "the label and curve settings come along")
        XCTAssertEqual(TextStyleValues(layer: copy, composition: p.composition).backgroundPadX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(layer(p, "A").timing.start, 0, "text does not push the video lane")
        XCTAssertEqual(DuplicateClipCommand(layerId: "missing", newLayerId: "x").apply(to: p).layers.count, p.layers.count)
    }

    func testDuplicatingAnOverlayStaysAFreeClip() {
        var p = CopyToOverlayCommand(layerId: "A", newLayerId: "overlay-1").apply(to: lane())
        p = DuplicateClipCommand(layerId: "overlay-1", newLayerId: "overlay-1-copy").apply(to: p)
        let copy = layer(p, "overlay-1-copy")
        XCTAssertEqual(copy.timing.start, 4000, "after the overlay's 4 s")
        XCTAssertEqual(layer(p, "A").timing.start, 0)
        XCTAssertEqual(layer(p, "C").timing.start, 8000, "the video lane is not touched")
    }
}
