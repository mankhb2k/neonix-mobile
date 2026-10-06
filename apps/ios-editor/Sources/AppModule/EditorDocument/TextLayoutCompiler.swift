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
        textAlign: String, wrap: String, maxWidth: Double
    ) -> (layout: V2TextLayout, lines: [ResolvedTextLine]) {
        let font = resolveFont(family: fontFamily, size: fontSize)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = attributed.length

        let ascent = Double(font.ascender)
        let descent = Double(-font.descender)
        let leading = Double(font.leading)
        let lineHeight = ascent + descent + leading
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
}
