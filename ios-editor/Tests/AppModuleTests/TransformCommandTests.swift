import XCTest
@testable import NeonixEditor

final class TransformCommandTests: XCTestCase {
    private func project() -> V2Project {
        compile(EditorDocument(
            id: "t", composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000ff"),
            assets: [], layers: [
                EditorLayer(id: "a", kind: "shape", fill: "#FFFFFFff", frame: V2Frame(width: 200, height: 300), timing: V2Timing(start: 0, duration: 1000)),
                EditorLayer(id: "b", kind: "shape", fill: "#FF0000ff", frame: V2Frame(width: 100, height: 100), timing: V2Timing(start: 0, duration: 1000)),
            ]
        ))
    }

    func testSetsPositionScaleRotationAndOpacityOnJustThatLayer() throws {
        var values = TransformValues()
        values.x = -50; values.y = 120; values.scale = 1.5; values.rotation = -20; values.opacity = 0.6
        let result = SetTransformCommand(layerId: "a", values: values).apply(to: project())

        let a = try XCTUnwrap(result.layers.first { $0.id == "a" })
        XCTAssertEqual(a.transform.translate.x, -50)
        XCTAssertEqual(a.transform.translate.y, 120)
        XCTAssertEqual(a.transform.scale.x, 1.5)
        XCTAssertEqual(a.transform.scale.y, 1.5)
        XCTAssertEqual(a.transform.rotate.z, -20)
        XCTAssertEqual(a.opacity, 0.6)

        let b = try XCTUnwrap(result.layers.first { $0.id == "b" })
        XCTAssertEqual(b.transform.translate.x, 0, "other layers are untouched")
        XCTAssertEqual(b.opacity, 1)
    }

    func testKeepsTheRestOfTheTransform() throws {
        var base = project()
        var layers = base.layers
        layers[0].transform = V2Transform(
            translate: V2Vec3(x: 0, y: 0, z: 7), scale: V2Vec3(x: 1, y: 1, z: 2), rotate: V2Vec3(x: 15, y: 25, z: 0),
            skew: V2Vec2(x: 3, y: 4), anchor: V2Vec3(x: 5, y: 6, z: 0), perspective: 800
        )
        base = base.withLayers(layers)
        var values = TransformValues(layer: base.layers[0])
        values.rotation = 33
        let result = SetTransformCommand(layerId: "a", values: values).apply(to: base)
        let t = try XCTUnwrap(result.layers.first { $0.id == "a" }).transform
        XCTAssertEqual(t.rotate.z, 33)
        XCTAssertEqual(t.rotate.x, 15, "3D tilt is kept")
        XCTAssertEqual(t.rotate.y, 25)
        XCTAssertEqual(t.translate.z, 7)
        XCTAssertEqual(t.scale.z, 2)
        XCTAssertEqual(t.skew.x, 3)
        XCTAssertEqual(t.anchor.x, 5)
        XCTAssertEqual(t.perspective, 800)
    }

    func testUnknownLayerIsANoOp() {
        let before = project()
        var values = TransformValues()
        values.x = 999
        let after = SetTransformCommand(layerId: "nope", values: values).apply(to: before)
        XCTAssertEqual(after.layers.map(\.id), before.layers.map(\.id))
        XCTAssertEqual(after.layers.map(\.transform.translate.x), [0, 0])
    }

    func testValuesReadBackFromALayerAndUndoRestoresThem() throws {
        let original = project()
        var values = TransformValues()
        values.x = 40; values.rotation = 12
        var history = EditorHistory()
        history.record(current: original)
        let changed = SetTransformCommand(layerId: "a", values: values).apply(to: original)

        let read = TransformValues(layer: try XCTUnwrap(changed.layers.first { $0.id == "a" }))
        XCTAssertEqual(read, values)

        let undone = try XCTUnwrap(history.undo(current: changed))
        XCTAssertEqual(try XCTUnwrap(undone.layers.first { $0.id == "a" }).transform.translate.x, 0)
    }

    func testRulersSuitTheCompositionAndStartAtNeutral() {
        let small = V2Composition(width: 360, height: 640, fps: 30, background: "#000000ff")
        let large = V2Composition(width: 1080, height: 1920, fps: 30, background: "#000000ff")
        XCTAssertEqual(TransformControl.x.mapping(for: small).value(0), -360)
        XCTAssertEqual(TransformControl.y.mapping(for: large).value(0), -1920)
        for control in TransformControl.allCases {
            let mapping = control.mapping(for: small)
            XCTAssertEqual(mapping.value(mapping.index(control.neutral)), control.neutral, accuracy: 1e-9, "\(control) neutral is a tick")
        }
        XCTAssertEqual(TransformControl.rotation.display(-12), "-12°")
        XCTAssertEqual(TransformControl.scale.display(1.5), "150%")
        XCTAssertEqual(TransformControl.x.display(0), "0")
        XCTAssertEqual(TransformControl.y.display(40), "+40")
    }

    func testAdjustControlsMapOntoTheRealAdjustValues() {
        var values = AdjustValues()
        XCTAssertFalse(AdjustControl.allCases.contains { values.isChanged($0) }, "a fresh AdjustValues is neutral for every control")
        for control in AdjustControl.allCases {
            XCTAssertEqual(values[keyPath: control.keyPath], control.neutral, "\(control)")
        }
        values[keyPath: AdjustControl.saturation.keyPath] = 1.4
        XCTAssertEqual(values.saturation, 1.4)
        XCTAssertTrue(values.isChanged(.saturation))
        XCTAssertFalse(values.curvesChanged)
        values.curvePoints = [0, 0.2, 0.5, 0.8, 1]
        XCTAssertTrue(values.curvesChanged)
    }
}
