import XCTest
@testable import NeonixEditor

final class EditorTransformTests: XCTestCase {
    private let frame = V2Frame(width: 400, height: 600)

    private func layer(_ id: String, transform: EditorTransform? = nil, opacity: Double? = nil, inPreset: PresetBinding? = nil) -> EditorLayer {
        EditorLayer(id: id, kind: "shape", fill: "#FFFFFFff", frame: frame, timing: V2Timing(start: 0, duration: 1000),
                    inPreset: inPreset, transform: transform, opacity: opacity)
    }

    private func compiled(_ layers: [EditorLayer]) -> V2Project {
        compile(EditorDocument(id: "t", composition: V2Composition(width: 1080, height: 1920, fps: 30, background: "#000000ff"), assets: [], layers: layers))
    }

    // MARK: JSON

    func testEveryKeyIsOptionalAndScaleIsShorthand() throws {
        let decode = { (json: String) in try JSONDecoder().decode(EditorTransform.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode("{}"), EditorTransform())
        XCTAssertEqual(try decode(#"{"x":-120,"y":300,"rotation":-6}"#), EditorTransform(x: -120, y: 300, scale: 1, rotation: -6))
        XCTAssertEqual(try decode(#"{"scale":0.5}"#), EditorTransform(scale: 0.5))
        let stretched = try decode(#"{"scale":2,"scaleY":3}"#)
        XCTAssertEqual(stretched.scaleX, 2)
        XCTAssertEqual(stretched.scaleY, 3)
    }

    func testEncodingWritesOnlyWhatDiffersFromTheDefaults() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = { (t: EditorTransform) in String(decoding: try encoder.encode(t), as: UTF8.self) }
        XCTAssertEqual(try json(EditorTransform()), "{}")
        XCTAssertEqual(try json(EditorTransform(x: 10, rotation: 5)), #"{"rotation":5,"x":10}"#)
        XCTAssertEqual(try json(EditorTransform(scale: 0.5)), #"{"scale":0.5}"#)
        XCTAssertEqual(try json(EditorTransform(x: 0, y: 0, scaleX: 2, scaleY: 3, rotation: 0)), #"{"scaleX":2,"scaleY":3}"#)
    }

    func testLayerWithoutTransformKeepsItsOldJSON() throws {
        let plain = layer("a")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(plain), as: UTF8.self)
        XCTAssertFalse(text.contains("transform"))
        XCTAssertFalse(text.contains("opacity"))
        // A document written before transforms existed still decodes.
        let decoded = try JSONDecoder().decode(EditorLayer.self, from: Data(text.utf8))
        XCTAssertNil(decoded.transform)
        XCTAssertNil(decoded.opacity)
    }

    // MARK: Compile

    func testTransformLowersToTheV2Layer() throws {
        let project = compiled([layer("photo", transform: EditorTransform(x: -120, y: 300, scaleX: 0.8, scaleY: 0.9, rotation: -6), opacity: 0.7)])
        let v2 = try XCTUnwrap(project.layers.first { $0.id == "photo" })
        XCTAssertEqual(v2.transform.translate.x, -120)
        XCTAssertEqual(v2.transform.translate.y, 300)
        XCTAssertEqual(v2.transform.scale.x, 0.8)
        XCTAssertEqual(v2.transform.scale.y, 0.9)
        XCTAssertEqual(v2.transform.rotate.z, -6)
        XCTAssertEqual(v2.transform.anchor.x, 0, "pivot stays the layer's own centre")
        XCTAssertEqual(v2.opacity, 0.7)
    }

    func testNoTransformMeansIdentityAndFullOpacity() throws {
        let v2 = try XCTUnwrap(compiled([layer("a")]).layers.first)
        XCTAssertEqual(v2.transform.translate.x, 0)
        XCTAssertEqual(v2.transform.scale.x, 1)
        XCTAssertEqual(v2.transform.rotate.z, 0)
        XCTAssertEqual(v2.opacity, 1)
    }

    func testAPresetAnimatesAroundTheRestingPlace() throws {
        // The preset's keyframes live on the invisible wrapper; the layer keeps its own resting transform, so a
        // slide-in lands where the layer was placed instead of snapping back to the centre.
        let project = compiled([layer("photo", transform: EditorTransform(x: 200, y: -150, rotation: 8), opacity: 0.9,
                                       inPreset: PresetBinding(kind: .slide, durationMs: 500, easing: "easeOut"))])
        let wrapper = try XCTUnwrap(project.layers.first { $0.id == "photo-fx" })
        let child = try XCTUnwrap(project.layers.first { $0.id == "photo" })
        XCTAssertEqual(child.parentLayerId, "photo-fx")
        XCTAssertEqual(child.transform.translate.x, 200)
        XCTAssertEqual(child.transform.rotate.z, 8)
        XCTAssertEqual(child.opacity, 0.9)
        XCTAssertEqual(wrapper.transform.translate.x, 0, "the wrapper only carries keyframes")
        XCTAssertEqual(wrapper.transform.rotate.z, 0)
        XCTAssertEqual(wrapper.opacity, 1)
        XCTAssertNotNil(wrapper.tracks)
    }

    // MARK: Geometry helper

    func testCanvasPointFollowsRotationAndScale() {
        let quarterTurn = EditorTransform(x: 100, y: 50, scale: 1, rotation: 90)
        let up = quarterTurn.canvasPoint(dx: 0, dy: -100)   // 100 above the layer's centre, turned a quarter clockwise
        XCTAssertEqual(up.x, 200, accuracy: 0.001)
        XCTAssertEqual(up.y, 50, accuracy: 0.001)
        let scaled = EditorTransform(x: 0, y: 0, scale: 2, rotation: 0).canvasPoint(dx: 10, dy: 20)
        XCTAssertEqual(scaled.x, 20, accuracy: 0.001)
        XCTAssertEqual(scaled.y, 40, accuracy: 0.001)
    }

    // MARK: Templates keep the creator's placement when media is swapped

    func testFillingASlotKeepsThePositionRotationAndOpacity() throws {
        var slotLayer = layer("slot-1", transform: EditorTransform(x: -60, y: 520, scale: 0.9, rotation: -3), opacity: 0.95)
        slotLayer.kind = "image"
        slotLayer.assetId = "placeholder"
        slotLayer.fill = nil
        let document = EditorDocument(
            id: "t", composition: V2Composition(width: 1080, height: 1920, fps: 30, background: "#000000ff"),
            assets: [.image(V2ImageAsset(id: "placeholder", uri: "placeholder.jpg", width: 10, height: 10))], layers: [slotLayer]
        )
        let manifest = TemplateManifest(
            formatVersion: 2, minAppVersion: "1.0", name: "T", composition: .init(width: 1080, height: 1920, durationMs: 1000),
            fonts: [], builtinAssets: [], music: nil,
            slots: [TemplateManifest.Slot(id: "s1", kind: "media", layerId: "slot-1", label: "Photo", durationMs: 1000, required: true)]
        )
        let package = TemplatePackage(manifest: manifest, document: document, directory: FileManager.default.temporaryDirectory)

        let user: V2Asset = .video(V2VideoAsset(id: "mine", uri: "mine.mov", width: 1080, height: 1920, duration: 5000))
        let filled = try TemplateFiller.fill(package, with: [SlotFill(slotId: "s1", kind: .video, asset: user, trimStartMs: 1000)])
        let result = try XCTUnwrap(filled.document.layers.first)
        XCTAssertEqual(result.kind, "video", "a video slot becomes a video layer...")
        XCTAssertEqual(result.transform, EditorTransform(x: -60, y: 520, scale: 0.9, rotation: -3), "...in the same place")
        XCTAssertEqual(result.opacity, 0.95)

        let v2 = try XCTUnwrap(TemplateProjectBuilder.project(document: filled.document, trims: filled.trims).layers.first { $0.id == "slot-1" })
        XCTAssertEqual(v2.transform.rotate.z, -3)
        guard case .video(let payload) = v2.payload else { return XCTFail("expected video") }
        XCTAssertEqual(payload.trimStart, 1000)
    }

}
