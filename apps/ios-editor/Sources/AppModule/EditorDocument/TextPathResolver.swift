import CoreGraphics
import UIKit

/// Resolves real per-character position + rotation for text following an
/// arbitrary `CGPath` — the same arc-length technique any conformant SVG
/// `<textPath>` renderer uses, built from native Core Graphics/Core Text
/// primitives (no third-party geometry library — see CLAUDE.md's "no
/// third-party rendering engines" rule).
///
/// This is an Editor-tier compiler step, not a Runtime one: it bakes the
/// result into literal `V2TextChunk.dx`/`.dy`/`.rotate` numbers (see
/// `PresetCompiler.swift`), the same fields "wave" already uses — Protocol
/// V2 never sees "this text follows a path," only the resulting per-character
/// offsets. This mirrors the reasoning in CLAUDE.md's "Text layout stays
/// atomic" note: if Protocol V2 kept a live path reference instead, every
/// renderer would need its own path-flattening/arc-length implementation,
/// and subtly different tessellation choices (segment counts, tolerances)
/// would make two renderers draw the same JSON differently — exactly the
/// cross-renderer divergence that note exists to prevent.
enum TextPathResolver {
    /// Resolves `(dx, dy, rotate)` for every character in `lineText`, laid
    /// along `path` starting `startOffset` points from the path's own start.
    /// Each glyph's anchor is its own horizontal center (standard SVG
    /// `textPath` placement), found via the same real Core Text
    /// per-character measurement `TextLayoutCompiler.offsetForCharacter`
    /// already uses for stagger/wave — not an approximation.
    static func resolve(path: CGPath, startOffset: Double, lineText: String, font: UIFont) -> [(dx: Double, dy: Double, rotate: Double)] {
        let charCount = lineText.utf16.count
        guard charCount > 0 else { return [] }
        let flattened = flattenPath(path)
        let offsets = (0...charCount).map { TextLayoutCompiler.offsetForCharacter(in: lineText, font: font, localIndex: $0) }
        return (0..<charCount).map { i in
            let charStart = offsets[i]
            let charWidth = offsets[i + 1] - charStart
            let naturalX = charStart + charWidth / 2
            let (point, angle) = flattened.position(atDistance: startOffset + naturalX)
            return (Double(point.x) - naturalX, Double(point.y), angle)
        }
    }

    /// A circle, the one path shape this slice's compiler integration
    /// supports (see `EditorTextPathIntent`) — chosen as the clearest,
    /// most recognizable "text on a path" demo. The flattening/arc-length
    /// machinery above works for any `CGPath`, though; a future
    /// `pathId`-reference resolver (against the project's real `clipPaths`/
    /// path-layer geometry) would reuse it unchanged.
    ///
    /// Built manually (not via `CGPath(ellipseIn:)`) so the starting point
    /// and direction of travel are explicit and known, rather than relying
    /// on that initializer's internal (undocumented, easy to get backwards)
    /// start-point/winding convention — which, gotten wrong, is exactly what
    /// makes text silently render upside-down along the bottom of the
    /// circle instead of right-side-up along the top. In this app's
    /// composition coordinate system (y-down, origin top-left, matching
    /// every other `x`/`y` in this codebase), starting at -90° (12 o'clock)
    /// and increasing the angle moves toward 3 o'clock — i.e. left-to-right
    /// across the *top* of the circle, reading normally.
    static func circlePath(radius: Double, center: CGPoint, segmentsPerCircle: Int = 128) -> CGPath {
        let path = CGMutablePath()
        for i in 0...segmentsPerCircle {
            let t = Double(i) / Double(segmentsPerCircle)
            let angle = (-90 + 360 * t) * Double.pi / 180
            let point = CGPoint(x: center.x + CGFloat(radius * cos(angle)), y: center.y + CGFloat(radius * sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
