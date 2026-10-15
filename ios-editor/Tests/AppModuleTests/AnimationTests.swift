import XCTest
@testable import NeonixEditor

/// The Animation tool's model: presets -> atomic V2 tracks, nested wrappers per slot, and what every edit does to them.
final class AnimationTests: XCTestCase {
    private func project() -> V2Project {
        let base = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        return AddTextLayerCommand(layerId: "clip", text: "Hello", atMs: 1000).apply(to: base)   // 1000 ... 4000 ms
    }

    private func set(_ p: V2Project, _ slot: AnimationSlot, _ preset: String?, _ ms: Double = 500) -> V2Project {
        SetAnimationCommand(layerId: "clip", slot: slot, presetId: preset, durationMs: ms).apply(to: p)
    }

    private func wrappers(_ p: V2Project) -> [V2Layer] { p.layers.filter { $0.type == "group" } }
    private func clip(_ p: V2Project, _ id: String = "clip") -> V2Layer { p.layers.first { $0.id == id }! }
    private func opacity(_ layer: V2Layer, at ms: Double) -> Double { sampleLayer(layer, atMs: ms).opacity }

    func testEveryPresetBuildsOrderedTracks() {
        XCTAssertEqual(Set(AnimationCatalog.all.map(\.id)).count, AnimationCatalog.all.count)
        for preset in AnimationCatalog.all {
            for slot in preset.slots {
                let tracks = AnimationCatalog.tracks(for: preset, slot: slot, durationMs: 600, canvas: (360, 640), idPrefix: "x")
                XCTAssertFalse(tracks.isEmpty, preset.id)
                for track in tracks {
                    var last = -Double.infinity
                    for key in track.keyframes {
                        let t: Double
                        switch key.time {
                        case .absolute(let ms): t = ms
                        case .anchored(_, let offset): t = 10_000 - offset   // as if the clip were 10 s long
                        default: t = last + 1
                        }
                        XCTAssertGreaterThan(t, last, "\(preset.id) \(slot) \(track.path): keyframe times must increase")
                        last = t
                    }
                    XCTAssertEqual(track.animation != nil, slot == .combo, "only a combo loops")
                }
            }
        }
        XCTAssertTrue(AnimationCatalog.presets(for: .combo).allSatisfy { $0.cycleMs > 0 })
    }

    func testAnInFadeWrapsTheClipAndFadesItIn() throws {
        let p = set(project(), .in, "fade", 500)
        let w = try XCTUnwrap(wrappers(p).first)
        XCTAssertEqual(wrappers(p).count, 1)
        XCTAssertEqual(w.id, "clip~anim~in~fade~500")
        XCTAssertEqual(clip(p).parentLayerId, w.id)
        XCTAssertEqual(w.timing.start, 1000); XCTAssertEqual(w.timing.duration, 3000)
        XCTAssertEqual(p.layers.firstIndex { $0.id == w.id }!, p.layers.firstIndex { $0.id == "clip" }! - 1, "the wrapper takes the clip's place in the z-order")
        XCTAssertEqual(opacity(w, at: 1000), 0, accuracy: 1e-6)
        XCTAssertEqual(opacity(w, at: 1500), 1, accuracy: 1e-6)
        XCTAssertEqual(opacity(w, at: 3000), 1, accuracy: 1e-6)
    }

    func testAnOutFadeIsTheSameMotionBackwardsEndingAtTheClipsEnd() throws {
        let p = set(project(), .out, "slide-left", 500)
        let w = try XCTUnwrap(wrappers(p).first)
        let x: (Double) -> Double = { sampleLayer(w, atMs: $0).translateX }
        XCTAssertEqual(x(1000), 0, accuracy: 1e-6, "at rest until the exit starts")
        XCTAssertEqual(x(3400), 0, accuracy: 1e-6)
        XCTAssertEqual(x(4000), -0.4 * 360, accuracy: 1e-6, "slide-left out ends off to the left at the end")
        XCTAssertLessThan(x(3800), 0)
        XCTAssertGreaterThan(x(3800), x(4000))
    }

    func testAComboLoopsForTheWholeClip() throws {
        let p = set(project(), .combo, "pulse")
        let w = try XCTUnwrap(wrappers(p).first)
        let scale: (Double) -> Double = { sampleLayer(w, atMs: $0).scaleX }
        XCTAssertEqual(scale(1000), 1, accuracy: 1e-6)
        XCTAssertEqual(scale(1400), 1.08, accuracy: 0.01, "the middle of the first cycle")
        XCTAssertEqual(scale(1800), 1, accuracy: 0.01)
        XCTAssertEqual(scale(2200), 1.08, accuracy: 0.01, "and again, a cycle later")
    }

    func testTheSlotsNestInOrderAndAreReadBack() {
        var p = set(project(), .combo, "sway")
        p = set(p, .out, "fade", 400)
        p = set(p, .in, "zoom-in", 600)
        let ws = wrappers(p)
        XCTAssertEqual(ws.count, 3)
        func parent(_ id: String) -> String? { p.layers.first { $0.id == id }!.parentLayerId }
        XCTAssertEqual(clip(p).parentLayerId, "clip~anim~in~zoom-in~600")
        XCTAssertEqual(parent("clip~anim~in~zoom-in~600"), "clip~anim~out~fade~400")
        XCTAssertEqual(parent("clip~anim~out~fade~400"), "clip~anim~combo~sway~0")
        XCTAssertNil(parent("clip~anim~combo~sway~0"))
        let applied = AnimationWrappers.applied(for: "clip", in: p.layers)
        XCTAssertEqual(applied[.in]?.presetId, "zoom-in"); XCTAssertEqual(applied[.in]?.durationMs, 600)
        XCTAssertEqual(applied[.out]?.presetId, "fade"); XCTAssertEqual(applied[.combo]?.presetId, "sway")
    }

    func testReplacingAndRemovingASlot() {
        var p = set(project(), .in, "fade", 500)
        p = set(p, .in, "pop", 300)
        XCTAssertEqual(wrappers(p).map(\.id), ["clip~anim~in~pop~300"], "replaced, not stacked")
        p = set(p, .out, "fade", 500)
        p = set(p, .in, nil)
        XCTAssertEqual(wrappers(p).map(\.id), ["clip~anim~out~fade~500"])
        XCTAssertEqual(clip(p).parentLayerId, "clip~anim~out~fade~500")
        p = set(p, .out, nil)
        XCTAssertTrue(wrappers(p).isEmpty)
        XCTAssertNil(clip(p).parentLayerId, "back to a plain clip")
    }

    func testFailsClosed() {
        let p = project()
        XCTAssertEqual(set(p, .combo, "fade").layers.count, p.layers.count, "a fade is not a combo")
        XCTAssertEqual(set(p, .in, "nope").layers.count, p.layers.count)
        XCTAssertEqual(SetAnimationCommand(layerId: "missing", slot: .in, presetId: "fade").apply(to: p).layers.count, p.layers.count)
        let clamped = set(p, .in, "fade", 99_999)
        XCTAssertLessThanOrEqual(AnimationWrappers.applied(for: "clip", in: clamped.layers)[.in]!.durationMs, 2900, "never longer than the clip")
    }

    func testWrappersFollowTheirClipAndGoWhenItDoes() {
        var p = set(project(), .in, "fade", 500)
        // Trim: the clip now starts later and is shorter; the wrapper mirrors it once normalised.
        p = TrimClipCommand(layerId: "clip", start: 1500, duration: 2000, trimStart: nil, trimEnd: nil).apply(to: p)
        p = AnimationWrappers.normalized(p)
        XCTAssertEqual(wrappers(p)[0].timing.start, 1500); XCTAssertEqual(wrappers(p)[0].timing.duration, 2000)
        XCTAssertEqual(opacity(wrappers(p)[0], at: 1500), 0, accuracy: 1e-6, "the entrance starts at the new start")
        let same = AnimationWrappers.normalized(p)
        XCTAssertEqual(same.layers.count, p.layers.count)
        p = DeleteClipCommand(layerId: "clip").apply(to: p)
        XCTAssertEqual(AnimationWrappers.normalized(p).layers.count, 0, "no orphan wrapper is left behind")
    }

    func testSplitMovesTheExitToTheSecondHalfAndLoopsOnBoth() throws {
        var p = set(project(), .in, "fade", 400)
        p = set(p, .out, "zoom-out", 400)
        p = set(p, .combo, "float")
        p = SplitClipCommand(layerId: "clip", atMs: 2500).apply(to: p)
        p = AnimationWrappers.normalized(p)
        let secondId = try XCTUnwrap(p.layers.first { $0.id.hasPrefix("clip-split-") && $0.type != "group" }?.id)
        let first = AnimationWrappers.applied(for: "clip", in: p.layers)
        let second = AnimationWrappers.applied(for: secondId, in: p.layers)
        XCTAssertEqual(Set(first.keys), [.in, .combo], "the entrance stays at the start")
        XCTAssertEqual(Set(second.keys), [.out, .combo], "the exit moves to the end")
        XCTAssertEqual(clip(p, secondId).parentLayerId?.hasPrefix("\(secondId)~anim~"), true, "the second half is not nested in the first half's wrappers")
        XCTAssertEqual(clip(p).timing.duration, 1500)
        for w in wrappers(p) {
            let owner = AnimationWrappers.parse(w.id)!.clipId
            XCTAssertEqual(w.timing.start, clip(p, owner).timing.start); XCTAssertEqual(w.timing.duration, clip(p, owner).timing.duration)
        }
        // A split without any animation is unchanged.
        let plain = SplitClipCommand(layerId: "clip", atMs: 2500).apply(to: project())
        XCTAssertTrue(plain.layers.allSatisfy { $0.type != "group" })
    }

    func testParseRejectsOtherIds() {
        XCTAssertNil(AnimationWrappers.parse("text-1234"))
        XCTAssertNil(AnimationWrappers.parse("clip-fx"))
        XCTAssertNil(AnimationWrappers.parse("clip~anim~sideways~fade~500"))
        XCTAssertEqual(AnimationWrappers.parse("a-b~anim~out~slide-left~250")?.clipId, "a-b")
    }

    func testADuplicatedStickerKeepsItsAnimationsInWrappersOfItsOwn() throws {
        let base = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        let asset = V2ImageAsset(id: "sticker-a", uri: "x.png", width: 100, height: 100)
        var p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: base)
        p = SetAnimationCommand(layerId: "sticker-1", slot: .in, presetId: "pop", durationMs: 400).apply(to: p)
        p = DuplicateOverlayCommand(layerId: "sticker-1", newLayerId: "sticker-2").apply(to: p)
        XCTAssertEqual(AnimationWrappers.applied(for: "sticker-2", in: p.layers)[.in]?.presetId, "pop")
        let copy = p.layers.first { $0.id == "sticker-2" }!
        XCTAssertEqual(copy.parentLayerId, "sticker-2~anim~in~pop~400")
        let wrapper = p.layers.first { $0.id == "sticker-2~anim~in~pop~400" }!
        XCTAssertNil(wrapper.parentLayerId)
        XCTAssertEqual(wrapper.timing.start, copy.timing.start, "the copy's wrapper follows the copy, which starts where the original ends")
        XCTAssertEqual(AnimationWrappers.applied(for: "sticker-1", in: p.layers).count, 1)
    }
}
