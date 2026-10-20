import XCTest
@testable import NeonixEditor

/// `V2Mask.feather` / `invert` (Swift-only additions) and how the Mask tool's draft becomes a V2 mask.
final class MaskTests: XCTestCase {
    private let frame = CGSize(width: 360, height: 640)

    // MARK: Protocol

    func testFeatherAndInvertAreOptionalAndAbsentMeansNone() throws {
        let json = #"{"id":"m","maskType":"alpha","children":[{"type":"circle","cx":1,"cy":1,"r":1}]}"#
        let mask = try JSONDecoder().decode(V2Mask.self, from: Data(json.utf8))
        XCTAssertNil(mask.feather)
        XCTAssertNil(mask.invert)
    }

    func testFeatherAndInvertSurviveJSONAndAreOmittedWhenUnset() throws {
        var mask = try XCTUnwrap(MaskDraft(shape: .circle).v2Mask(id: "m", frame: frame))
        let plain = String(decoding: try JSONEncoder().encode(mask), as: UTF8.self)
        XCTAssertFalse(plain.contains("feather"))
        XCTAssertFalse(plain.contains("invert"))
        mask.feather = 12.5
        mask.invert = true
        let back = try JSONDecoder().decode(V2Mask.self, from: JSONEncoder().encode(mask))
        XCTAssertEqual(back.feather, 12.5)
        XCTAssertEqual(back.invert, true)
    }

    // MARK: Draft -> V2 mask

    func testNoneHasNoMaskAndAnEmptyFrameHasNoMask() {
        XCTAssertNil(MaskDraft().v2Mask(id: "m", frame: frame))
        XCTAssertNil(MaskDraft(shape: .circle).v2Mask(id: "m", frame: .zero))
    }

    func testACircleIsAnEllipseInTheLayersPixelsSizedFromTheShorterSide() throws {
        var draft = MaskDraft(shape: .circle)
        draft.centerX = 0.5; draft.centerY = 0.25; draft.width = 0.5; draft.height = 0.25
        let mask = try XCTUnwrap(draft.v2Mask(id: "m", frame: frame))
        XCTAssertEqual(mask.maskType, "alpha")
        guard case .ellipse(let cx, let cy, let rx, let ry, _)? = mask.children?.first else { return XCTFail("not an ellipse") }
        XCTAssertEqual(cx, 180, accuracy: 0.001)
        XCTAssertEqual(cy, 160, accuracy: 0.001)
        XCTAssertEqual(rx, 0.5 * 360 / 2, accuracy: 0.001)
        XCTAssertEqual(ry, 0.25 * 360 / 2, accuracy: 0.001)
    }

    func testARectangleHasRoundedCornersFromRoundness() throws {
        var draft = MaskDraft(shape: .rectangle)
        draft.width = 0.5; draft.height = 0.7; draft.roundness = 0.5
        guard case .rect(let x, let y, let w, let h, let rx, _, _)? = try XCTUnwrap(draft.v2Mask(id: "m", frame: frame)).children?.first else { return XCTFail() }
        XCTAssertEqual(w, 180, accuracy: 0.001)
        XCTAssertEqual(h, 252, accuracy: 0.001)
        XCTAssertEqual(x, 180 - 90, accuracy: 0.001)
        XCTAssertEqual(y, 320 - 126, accuracy: 0.001)
        XCTAssertEqual(rx ?? 0, 0.5 * 180 / 2, accuracy: 0.001)
    }

    func testHorizontalIsTheHalfPlaneAboveTheLineAndMirrorABandAroundIt() throws {
        var draft = MaskDraft(shape: .horizontal)
        draft.centerY = 0.5
        guard case .rect(_, let top, _, let height, _, _, _)? = try XCTUnwrap(draft.v2Mask(id: "m", frame: frame)).children?.first else { return XCTFail() }
        XCTAssertEqual(top + height, 320, accuracy: 0.001, "the half-plane ends on the line")
        var mirror = MaskDraft(shape: .mirror)
        mirror.height = 0.5
        guard case .rect(_, let y, _, let band, _, _, _)? = try XCTUnwrap(mirror.v2Mask(id: "m", frame: frame)).children?.first else { return XCTFail() }
        XCTAssertEqual(band, 0.5 * 360, accuracy: 0.001)
        XCTAssertEqual(y + band / 2, 320, accuracy: 0.001, "centred on the line")
    }

    func testRotationTurnsTheShapeAboutItsCentreAndNoRotationHasNoTransform() throws {
        var draft = MaskDraft(shape: .circle)
        XCTAssertNil(draft.v2Mask(id: "m", frame: frame)?.children.flatMap { nodeTransform($0[0]) })
        draft.rotation = 30
        let transform = try XCTUnwrap(nodeTransform(try XCTUnwrap(draft.v2Mask(id: "m", frame: frame)).children![0]))
        guard case .rotate(let angle, let center)? = transform.first else { return XCTFail() }
        XCTAssertEqual(angle, 30)
        XCTAssertEqual(center?.x ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(center?.y ?? 0, 320, accuracy: 0.001)
    }

    func testFeatherIsInPixelsOfTheShorterSideAndInvertCarriesOver() throws {
        var draft = MaskDraft(shape: .circle)
        draft.feather = 0.5
        draft.invert = true
        let mask = try XCTUnwrap(draft.v2Mask(id: "m", frame: frame))
        XCTAssertEqual(mask.feather ?? 0, 0.5 * MaskDraft.maxFeather * 360, accuracy: 0.001)
        XCTAssertEqual(mask.invert, true)
        XCTAssertEqual(MaskDraft(shape: .rectangle, keeping: draft).invert, true, "picking another shape keeps the invert switch")
        XCTAssertEqual(MaskDraft(shape: .rectangle, keeping: draft).feather, 0, "and nothing else")
    }

    private func nodeTransform(_ node: V2SvgDefinitionNode) -> [V2SvgTransformOperation]? {
        switch node {
        case .ellipse(_, _, _, _, let common), .rect(_, _, _, _, _, _, let common), .circle(_, _, _, let common): return common.transform
        default: return nil
        }
    }

    // MARK: The tool's command

    private func project() -> V2Project {
        let asset = V2Asset.video(V2VideoAsset(id: "v", uri: "v.mov", width: 1080, height: 1920, duration: 5000))
        let a = V2Layer(id: "a", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity, timing: V2Timing(start: 0, duration: 2000), payload: .video(V2VideoPayload(assetId: "v", trimStart: 0)))
        let b = V2Layer(id: "b", order: 1, frame: V2Frame(width: 360, height: 640), transform: .identity, timing: V2Timing(start: 2000, duration: 2000), payload: .video(V2VideoPayload(assetId: "v", trimStart: 0)))
        return V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [asset], layers: [a, b])
    }

    func testTheCommandNamesTheMaskInTheLayerAndKeepsTheShapeInItsId() throws {
        let p = SetLayerMaskCommand(layerId: "a", draft: MaskDraft(shape: .circle)).apply(to: project())
        XCTAssertEqual(p.layers[0].mask, "mask-a~circle")
        XCTAssertEqual(p.masks?.map(\.id), ["mask-a~circle"])
        XCTAssertNil(p.layers[1].mask)
        XCTAssertEqual(SetLayerMaskCommand.shape(ofMaskId: "mask-a~circle"), .circle)
        XCTAssertNil(SetLayerMaskCommand.shape(ofMaskId: "other"))
    }

    func testAnotherShapeReplacesTheOldMaskAndNoneRemovesIt() {
        var p = SetLayerMaskCommand(layerId: "a", draft: MaskDraft(shape: .circle)).apply(to: project())
        p = SetLayerMaskCommand(layerId: "a", draft: MaskDraft(shape: .rectangle)).apply(to: p)
        XCTAssertEqual(p.masks?.map(\.id), ["mask-a~rectangle"], "the old shape's mask is gone")
        p = SetLayerMaskCommand(layerId: "a", draft: MaskDraft()).apply(to: p)
        XCTAssertNil(p.layers[0].mask)
        XCTAssertNil(p.masks, "no masks left, none stored")
    }

    func testEditingTheSameShapeAgainReplacesItsEntryInPlace() {
        var draft = MaskDraft(shape: .circle)
        var p = SetLayerMaskCommand(layerId: "a", draft: draft).apply(to: project())
        draft.feather = 0.4
        p = SetLayerMaskCommand(layerId: "a", draft: draft).apply(to: p)
        XCTAssertEqual(p.masks?.count, 1)
        XCTAssertGreaterThan(p.masks?.first?.feather ?? 0, 0)
    }

    func testTheDraftComesBackOutOfTheStoredMask() throws {
        var draft = MaskDraft(shape: .rectangle)
        draft.centerX = 0.3; draft.centerY = 0.6; draft.width = 0.4; draft.height = 0.55; draft.rotation = 20; draft.roundness = 0.5; draft.feather = 0.3; draft.invert = true
        let p = SetLayerMaskCommand(layerId: "a", draft: draft).apply(to: project())
        let back = MaskDraft(layer: p.layers[0], masks: p.masks ?? [])
        XCTAssertEqual(back.shape, .rectangle)
        for (x, y) in [(back.centerX, 0.3), (back.centerY, 0.6), (back.width, 0.4), (back.height, 0.55), (back.rotation, 20), (back.roundness, 0.5), (back.feather, 0.3)] {
            XCTAssertEqual(x, y, accuracy: 0.0005)
        }
        XCTAssertTrue(back.invert)
        for shape in [MaskShape.horizontal, .mirror, .circle] {
            var d = MaskDraft(shape: shape)
            d.centerX = 0.4; d.centerY = 0.7; d.rotation = -35
            let q = SetLayerMaskCommand(layerId: "a", draft: d).apply(to: project())
            let r = MaskDraft(layer: q.layers[0], masks: q.masks ?? [])
            XCTAssertEqual(r.shape, shape)
            XCTAssertEqual(r.centerX, 0.4, accuracy: 0.0005, "\(shape)")
            XCTAssertEqual(r.centerY, 0.7, accuracy: 0.0005, "\(shape)")
            XCTAssertEqual(r.rotation, -35, accuracy: 0.0005, "\(shape)")
        }
    }

    func testALayerWithNoMaskOfThisToolsMakingReadsBackAsNone() {
        XCTAssertEqual(MaskDraft(layer: project().layers[0], masks: []), MaskDraft())
    }

    func testASplitHalfSharingTheMaskGetsACopyBeforeTheOriginalIsEdited() {
        var p = SetLayerMaskCommand(layerId: "a", draft: MaskDraft(shape: .circle)).apply(to: project())
        // The second half names the first one's mask (what a split / copy leaves behind).
        var layers = p.layers
        layers[1].mask = "mask-a~circle"
        p = p.withLayers(layers)
        var edited = MaskDraft(shape: .circle)
        edited.feather = 0.5
        p = SetLayerMaskCommand(layerId: "a", draft: edited).apply(to: p)
        XCTAssertEqual(p.layers[1].mask, "mask-b~circle", "b keeps its own copy")
        let aMask = p.masks?.first { $0.id == "mask-a~circle" }, bMask = p.masks?.first { $0.id == "mask-b~circle" }
        XCTAssertGreaterThan(aMask?.feather ?? 0, 0)
        XCTAssertNil(bMask?.feather, "editing a left b's mask as it was")
    }

    func testAMaskOfADeletedClipIsDropped() {
        var p = SetLayerMaskCommand(layerId: "a", draft: MaskDraft(shape: .circle)).apply(to: project())
        p = p.withLayers(p.layers.filter { $0.id != "a" })
        // Any later mask edit prunes what no layer names.
        p = SetLayerMaskCommand(layerId: "b", draft: MaskDraft(shape: .mirror)).apply(to: p)
        XCTAssertEqual(p.masks?.map(\.id), ["mask-b~mirror"])
    }

    func testOnlyPictureAndVideoLayersTakeAMask() {
        let text = AddTextLayerCommand(layerId: "t", text: "Hi", atMs: 0).apply(to: project())
        let after = SetLayerMaskCommand(layerId: "t", draft: MaskDraft(shape: .circle)).apply(to: text)
        XCTAssertNil(after.masks)
        XCTAssertNil(SetLayerMaskCommand(layerId: "nope", draft: MaskDraft(shape: .circle)).apply(to: project()).masks)
    }
}
