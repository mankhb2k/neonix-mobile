import Foundation

/// What the Text sheet edits on one text clip: the words and the look (user 2026-10-13: Font and Style only). Sizes are in
/// composition units and scale with the canvas (the old fixed 32 was 8.9 % of a 360-wide canvas). Stroke / background presets of
/// the Design Lab are not here: the renderer draws neither yet.
struct TextStyleValues: Equatable {
    var text = ""
    /// A font name `UIFont(name:size:)` knows (PostScript name), the same string Protocol V2 keeps in `font.families`.
    var fontFamily = "Helvetica"
    var fontSize = 32.0
    /// `#RRGGBBAA`, like `EditorTextLayer.color`.
    var color = "#FFFFFFff"
    /// "left" | "center" | "right" (the lines of a multi-line text align to each other within the clip).
    var align = "center"
    /// The rounded story-style label behind the text (`TextBackgroundGeometry`); nil = none.
    var backgroundColor: String?

    static let placeholder = "Enter text"
    /// The words of a new clip: something to see on the stage at once, selected on the first tap so typing replaces it.
    static let defaultText = "Hello"

    /// The defaults for a new clip on this canvas.
    init(composition: V2Composition) {
        fontSize = Self.defaultSize(for: composition)
    }

    init() {}

    /// The values a text layer has now (its first span - the editor authors one font per layer).
    init(layer: V2Layer, composition: V2Composition) {
        self.init(composition: composition)
        guard let payload = layer.textPayload else { return }
        text = payload.source.text
        if let span = payload.chunks.first?.spans.first {
            if let family = span.font.families.first { fontFamily = family }
            fontSize = span.font.size.numericValue
            if let flat = span.fill?.flatColor { color = flat }
        }
        backgroundColor = payload.layout?.background?.fill.flatColor
        align = Self.inferredAlign(payload: payload, values: self, frameWidth: layer.frame.width)
    }

    /// V2 keeps no "align" (only each line's resolved x), so it is read back by asking which alignment reproduces those x's.
    private static func inferredAlign(payload: V2TextLayerPayload, values: TextStyleValues, frameWidth: Double) -> String {
        let padX = values.backgroundColor == nil ? 0 : TextBackgroundGeometry.padX(fontSize: values.fontSize)
        for candidate in ["center", "left", "right"] {
            let (_, lines) = TextLayoutCompiler.compile(
                text: values.text, fontFamily: values.fontFamily, fontSize: values.fontSize,
                textAlign: candidate, wrap: "none", maxWidth: frameWidth - 2 * padX
            )
            let xs = payload.chunks.compactMap { $0.x?.first?.numericValue }
            if xs.count == lines.count, zip(xs, lines).allSatisfy({ abs($0 - ($1.x + padX)) < 0.5 }) { return candidate }
        }
        return "center"
    }

    /// The clip's frame height: exactly the text block (plus the label's padding), so the text sits centred where the clip is.
    static func frameHeight(for values: TextStyleValues, width: Double) -> Double {
        let padY = values.backgroundColor == nil ? 0 : TextBackgroundGeometry.padY(fontSize: values.fontSize)
        let padX = values.backgroundColor == nil ? 0 : TextBackgroundGeometry.padX(fontSize: values.fontSize)
        let (layout, _) = TextLayoutCompiler.compile(
            text: values.text, fontFamily: values.fontFamily, fontSize: values.fontSize,
            textAlign: values.align, wrap: "none", maxWidth: width - 2 * padX
        )
        return max(values.fontSize * 1.2, (layout.contentHeight ?? 0) + 2 * padY)
    }

    static func defaultSize(for composition: V2Composition) -> Double { (composition.width * 32 / 360).rounded() }

    /// The Size slider's range: 5.5 % ... 18 % of the canvas width.
    static func sizeRange(for composition: V2Composition) -> ClosedRange<Double> {
        (composition.width * 0.055).rounded()...(composition.width * 0.18).rounded()
    }
}
