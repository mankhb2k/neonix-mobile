import XCTest
@testable import NeonixEditor

/// Remove BG (photo, Phase 1): the segmentation source in `V2Mask`, how the tool's draft becomes a mask, and the command's bookkeeping next to the Mask tool.
final class RemoveBackgroundTests: XCTestCase {
    private let frame = CGSize(width: 140, height: 210)

    private var project: V2Project {
        ProjectsView.openEditorProject(for: ProjectSample(name: "Trip to Paris", lastEdited: "", gradient: [], compositionWidth: 360, compositionHeight: 640))
    }
    private let layerId = "overlay-photo-1"

    // MARK: Protocol

    func testSegmentationRoundTripsAndOmitsWhatIsUnset() throws {
        let auto = V2MaskSegmentation(mode: "auto")
        let text = String(decoding: try JSONEncoder().encode(auto), as: UTF8.self)
        XCTAssertTrue(text.contains("\"type\":\"segmentation\""))
        XCTAssertFalse(text.contains("\"at\""))
        let point = V2MaskSegmentation(mode: "point", at: V2Vec2(x: 0.25, y: 0.75))
        let back = try JSONDecoder().decode(V2MaskSegmentation.self, from: JSONEncoder().encode(point))
        XCTAssertEqual(back.mode, "point")
        XCTAssertEqual(back.at?.x, 0.25)
        XCTAssertEqual(back.at?.y, 0.75)
    }

    // MARK: Draft

    func testNoneAndAnEmptyFrameHaveNoMask() {
        XCTAssertNil(RemoveBackgroundDraft().v2Mask(id: "m", frame: frame))
        var draft = RemoveBackgroundDraft(); draft.mode = .auto
        XCTAssertNil(draft.v2Mask(id: "m", frame: .zero))
    }

    func testDraftBecomesASegmentationMaskAndReadsBack() throws {
        var draft = RemoveBackgroundDraft()
        draft.mode = .point; draft.at = CGPoint(x: 0.3, y: 0.6); draft.feather = 0.5; draft.invert = true
        let applied = SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: project)
        let layer = try XCTUnwrap(applied.layers.first { $0.id == layerId })
        let mask = try XCTUnwrap(applied.masks?.first { $0.id == layer.mask })
        XCTAssertEqual(mask.id, "removebg-\(layerId)~point")
        XCTAssertEqual(mask.segmentation?.mode, "point")
        XCTAssertNil(mask.children)
        XCTAssertEqual(mask.feather ?? 0, 0.5 * MaskDraft.maxFeather * 140, accuracy: 0.001)   // of the shorter side
        XCTAssertEqual(RemoveBackgroundDraft(layer: layer, masks: applied.masks ?? []), draft)
    }

    func testAutoDropsThePointAndNoneRemovesTheMask() throws {
        var draft = RemoveBackgroundDraft(); draft.mode = .auto
        let applied = SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: project)
        XCTAssertNil(applied.masks?.first { $0.segmentation != nil }?.segmentation?.at)
        let cleared = SetLayerSegmentationCommand(layerId: layerId, draft: RemoveBackgroundDraft()).apply(to: applied)
        XCTAssertNil(cleared.layers.first { $0.id == layerId }?.mask)
        XCTAssertTrue((cleared.masks ?? []).isEmpty, "a mask no layer names is dropped")
    }

    // MARK: Next to the Mask tool

    func testRemoveBGAndAShapeMaskReplaceEachOther() throws {
        var draft = RemoveBackgroundDraft(); draft.mode = .auto
        let removed = SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: project)
        let shaped = SetLayerMaskCommand(layerId: layerId, draft: MaskDraft(shape: .circle)).apply(to: removed)
        XCTAssertEqual(shaped.masks?.count, 1)
        XCTAssertNil(shaped.masks?.first?.segmentation)
        XCTAssertEqual(RemoveBackgroundDraft(layer: try XCTUnwrap(shaped.layers.first { $0.id == layerId }), masks: shaped.masks ?? []).mode, .none)
        let back = SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: shaped)
        XCTAssertEqual(back.masks?.count, 1)
        XCTAssertNotNil(back.masks?.first?.segmentation)
    }

    func testChromaKeyAndRemoveBGOptionsReplaceEachOther() throws {
        var remove = RemoveBackgroundDraft(); remove.mode = .auto
        let withRemoveBG = SetLayerSegmentationCommand(layerId: layerId, draft: remove).apply(to: project)
        var chroma = ChromaKeyDraft(); chroma.enabled = true
        let withChroma = SetChromaKeyCommand(layerId: layerId, draft: chroma).apply(to: withRemoveBG)
        let keyedLayer = try XCTUnwrap(withChroma.layers.first { $0.id == layerId })
        XCTAssertNil(keyedLayer.mask, "chroma key replaces the Remove BG segmentation mask")
        XCTAssertTrue(withChroma.filters?.contains { filter in filter.primitives.contains { if case .feChromaKey = $0 { return true }; return false } } == true)

        let switchedBack = SetRemoveBackgroundOptionCommand(layerId: layerId, draft: remove).apply(to: withChroma)
        let removeLayer = try XCTUnwrap(switchedBack.layers.first { $0.id == layerId })
        XCTAssertEqual(RemoveBackgroundDraft(layer: removeLayer, masks: switchedBack.masks ?? []).mode, .auto)
        XCTAssertFalse((switchedBack.filters ?? []).contains { filter in filter.primitives.contains { if case .feChromaKey = $0 { return true }; return false } })
    }

    func testADuplicateKeepsItsOwnCopyOfTheMask() throws {
        var draft = RemoveBackgroundDraft(); draft.mode = .auto
        let removed = SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: project)
        let doubled = DuplicateOverlayCommand(layerId: layerId, newLayerId: "\(layerId)-copy").apply(to: removed)
        let copy = try XCTUnwrap(doubled.layers.first { $0.id == "\(layerId)-copy" })
        XCTAssertEqual(RemoveBackgroundDraft(layer: copy, masks: doubled.masks ?? []).mode, .auto)
        // Changing the original must not change the copy.
        draft.mode = .point
        let changed = SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: doubled)
        XCTAssertEqual(RemoveBackgroundDraft(layer: try XCTUnwrap(changed.layers.first { $0.id == "\(layerId)-copy" }), masks: changed.masks ?? []).mode, .auto)
    }

    func testAPhotoHasRemoveBGBuilt() {
        XCTAssertTrue(ClipTool.removeBackground.isBuilt(for: .image))
    }
}

/// The Vision + Core Image pipeline on the sample photo (a woman in front of a street): the subject stays, the background goes. Vision must run on this machine's simulator.
final class SegmentationServiceTests: XCTestCase {
    private func alpha(_ image: CGImage, x: Int, y: Int) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Int(pixel[3])
    }

    func testAutoCutoutKeepsTheSubjectAndClearsTheBackground() throws {
        let photo = try XCTUnwrap(BundledImageCache.image(filename: SampleMedia.photo.asset.uri)?.cgImage)
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision's foreground request finds nothing on the simulator (no Neural Engine); run this on the iPhone")
        #endif
        let matte = try XCTUnwrap(SegmentationService.matte(for: photo, mode: "auto", at: nil), "Vision found no subject")
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let cut = try XCTUnwrap(SegmentationService.cutout(of: photo, matte: matte, feather: 0, invert: false, context: context))
        XCTAssertEqual(cut.width, photo.width)
        XCTAssertEqual(alpha(cut, x: 3, y: 3), 0, "the corner is background")
        XCTAssertGreaterThan(alpha(cut, x: photo.width / 2, y: photo.height / 2), 200, "the middle is the subject")
        let flipped = try XCTUnwrap(SegmentationService.cutout(of: photo, matte: matte, feather: 0, invert: true, context: context))
        XCTAssertGreaterThan(alpha(flipped, x: 3, y: 3), 200, "Invert keeps the background")
        XCTAssertEqual(alpha(flipped, x: photo.width / 2, y: photo.height / 2), 0)
    }
}

/// Remove BG is the same mask on a video clip as on a photo (the matte per frame is derived data, never in the project).
final class RemoveBackgroundVideoTests: XCTestCase {
    func testAVideoClipTakesAndLosesTheSegmentationMask() throws {
        let base = compile(SampleProjectBuilder.makeDocument(
            media: .videoPortrait, inOption: .none, outOption: .none, effectOption: .none, easingOption: .linear,
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#101820"), frame: V2Frame(width: 360, height: 640)))
        let layer = try XCTUnwrap(base.layers.first { $0.type == "video" })
        var draft = RemoveBackgroundDraft(); draft.mode = .auto
        let applied = SetLayerSegmentationCommand(layerId: layer.id, draft: draft).apply(to: base)
        let cut = try XCTUnwrap(applied.layers.first { $0.id == layer.id })
        XCTAssertEqual(RemoveBackgroundDraft(layer: cut, masks: applied.masks ?? []).mode, .auto)
        let cleared = SetLayerSegmentationCommand(layerId: layer.id, draft: RemoveBackgroundDraft()).apply(to: applied)
        XCTAssertNil(cleared.layers.first { $0.id == layer.id }?.mask)
        XCTAssertTrue((cleared.masks ?? []).isEmpty)
    }

    func testVideoHasRemoveBGBuilt() {
        XCTAssertTrue(ClipTool.removeBackground.isBuilt(for: .video))
    }
}
