import XCTest
import UIKit
@testable import NeonixEditor

/// The Text sheet's Style badges end to end through the real pipeline: values -> `compile` -> Protocol V2 -> read back and sampled.
final class TextStyleTests: XCTestCase {
    private var project: V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
    }

    private func base(_ text: String = "Hello") -> TextStyleValues {
        var values = TextStyleValues(composition: project.composition)
        values.text = text
        return values
    }

    /// Each call is its own clip (the memory is per layer id).
    private func layer(_ values: TextStyleValues) -> V2Layer {
        AddTextLayerCommand(layerId: "t-\(UUID().uuidString.prefix(6))", text: values.text, atMs: 0, style: values).apply(to: project).layers[0]
    }

    private func span(_ layer: V2Layer) -> V2TextSpan { layer.textPayload!.chunks[0].spans[0] }

    private func readBack(_ layer: V2Layer) -> TextStyleValues { TextStyleValues(layer: layer, composition: project.composition) }

    /// A layer as V2 alone would describe it (no remembered settings): the payload re-encoded.
    private func withoutMemory(_ layer: V2Layer) -> V2Layer {
        var copy = layer
        copy.id = "other-" + layer.id
        return copy
    }

    // MARK: Stroke

    func testStrokeIsOutlineUnderTheFillAndReadsBack() {
        var values = base(); values.strokeColor = "#000000ff"; values.strokeWidth = 0.1
        let l = layer(values)
        XCTAssertEqual(span(l).stroke?.flatColor, "#000000ff")
        XCTAssertEqual(span(l).strokeWidth?.numericValue ?? 0, values.fontSize * 0.1, accuracy: 1e-9)
        XCTAssertEqual(span(l).paintOrder, [.stroke, .fill], "the outline goes under the fill")
        let back = readBack(withoutMemory(l))
        XCTAssertEqual(back.strokeColor, "#000000ff")
        XCTAssertEqual(back.strokeWidth, 0.1, accuracy: 1e-9)
        var none = base(); none.strokeColor = "#000000ff"; none.strokeWidth = 0
        XCTAssertNil(span(layer(none)).stroke, "a zero width is no outline")
    }

    func testAStrokedRunIsSampledWithItsOutline() {
        var values = base(); values.strokeColor = "#FF0000ff"; values.strokeWidth = 0.1
        let run = sampleLayer(layer(values), atMs: 0).textRuns![0]
        XCTAssertEqual(run.strokeColor, "#FF0000ff")
        XCTAssertGreaterThan(run.strokeWidth, 0)
        let outline = GlyphOutline.outline(text: "Hello", font: run.uiFont, letterSpacing: 0, underline: false)
        XCTAssertFalse(outline.path.isEmpty)
        XCTAssertGreaterThan(outline.size.width, 20)
    }

    // MARK: Glow and shadow

    func testGlowAndShadowBecomeV2ShadowsAndReadBack() {
        var values = base()
        values.glowColor = "#FFD60Aff"; values.glowIntensity = 0.8; values.glowBlur = 0.4
        values.shadowColor = "#000000ff"; values.shadowOpacity = 0.5; values.shadowBlur = 0.2; values.shadowDistance = 0.1; values.shadowAngle = 90
        let shadows = span(layer(values)).shadows!
        XCTAssertEqual(shadows.count, 3, "two glow layers (wide, tight) and the drop shadow")
        XCTAssertTrue(shadows[0].offsetX == 0 && shadows[0].offsetY == 0 && shadows[1].offsetX == 0)
        XCTAssertEqual(shadows[2].offsetX, 0, accuracy: 1e-9)
        XCTAssertEqual(shadows[2].offsetY, values.fontSize * 0.1, accuracy: 1e-9, "angle 90 = straight down")
        XCTAssertEqual(shadows[2].color, colorWithAlphaScaled("#000000ff", by: 0.5))
        let back = readBack(withoutMemory(layer(values)))
        XCTAssertEqual(back.glowColor, "#FFD60Aff")
        XCTAssertEqual(back.glowIntensity, 0.8, accuracy: 0.01)
        XCTAssertEqual(back.shadowColor, "#000000ff")
        XCTAssertEqual(back.shadowAngle, 90, accuracy: 0.01)
        XCTAssertEqual(back.shadowDistance, 0.1, accuracy: 1e-6)
        XCTAssertNil(span(layer(base())).shadows)
    }

    // MARK: Spacing

    func testLetterAndLineSpacingWidenTheLayout() {
        let plain = layer(base("Hi\nthere"))
        var spaced = base("Hi\nthere"); spaced.letterSpacing = 0.2; spaced.lineSpacing = 0.5
        let l = layer(spaced)
        XCTAssertGreaterThan(l.textPayload!.layout!.lineHeight, plain.textPayload!.layout!.lineHeight + 10)
        XCTAssertGreaterThan(l.frame.height, plain.frame.height + 10, "the clip's frame follows the line spacing")
        XCTAssertEqual(span(l).letterSpacing.map { if case .length(let v) = $0 { v.numericValue } else { 0 } } ?? 0, spaced.fontSize * 0.2, accuracy: 1e-9)
        let back = readBack(withoutMemory(l))
        XCTAssertEqual(back.letterSpacing, 0.2, accuracy: 1e-6)
        XCTAssertEqual(back.lineSpacing, 0.5, accuracy: 0.01)
        XCTAssertEqual(readBack(withoutMemory(plain)).lineSpacing, 0, accuracy: 1e-9)
    }

    func testLetterSpacingMovesTheCharactersApart() {
        var spaced = base("Hello"); spaced.letterSpacing = 0.3; spaced.curve = 50   // per-character runs show the offsets
        let runs = sampleLayer(layer(spaced), atMs: 0).textRuns!
        var tight = spaced; tight.letterSpacing = 0
        let tightRuns = sampleLayer(layer(tight), atMs: 0).textRuns!
        XCTAssertGreaterThan((runs.last!.x - runs.first!.x), (tightRuns.last!.x - tightRuns.first!.x) + 10)
    }

    // MARK: Case, bold, italic, underline

    func testCaseTransformsTheDrawnWordsNotTheSourceAndWidensTheLine() {
        var upper = base("hello"); upper.textCase = "uppercase"
        let l = layer(upper)
        XCTAssertEqual(l.textPayload!.source.text, "hello", "what was typed is kept")
        XCTAssertEqual(span(l).textTransform, "uppercase")
        XCTAssertEqual(sampleLayer(l, atMs: 0).textRuns![0].text, "HELLO")
        let lower = base("hello")
        XCTAssertGreaterThan(l.textPayload!.layout!.contentWidth ?? 0, layer(lower).textPayload!.layout!.contentWidth ?? 0, "the layout measures the uppercase words")
        XCTAssertEqual(readBack(withoutMemory(l)).textCase, "uppercase")
        XCTAssertEqual(readBack(withoutMemory(l)).text, "hello")
        var title = base("hello there"); title.textCase = "capitalize"
        XCTAssertEqual(sampleLayer(layer(title), atMs: 0).textRuns![0].text, "Hello There")
        XCTAssertEqual(TextLayoutCompiler.transformed("straße", "uppercase"), "straße", "a transform that changes the length is not applied")
        XCTAssertEqual(TextLayoutCompiler.transformed("Việt Nam", "uppercase"), "VIỆT NAM")
    }

    func testBoldItalicAndUnderline() {
        var values = base(); values.fontFamily = "Georgia"; values.bold = true; values.italic = true; values.underline = true
        let l = layer(values)
        XCTAssertEqual(span(l).font.weight, 700)
        XCTAssertEqual(span(l).font.style, "italic")
        XCTAssertNotNil(span(l).textDecoration?.underline)
        let run = sampleLayer(l, atMs: 0).textRuns![0]
        XCTAssertTrue(run.bold && run.italic && run.underline)
        XCTAssertTrue(run.uiFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(run.uiFont.fontDescriptor.symbolicTraits.contains(.traitItalic))
        let back = readBack(withoutMemory(l))
        XCTAssertTrue(back.bold && back.italic && back.underline)
        let plain = layer(base())
        XCTAssertNil(span(plain).font.weight); XCTAssertNil(span(plain).textDecoration)
        XCTAssertFalse(sampleLayer(plain, atMs: 0).textRuns![0].bold)
    }

    // MARK: Background

    func testBackgroundOpacityRadiusPaddingAndBox() throws {
        var values = base("Hi\nthere you"); values.backgroundColor = "#FFFFFFff"
        let hug = layer(values)
        var box = values; box.backgroundStyle = "box"; box.backgroundOpacity = 0.5; box.backgroundRadius = 0.1; box.backgroundPadX = 0.5; box.backgroundPadY = 0.3
        let l = layer(box)
        let fill = try XCTUnwrap(l.textPayload?.layout?.background?.fill.flatColor)
        XCTAssertEqual(fill.lowercased(), "#ffffff80", "opacity 0.5 halves the alpha")
        let hugContour = try XCTUnwrap(hug.textPayload?.layout?.background?.contours.first)
        let boxContour = try XCTUnwrap(l.textPayload?.layout?.background?.contours.first)
        let arcs: (V2PathContour) -> Int = { $0.segments.filter { if case .arc = $0 { return true } else { return false } }.count }
        XCTAssertGreaterThan(arcs(hugContour), 4, "two lines of different length make a stepped label")
        XCTAssertEqual(arcs(boxContour), 4, "box = one rounded rectangle")
        XCTAssertGreaterThan(l.frame.height, hug.frame.height, "more height padding grows the clip")
        let back = readBack(withoutMemory(l))
        XCTAssertEqual(back.backgroundColor, "#FFFFFFff")
        XCTAssertEqual(back.backgroundOpacity, 0.5, accuracy: 0.01)
        // The padding and corner radius are not in V2: the cache gives them back while the clip is untouched.
        let remembered = readBack(l)
        XCTAssertEqual(remembered.backgroundStyle, "box")
        XCTAssertEqual(remembered.backgroundPadX, 0.5, accuracy: 1e-9)
    }

    // MARK: Curve

    func testCurveBendsTheLineIntoAnArc() {
        var arch = base("Hello world"); arch.curve = 60
        let l = layer(arch)
        let chunk = l.textPayload!.chunks[0]
        let dy = chunk.dy!.map(\.numericValue), rotate = chunk.rotate!
        XCTAssertEqual(dy.count, "Hello world".utf16.count)
        XCTAssertGreaterThan(dy.first!, dy[dy.count / 2], "an arch: the ends drop below the middle")
        XCTAssertEqual(dy.first!, dy.last!, accuracy: 6, "about symmetric (the first and last letters differ in width)")
        XCTAssertLessThan(rotate.first!, 0)
        XCTAssertGreaterThan(rotate.last!, 0)
        var bowl = arch; bowl.curve = -60
        let b = layer(bowl).textPayload!.chunks[0]
        XCTAssertLessThan(b.dy!.first!.numericValue, b.dy![b.dy!.count / 2].numericValue, "a bowl: the ends rise")
        XCTAssertNil(layer(base("Hello world")).textPayload!.chunks[0].dy, "no curve, no per-character offsets")
        XCTAssertEqual(readBack(l).curve, 60, "the cache keeps the curve")
        XCTAssertEqual(readBack(withoutMemory(l)).curve, 0, "V2 alone does not")
        XCTAssertNil(TextCurve.placements(lineText: "", font: .systemFont(ofSize: 20), letterSpacing: 0, lineWidth: 0, curve: 50))
    }

    // MARK: Memory

    func testTheMemoryGoesStaleWhenTheClipIsRewrittenBehindIt() {
        var arch = base(); arch.curve = 40
        var p = AddTextLayerCommand(layerId: "t", text: "Hello", atMs: 0, style: arch).apply(to: project)
        XCTAssertEqual(TextStyleValues(layer: p.layers[0], composition: p.composition).curve, 40)
        // Another style written straight (as an undo would restore an older layer): the entry no longer matches.
        var older = p.layers[0]
        older.payload = layer(base("Other")).payload
        XCTAssertEqual(TextStyleValues(layer: older, composition: p.composition).curve, 0)
        // The words change through the command: the memory follows.
        p = SetTextContentCommand(layerId: "t", text: "New words").apply(to: p)
        let after = TextStyleValues(layer: p.layers[0], composition: p.composition)
        XCTAssertEqual(after.curve, 40)
        XCTAssertEqual(after.text, "New words")
    }

    func testColourWithAlphaScaled() {
        XCTAssertEqual(colorWithAlphaScaled("#112233ff", by: 0.5), "#11223380")
        XCTAssertEqual(colorWithAlphaScaled("#112233", by: 1), "#112233ff")
        XCTAssertEqual(colorWithAlphaScaled("#11223380", by: 0), "#11223300")
    }
}
