import CoreText
import UIKit

/// One already-shaped visual line: the atomic result of running Core Text
/// line-breaking against an `EditorTextLayoutIntent`. `x`/`y` are exactly
/// what becomes `V2TextChunk.x`/`.y` (`y` is the SVG-style baseline
/// position, matching the real schema's semantics).
struct ResolvedTextLine {
    var range: V2TextRange
    var x: Double
    var y: Double
    var width: Double
}

/// Real text shaping via Core Text — the native framework, not a
/// third-party engine (see CLAUDE.md's "no third-party rendering engines"
/// rule). This is the Editor-tier compiler step that resolves
/// `EditorTextLayoutIntent` (wrap policy + alignment) plus a font and a
/// frame width into Protocol V2's atomic `V2TextLayout` + per-line
/// positions — the only place in this app that runs line-breaking, so every
/// renderer downstream only ever reads already-resolved numbers.
enum TextLayoutCompiler {
    static func compile(
        text: String, fontFamily: String, fontSize: Double,
        textAlign: String, wrap: String, maxWidth: Double,
        bold: Bool = false, italic: Bool = false, letterSpacing: Double = 0, lineSpacing: Double = 0
    ) -> (layout: V2TextLayout, lines: [ResolvedTextLine]) {
        let font = resolveFont(family: fontFamily, size: fontSize, bold: bold, italic: italic)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if letterSpacing != 0 { attributes[.kern] = letterSpacing }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = attributed.length

        let ascent = Double(font.ascender)
        let descent = Double(-font.descender)
        let leading = Double(font.leading)
        let lineHeight = ascent + descent + leading + lineSpacing
        let effectiveWidth = wrap == "none" ? Double.greatestFiniteMagnitude : maxWidth

        var lines: [ResolvedTextLine] = []
        var maxLineWidth = 0.0
        var start = 0
        while start < length {
            let count = wrap == "character"
                ? CTTypesetterSuggestClusterBreak(typesetter, start, effectiveWidth)
                : CTTypesetterSuggestLineBreak(typesetter, start, effectiveWidth)
            let safeCount = max(count, 1)
            let range = CFRange(location: start, length: safeCount)
            let line = CTTypesetterCreateLine(typesetter, range)
            var lineAscent: CGFloat = 0, lineDescent: CGFloat = 0, lineLeading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &lineAscent, &lineDescent, &lineLeading)
            maxLineWidth = max(maxLineWidth, width)

            let baselineY = ascent + Double(lines.count) * lineHeight
            let lineX: Double
            switch textAlign {
            case "center": lineX = max((maxWidth - width) / 2, 0)
            case "right", "end": lineX = max(maxWidth - width, 0)
            default: lineX = 0
            }
            lines.append(ResolvedTextLine(
                range: V2TextRange(start: start, end: start + safeCount),
                x: lineX, y: baselineY, width: width
            ))
            start += safeCount
        }
        if lines.isEmpty {
            lines = [ResolvedTextLine(range: V2TextRange(start: 0, end: 0), x: 0, y: ascent, width: 0)]
        }

        let layout = V2TextLayout(
            lineHeight: lineHeight,
            contentWidth: wrap == "none" ? maxLineWidth : maxWidth,
            contentHeight: Double(lines.count) * lineHeight,
            contentOffsetX: 0,
            contentOffsetY: 0
        )
        return (layout, lines)
    }

    /// Shared with the Runtime renderer (`KeyframeSampler.swift`) so the
    /// baseline-to-top conversion there uses identical font metrics to the
    /// ones this compiler resolved the layout against.
    static func resolveFont(family: String, size: Double) -> UIFont {
        UIFont(name: family, size: CGFloat(size)) ?? UIFont.systemFont(ofSize: CGFloat(size))
    }

    /// The face for a bold / italic toggle: the same family's bold / italic variant when it has one (Georgia -> Georgia-Bold), else the
    /// font as it is. Light switch only - no synthetic slant or smear.
    static func resolveFont(family: String, size: Double, bold: Bool, italic: Bool) -> UIFont {
        let base = resolveFont(family: family, size: size)
        guard bold || italic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: CGFloat(size))
    }

    /// `text-transform` applied to the words: the transformed string only when it keeps the same UTF-16 length (so the source ranges
    /// stay valid; true for every Latin and Vietnamese letter, not for the German sharp s).
    static func transformed(_ text: String, _ transform: String?) -> String {
        let result: String
        switch transform {
        case "uppercase": result = text.uppercased()
        case "lowercase": result = text.lowercased()
        case "capitalize": result = text.capitalized
        default: return text
        }
        return result.utf16.count == text.utf16.count ? result : text
    }

    /// The x offset (from the start of `lineText`) of the character at
    /// `localIndex` (UTF-16, relative to `lineText`'s own start) once shaped
    /// with `font` — used by the Runtime to place individually staggered
    /// characters when a `rangeSelectors` entry applies (see
    /// `KeyframeSampler.swift`). Real Core Text per-glyph measurement, same
    /// as the line-breaking above — not an approximation (e.g. not a flat
    /// `index * averageCharWidth`), so staggered characters land exactly
    /// where the unstaggered line would have drawn them, including kerning.
    static func offsetForCharacter(in lineText: String, font: UIFont, localIndex: Int, letterSpacing: Double = 0) -> Double {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if letterSpacing != 0 { attributes[.kern] = letterSpacing }
        let attributed = NSAttributedString(string: lineText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        return Double(CTLineGetOffsetForStringIndex(line, localIndex, nil))
    }
}
