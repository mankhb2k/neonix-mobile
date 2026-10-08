import XCTest
@testable import NeonixEditor

/// Plain JSON round-trip checks for Protocol V2 types that have no runtime
/// sampling behavior of their own (unlike `KeyframeSamplerTests`, which
/// exercises actual per-frame resolution) — these just confirm the
/// hand-written `Codable` conformances decode/encode the real wire shape
/// correctly. Covers the LUT filter addition (`V2LutAsset`, `feColorLUT`)
/// — see `ui-design-note.md` for the design discussion this was built from.
final class ProtocolCodableTests: XCTestCase {
    func testLutAssetRoundTripsThroughJSON() throws {
        let json = """
        { "id": "lut-vintage-film", "kind": "lut", "uri": "vintage-film.cube", "dimension": 33 }
        """
        let asset = try JSONDecoder().decode(V2Asset.self, from: Data(json.utf8))
        guard case .lut(let lut) = asset else {
            return XCTFail("expected .lut case")
        }
        XCTAssertEqual(lut.id, "lut-vintage-film")
        XCTAssertEqual(lut.uri, "vintage-film.cube")
        XCTAssertEqual(lut.dimension, 33)
        XCTAssertEqual(asset.kind, "lut")

        let reencoded = try JSONEncoder().encode(asset)
        let redecoded = try JSONDecoder().decode(V2Asset.self, from: reencoded)
        guard case .lut(let lut2) = redecoded else {
            return XCTFail("expected .lut case after round-trip")
        }
        XCTAssertEqual(lut2.dimension, 33)
        XCTAssertEqual(lut2.uri, "vintage-film.cube")
    }

    func testFeColorLUTPrimitiveRoundTripsThroughJSON() throws {
        let json = """
        { "id": "f1", "type": "feColorLUT", "in": "SourceGraphic", "assetId": "lut-vintage-film", "result": "lutResult" }
        """
        let primitive = try JSONDecoder().decode(V2FilterPrimitive.self, from: Data(json.utf8))
        guard case .feColorLUT(let base, let assetId) = primitive else {
            return XCTFail("expected .feColorLUT case")
        }
        XCTAssertEqual(base.id, "f1")
        XCTAssertEqual(base.in, "SourceGraphic")
        XCTAssertEqual(base.result, "lutResult")
        XCTAssertEqual(assetId, "lut-vintage-film")

        let reencoded = try JSONEncoder().encode(primitive)
        let redecoded = try JSONDecoder().decode(V2FilterPrimitive.self, from: reencoded)
        guard case .feColorLUT(_, let assetId2) = redecoded else {
            return XCTFail("expected .feColorLUT case after round-trip")
        }
        XCTAssertEqual(assetId2, "lut-vintage-film")
    }

    /// The 2-primitive intensity-blend chain an Editor-tier "Bộ lọc" preset
    /// would compile to — `feColorLUT` always applies at full strength;
    /// partial intensity is this `feComposite` blending its `result` back
    /// against the original, not a field on `feColorLUT` itself.
    func testFilterWithColorLUTAndIntensityComposeChainDecodesInOrder() throws {
        let json = """
        {
          "id": "filter-vintage-film-70",
          "primitives": [
            { "id": "f1", "type": "feColorLUT", "in": "SourceGraphic", "assetId": "lut-vintage-film", "result": "lutResult" },
            { "id": "f2", "type": "feComposite", "operator": "arithmetic", "in": "lutResult", "in2": "SourceGraphic", "k1": 0, "k2": 0.7, "k3": 0.3, "k4": 0, "result": "final" }
          ]
        }
        """
        let filter = try JSONDecoder().decode(V2Filter.self, from: Data(json.utf8))
        XCTAssertEqual(filter.primitives.count, 2)

        guard case .feColorLUT(_, let assetId) = filter.primitives[0] else {
            return XCTFail("expected first primitive to be .feColorLUT")
        }
        XCTAssertEqual(assetId, "lut-vintage-film")

        guard case .feComposite(let base2, let in2, let op, _, let k2, let k3, _) = filter.primitives[1] else {
            return XCTFail("expected second primitive to be .feComposite")
        }
        XCTAssertEqual(base2.in, "lutResult")
        XCTAssertEqual(in2, "SourceGraphic")
        XCTAssertEqual(op, "arithmetic")
        XCTAssertEqual(k2, 0.7)
        XCTAssertEqual(k3, 0.3)
    }
}
