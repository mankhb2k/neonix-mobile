import UIKit

/// The Curve badge: bends one line of text into an arc. Resolved at compile time into per-character `dx`/`dy`/`rotate` (like wave and
/// text-on-path), so Protocol V2 never sees "curve".
///
/// `curve` runs -100...100; the arc's half angle grows with it (100 = 90 % of a half turn each side of the middle), so the bend looks the
/// same for a short and a long line. Positive = an arch (the middle stays on the baseline, the ends drop and tilt outward), negative = a
/// bowl (the ends rise).
enum TextCurve {
    static func placements(lineText: String, font: UIFont, letterSpacing: Double, lineWidth: Double, curve: Double) -> [(dx: Double, dy: Double, rotate: Double)]? {
        let count = lineText.utf16.count
        guard count > 0, lineWidth > 1, curve != 0 else { return nil }
        let halfAngle = min(abs(curve), 100) / 100 * Double.pi * 0.9
        let radius = (lineWidth / 2) / halfAngle
        let sign: Double = curve > 0 ? 1 : -1
        return (0..<count).map { i in
            let left = TextLayoutCompiler.offsetForCharacter(in: lineText, font: font, localIndex: i, letterSpacing: letterSpacing)
            let right = i + 1 < count
                ? TextLayoutCompiler.offsetForCharacter(in: lineText, font: font, localIndex: i + 1, letterSpacing: letterSpacing)
                : lineWidth
            let centre = (left + right) / 2 - lineWidth / 2        // distance from the middle of the line along the straight baseline
            let theta = centre / radius                             // the same distance along the arc
            return (
                dx: radius * sin(theta) - centre,
                dy: sign * radius * (1 - cos(theta)),
                rotate: sign * theta * 180 / Double.pi
            )
        }
    }
}
