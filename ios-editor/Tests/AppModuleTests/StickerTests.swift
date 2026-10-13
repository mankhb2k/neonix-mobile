import XCTest
@testable import NeonixEditor

/// `AddStickerCommand`, the sticker lane rule, and the catalogue JSON.
final class StickerTests: XCTestCase {
    private let asset = V2ImageAsset(id: "sticker-grin", uri: "sticker-grin.png", mimeType: "image/png", width: 256, height: 256, integrity: nil)

    private func project(_ layers: [V2Layer] = []) -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: layers)
    }

    func testAddsACentredImageLayerSizedFromTheShorterSide() {
        let p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 1000).apply(to: project())
        XCTAssertEqual(p.layers.count, 1)
        let l = p.layers[0]
        XCTAssertEqual(l.frame.width, 360 * 0.35, accuracy: 0.01)
        XCTAssertEqual(l.frame.height, 360 * 0.35, accuracy: 0.01)
        XCTAssertEqual(l.timing.start, 1000)
        XCTAssertEqual(l.timing.duration, AddStickerCommand.defaultDurationMs)
        XCTAssertEqual(p.assets.count, 1)
    }

    func testTheAssetIsAddedOnlyOnce() {
        var p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: project())
        p = AddStickerCommand(layerId: "sticker-2", asset: asset, atMs: 5000).apply(to: p)
        XCTAssertEqual(p.assets.count, 1)
        XCTAssertEqual(p.layers.count, 2)
    }

    func testStickersThatDoNotOverlapShareALaneAndOverlappingOnesStack() {
        var p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: project())
        p = AddStickerCommand(layerId: "sticker-2", asset: asset, atMs: 4000).apply(to: p)
        p = AddStickerCommand(layerId: "sticker-3", asset: asset, atMs: 4500).apply(to: p)
        let order = Dictionary(uniqueKeysWithValues: p.layers.map { ($0.id, $0.order) })
        XCTAssertEqual(order["sticker-1"], order["sticker-2"])
        XCTAssertNotEqual(order["sticker-2"], order["sticker-3"])
    }

    func testCatalogueDecodes() throws {
        let json = """
        {"license":{"name":"MIT","holder":"Microsoft Corporation","source":"x","file":"f"},
         "categories":[{"id":"smileys","title":"Smileys"}],
         "stickers":[{"id":"grin","name":"Grin","category":"smileys","url":"https://x/grin.png","width":256,"height":256}]}
        """.data(using: .utf8)!
        let c = try JSONDecoder().decode(APIStickerCatalogue.self, from: json)
        XCTAssertEqual(c.stickers.first?.id, "grin")
        XCTAssertEqual(c.categories.first?.title, "Smileys")
    }

    func testAStickerIsItsOwnKindWithItsOwnTools() {
        let p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: project())
        XCTAssertEqual(ClipKind(layer: p.layers[0]), .sticker)
        XCTAssertEqual(ClipTool.tools(for: .sticker), [.split, .transform, .animation, .delete, .graph, .duplicate, .mirror])
    }

    func testMirrorFlipsAndTransformKeepsTheFlip() {
        var p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: project())
        p = MirrorLayerCommand(layerId: "sticker-1").apply(to: p)
        XCTAssertEqual(p.layers[0].transform.scale.x, -1)
        var v = TransformValues(layer: p.layers[0]); v.scale = 2
        p = SetTransformCommand(layerId: "sticker-1", values: v).apply(to: p)
        XCTAssertEqual(p.layers[0].transform.scale.x, -2)
        p = MirrorLayerCommand(layerId: "sticker-1").apply(to: p)
        XCTAssertEqual(p.layers[0].transform.scale.x, 2)
    }

    func testDuplicateStartsAtTheEndOnTheSameLane() {
        var p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 1000).apply(to: project())
        p = DuplicateOverlayCommand(layerId: "sticker-1", newLayerId: "sticker-1-copy").apply(to: p)
        XCTAssertEqual(p.layers.count, 2)
        XCTAssertEqual(p.layers[1].timing.start, 4000)
        XCTAssertEqual(p.layers[1].order, p.layers[0].order)
        XCTAssertEqual(ClipKind(layer: p.layers[1]), .sticker)
    }
}
