import XCTest
@testable import NeonixEditor

final class ChromaKeyCommandTests: XCTestCase {
    private func project() -> V2Project {
        let layer = V2Layer(id: "clip", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                            timing: V2Timing(start: 0, duration: 5000), payload: .video(V2VideoPayload(assetId: "movie")))
        return V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
                         assets: [], layers: [layer])
    }

    func testSetAndRemoveChromaKeyUpdatesTheReferencedFilter() throws {
        var draft = ChromaKeyDraft()
        draft.enabled = true
        let keyed = SetChromaKeyCommand(layerId: "clip", draft: draft).apply(to: project())
        let layer = try XCTUnwrap(keyed.layers.first)
        XCTAssertEqual(layer.filter, "chroma-clip")
        let filter = try XCTUnwrap(keyed.filters?.first)
        guard case .feChromaKey(_, let color, _, _, _, _) = try XCTUnwrap(filter.primitives.first) else {
            return XCTFail("expected the layer filter to contain feChromaKey")
        }
        XCTAssertEqual(color, "#0ABF47")

        draft.enabled = false
        let cleared = SetChromaKeyCommand(layerId: "clip", draft: draft).apply(to: keyed)
        XCTAssertNil(cleared.layers.first?.filter)
        XCTAssertNil(cleared.filters)
    }

    func testAdjustCommandKeepsTheChromaKeyPrimitiveInTheLayerFilter() throws {
        var draft = ChromaKeyDraft()
        draft.enabled = true
        let keyed = SetChromaKeyCommand(layerId: "clip", draft: draft).apply(to: project())
        let adjusted = SetAdjustCommand(layerId: "clip", values: AdjustValues(brightness: 0.2)).apply(to: keyed)
        let filterId = try XCTUnwrap(adjusted.layers.first?.filter)
        let filter = try XCTUnwrap(adjusted.filters?.first(where: { $0.id == filterId }))
        XCTAssertTrue(filter.primitives.contains { if case .feChromaKey = $0 { return true }; return false })

        let resetAdjust = SetAdjustCommand(layerId: "clip", values: AdjustValues()).apply(to: adjusted)
        let preserved = try XCTUnwrap(resetAdjust.filters?.first(where: { $0.id == resetAdjust.layers.first?.filter }))
        XCTAssertEqual(preserved.primitives.count, 1, "resetting Adjust leaves the chroma key active")
        XCTAssertTrue(preserved.primitives.contains { if case .feChromaKey = $0 { return true }; return false })
    }
}
