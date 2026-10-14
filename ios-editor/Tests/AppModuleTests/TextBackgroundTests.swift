import XCTest
@testable import NeonixEditor

/// The story-style text background (`TextBackgroundGeometry`), multi-line text, and alignment read-back.
final class TextBackgroundTests: XCTestCase {
    private func arcs(_ contour: V2PathContour) -> [(sweep: Bool, radius: Double)] {
        contour.segments.compactMap { if case .arc(let radii, _, _, let sweep, _) = $0 { return (sweep, radii.x) } else { return nil } }
    }

    private func bounds(_ contour: V2PathContour) -> CGRect {
        MotionPathResolver.buildCGPath(contours: [contour]).boundingBoxOfPath
    }

    func testOneLineIsARoundedRectangle() throws {
        let contour = try XCTUnwrap(TextBackgroundGeometry.contour(lines: [(10, 110)], boundaries: [0, 40], radius: 8))
        XCTAssertTrue(contour.closed)
        XCTAssertEqual(arcs(contour).count, 4)
        XCTAssertTrue(arcs(contour).allSatisfy { $0.sweep && $0.radius == 8 }, "four convex corners")
        XCTAssertEqual(bounds(contour).width, 100, accuracy: 0.5)
        XCTAssertEqual(bounds(contour).height, 40, accuracy: 0.5)
    }

    func testTwoLinesOfDifferentWidthMakeAStepWithConcaveFillets() throws {
        // Line 1 is narrower and centred over line 2 (the Facebook story look).
        let contour = try XCTUnwrap(TextBackgroundGeometry.contour(lines: [(40, 160), (10, 190)], boundaries: [0, 40, 80], radius: 8))
        let a = arcs(contour)
        XCTAssertEqual(a.count, 8)
        XCTAssertEqual(a.filter { $0.sweep }.count, 6, "six convex corners")
        XCTAssertEqual(a.filter { !$0.sweep }.count, 2, "two concave fillets where the lines meet")
        XCTAssertEqual(bounds(contour).width, 180, accuracy: 0.5)
        XCTAssertEqual(bounds(contour).height, 80, accuracy: 0.5)
    }

    func testEqualWidthLinesMergeIntoOneRectangle() throws {
        let contour = try XCTUnwrap(TextBackgroundGeometry.contour(lines: [(10, 110), (10, 110)], boundaries: [0, 40, 80], radius: 8))
        XCTAssertEqual(arcs(contour).count, 4)
    }

    func testAStepSmallerThanTheRadiusShrinksTheFillet() throws {
        let contour = try XCTUnwrap(TextBackgroundGeometry.contour(lines: [(10, 110), (6, 114)], boundaries: [0, 40, 80], radius: 12))
        XCTAssertTrue(arcs(contour).allSatisfy { $0.radius <= 4.01 || $0.radius == 12 }, "no arc is wider than half the 4 pt step")
        XCTAssertTrue(arcs(contour).contains { $0.radius <= 4.01 })
    }

    private func project() -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
    }

    func testATextLayerWithABackgroundCarriesTheLabelAndShiftsTheText() {
        var style = TextStyleValues(composition: project().composition)
        style.backgroundColor = "#FFFFFFff"; style.text = "Hi\nthere you"
        let layer = AddTextLayerCommand(layerId: "t", text: style.text, atMs: 0, style: style).apply(to: project()).layers[0]
        let payload = layer.textPayload!
        XCTAssertEqual(payload.chunks.count, 2, "a new line makes a new line of text")
        let background = payload.layout?.background
        XCTAssertNotNil(background)
        XCTAssertEqual(background?.fill.flatColor, "#FFFFFFff")
        let box = MotionPathResolver.buildCGPath(contours: background!.contours).boundingBoxOfPath
        XCTAssertEqual(box.minY, 0, accuracy: 0.5)
        XCTAssertEqual(box.height, layer.frame.height, accuracy: 1, "the label fills the clip's frame exactly")
        XCTAssertGreaterThan(payload.chunks[0].y![0].numericValue, TextBackgroundGeometry.padY(fontSize: style.fontSize), "text is shifted in by the padding")
        XCTAssertEqual(TextStyleValues(layer: layer, composition: project().composition).backgroundColor, "#FFFFFFff")
    }

    func testNoBackgroundMeansNoLabelAndATightFrame() {
        var style = TextStyleValues(composition: project().composition); style.text = "Hello"
        let layer = AddTextLayerCommand(layerId: "t", text: "Hello", atMs: 0, style: style).apply(to: project()).layers[0]
        XCTAssertNil(layer.textPayload?.layout?.background)
        XCTAssertLessThan(layer.frame.height, 80, "the frame hugs one line instead of the old fixed 80")
    }

    func testAlignmentIsReadBackFromTheResolvedLines() {
        for align in ["left", "center", "right"] {
            var style = TextStyleValues(composition: project().composition)
            style.text = "Short\nA much longer line"; style.align = align
            let layer = AddTextLayerCommand(layerId: "t", text: style.text, atMs: 0, style: style).apply(to: project()).layers[0]
            XCTAssertEqual(TextStyleValues(layer: layer, composition: project().composition).align, align, align)
        }
    }

    func testChangingTheBackgroundThroughSetTextCommandRewritesTheLabel() {
        var style = TextStyleValues(composition: project().composition); style.text = "Hello"
        let added = AddTextLayerCommand(layerId: "t", text: "Hello", atMs: 0, style: style).apply(to: project())
        var values = TextStyleValues(layer: added.layers[0], composition: project().composition)
        values.backgroundColor = "#FFD60Aff"
        let with = SetTextCommand(layerId: "t", values: values).apply(to: added).layers[0]
        XCTAssertEqual(with.textPayload?.layout?.background?.fill.flatColor, "#FFD60Aff")
        values.backgroundColor = nil
        let without = SetTextCommand(layerId: "t", values: values).apply(to: added).layers[0]
        XCTAssertNil(without.textPayload?.layout?.background)
    }
}
