import Foundation

/// What the Text sheet edits on one text clip: the words and the look. Sizes are in composition units and scale with the canvas (the old
/// fixed 32 was 8.9 % of a 360-wide canvas); every effect (outline, glow, shadow, spacing) is a fraction of the font size, so changing the
/// size keeps the look in proportion.
struct TextStyleValues: Equatable {
    var text = ""
    /// A font name `UIFont(name:size:)` knows (PostScript name), the same string Protocol V2 keeps in `font.families`.
    var fontFamily = "Helvetica"
    var fontSize = 32.0
    /// `#RRGGBBAA`, like `EditorTextLayer.color`.
    var color = "#FFFFFFff"
    /// "left" | "center" | "right" (the lines of a multi-line text align to each other within the clip).
    var align = "center"

    // Background label (`TextBackgroundGeometry`); nil colour = none.
    var backgroundColor: String?
    var backgroundOpacity = 1.0
    /// "hug" (story style) | "box" (one rectangle).
    var backgroundStyle = "hug"
    var backgroundRadius = TextBackgroundGeometry.defaultRadius
    var backgroundPadX = TextBackgroundGeometry.defaultPadX
    var backgroundPadY = TextBackgroundGeometry.defaultPadY

    // Outline, glow, shadow: nil colour = off. Widths, blurs and distances are fractions of the font size.
    var strokeColor: String?
    var strokeWidth = 0.06
    var glowColor: String?
    var glowIntensity = 0.8
    var glowBlur = 0.35
    var shadowColor: String?
    var shadowOpacity = 0.6
    var shadowBlur = 0.12
    var shadowDistance = 0.10
    /// Degrees, 0 = to the right, 90 = down.
    var shadowAngle = 45.0

    // Spacing: fractions of the font size; 0 = the font's own.
    var letterSpacing = 0.0
    var lineSpacing = 0.0

    // Case, bold, italic, underline.
    var bold = false
    var italic = false
    var underline = false
    /// "uppercase" | "lowercase" | "capitalize"; nil = as typed.
    var textCase: String?

    /// -100...100, see `TextCurve`.
    var curve = 0.0

    static let placeholder = "Enter text"
    /// The words of a new clip: something to see on the stage at once, selected on the first tap so typing replaces it.
    static let defaultText = "Hello"

    /// The defaults for a new clip on this canvas.
    init(composition: V2Composition) {
        fontSize = Self.defaultSize(for: composition)
    }

    init() {}

    /// The authoring intent these values describe - the one place both `AddTextLayerCommand` and `SetTextCommand` build it.
    func editorText(wrap: String = "none") -> EditorTextLayer {
        EditorTextLayer(
            text: text, fontFamily: fontFamily, fontSize: fontSize, color: color,
            layout: EditorTextLayoutIntent(textAlign: align, wrap: wrap),
            background: backgroundColor.map {
                EditorTextBackground(color: $0, opacity: backgroundOpacity, style: backgroundStyle, radius: backgroundRadius, padX: backgroundPadX, padY: backgroundPadY)
            },
            stroke: strokeColor.map { EditorTextStroke(color: $0, width: strokeWidth * fontSize) },
            glow: glowColor.map { EditorTextGlow(color: $0, intensity: glowIntensity, blur: glowBlur * fontSize) },
            shadow: shadowColor.map { EditorTextShadow(color: $0, opacity: shadowOpacity, blur: shadowBlur * fontSize, distance: shadowDistance * fontSize, angle: shadowAngle) },
            letterSpacing: letterSpacing == 0 ? nil : letterSpacing * fontSize,
            lineSpacing: lineSpacing == 0 ? nil : lineSpacing * fontSize,
            bold: bold ? true : nil, italic: italic ? true : nil, underline: underline ? true : nil,
            textCase: textCase,
            curve: curve == 0 ? nil : curve
        )
    }

    /// The values a text layer has now. What the clip's V2 data still says (words, font, colours, outline, spacing, case, ...) is read
    /// back from it; the settings V2 only keeps as resolved geometry (the label's padding and corner radius, curve) come from
    /// `TextIntentCache` while the clip is exactly as the sheet last left it, else the defaults.
    init(layer: V2Layer, composition: V2Composition) {
        self.init(composition: composition)
        guard let payload = layer.textPayload else { return }
        if let remembered = TextIntentCache.shared.values(for: layer) {
            self = remembered
            return
        }
        text = payload.source.text
        if let span = payload.chunks.first?.spans.first {
            if let family = span.font.families.first { fontFamily = family }
            fontSize = span.font.size.numericValue
            if let flat = span.fill?.flatColor { color = flat }
            bold = (span.font.weight ?? 400) >= 600
            italic = span.font.style == "italic"
            underline = span.textDecoration?.underline != nil
            textCase = span.textTransform
            if let stroke = span.stroke?.flatColor, let width = span.strokeWidth?.numericValue, fontSize > 0 {
                strokeColor = stroke; strokeWidth = width / fontSize
            }
            if case .length(let spacing)? = span.letterSpacing, fontSize > 0 { letterSpacing = spacing.numericValue / fontSize }
            for shadow in span.shadows ?? [] where fontSize > 0 {
                let alpha = Double(UInt8(shadow.color.suffix(2), radix: 16) ?? 255) / 255
                let rgb = "#" + shadow.color.dropFirst().prefix(6) + "ff"
                if shadow.offsetX == 0 && shadow.offsetY == 0 {
                    if glowColor == nil { glowColor = rgb; glowIntensity = alpha; glowBlur = shadow.blur / fontSize }
                } else {
                    shadowColor = rgb; shadowOpacity = alpha; shadowBlur = shadow.blur / fontSize
                    shadowDistance = (shadow.offsetX * shadow.offsetX + shadow.offsetY * shadow.offsetY).squareRoot() / fontSize
                    shadowAngle = atan2(shadow.offsetY, shadow.offsetX) * 180 / Double.pi
                }
            }
        }
        if let fill = payload.layout?.background?.fill.flatColor {
            let digits = fill.dropFirst()
            backgroundColor = "#" + digits.prefix(6) + "ff"
            backgroundOpacity = digits.count == 8 ? Double(UInt8(digits.suffix(2), radix: 16) ?? 255) / 255 : 1
        }
        let natural = TextLayoutCompiler.resolveFont(family: fontFamily, size: fontSize, bold: bold, italic: italic)
        if let lineHeight = payload.layout?.lineHeight, fontSize > 0 {
            let base = Double(natural.ascender - natural.descender + natural.leading)
            lineSpacing = abs(lineHeight - base) < 0.01 ? 0 : (lineHeight - base) / fontSize
        }
        align = Self.inferredAlign(payload: payload, values: self, frameWidth: layer.frame.width)
    }

    private var effectivePadX: Double { backgroundColor == nil ? 0 : TextBackgroundGeometry.padX(fontSize: fontSize, factor: backgroundPadX) }
    private var effectivePadY: Double { backgroundColor == nil ? 0 : TextBackgroundGeometry.padY(fontSize: fontSize, factor: backgroundPadY) }

    /// V2 keeps no "align" (only each line's resolved x), so it is read back by asking which alignment reproduces those x's.
    private static func inferredAlign(payload: V2TextLayerPayload, values: TextStyleValues, frameWidth: Double) -> String {
        let padX = values.effectivePadX
        for candidate in ["center", "left", "right"] {
            var trial = values
            trial.align = candidate
            let (_, lines) = trial.layout(maxWidth: frameWidth - 2 * padX)
            let xs = payload.chunks.compactMap { $0.x?.first?.numericValue }
            if xs.count == lines.count, zip(xs, lines).allSatisfy({ abs($0 - ($1.x + padX)) < 0.5 }) { return candidate }
        }
        return "center"
    }

    /// The lines these values lay out into at this width (the same call the compiler makes).
    private func layout(maxWidth: Double) -> (layout: V2TextLayout, lines: [ResolvedTextLine]) {
        TextLayoutCompiler.compile(
            text: TextLayoutCompiler.transformed(text, textCase), fontFamily: fontFamily, fontSize: fontSize,
            textAlign: align, wrap: "none", maxWidth: maxWidth,
            bold: bold, italic: italic, letterSpacing: letterSpacing * fontSize, lineSpacing: lineSpacing * fontSize
        )
    }

    /// The clip's frame height: exactly the text block (plus the label's padding), so the text sits centred where the clip is.
    static func frameHeight(for values: TextStyleValues, width: Double) -> Double {
        let (layout, _) = values.layout(maxWidth: width - 2 * values.effectivePadX)
        return max(values.fontSize * 1.2, (layout.contentHeight ?? 0) + 2 * values.effectivePadY)
    }

    static func defaultSize(for composition: V2Composition) -> Double { (composition.width * 32 / 360).rounded() }

    /// The Size slider's range: 5.5 % ... 18 % of the canvas width.
    static func sizeRange(for composition: V2Composition) -> ClosedRange<Double> {
        (composition.width * 0.055).rounded()...(composition.width * 0.18).rounded()
    }
}

/// The part of a text clip's look that Protocol V2 keeps only as resolved geometry (label padding and corner radius, curve): remembered
/// per clip for the session. An entry counts only while the clip's text payload is exactly what it compiled to (`fingerprint`), so an
/// undo, a redo or any other command that rewrites the clip makes the entry stale and the sheet falls back to what V2 still says.
final class TextIntentCache: @unchecked Sendable {
    static let shared = TextIntentCache()
    private let lock = NSLock()
    private var entries: [String: (values: TextStyleValues, fingerprint: Int)] = [:]

    func remember(_ values: TextStyleValues, for layer: V2Layer) {
        let fingerprint = Self.fingerprint(of: layer)
        lock.lock(); defer { lock.unlock() }
        entries[layer.id] = (values, fingerprint)
    }

    func values(for layer: V2Layer) -> TextStyleValues? {
        let fingerprint = Self.fingerprint(of: layer)
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[layer.id], entry.fingerprint == fingerprint else { return nil }
        return entry.values
    }

    private static func fingerprint(of layer: V2Layer) -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let payload = layer.textPayload, let data = try? encoder.encode(payload) else { return 0 }
        return data.hashValue
    }
}
