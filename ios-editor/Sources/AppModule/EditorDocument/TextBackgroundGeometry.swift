import CoreGraphics

/// The rounded background label behind a text clip (Facebook / Instagram story style, user 2026-10-14): one shape that hugs every
/// line, so lines of different lengths make a stepped outline - convex corners outside, concave fillets where two lines meet.
/// Resolved at compile time into Protocol V2 geometry (`V2PathContour`: lines and arcs), so V2 only ever sees numbers, never "story
/// style" (CLAUDE.md, "Text layout stays atomic").
enum TextBackgroundGeometry {
    /// Padding and corner radius follow the font size, like the stories apps do; the Background badge's sliders change the factors.
    static let defaultPadX = 0.32, defaultPadY = 0.10, defaultRadius = 0.30
    static func padX(fontSize: Double, factor: Double? = nil) -> Double { fontSize * (factor ?? defaultPadX) }
    static func padY(fontSize: Double, factor: Double? = nil) -> Double { fontSize * (factor ?? defaultPadY) }
    static func radius(fontSize: Double, factor: Double? = nil) -> Double { fontSize * (factor ?? defaultRadius) }

    /// `lines` are the boxes' left/right edges per line, top to bottom; the lines stack without a gap (`boundaries` are the
    /// n + 1 horizontal edges: the top of the box, the line separators, the bottom).
    static func contour(lines: [(left: Double, right: Double)], boundaries: [Double], radius: Double) -> V2PathContour? {
        guard !lines.isEmpty, boundaries.count == lines.count + 1 else { return nil }
        // Clockwise (y down): along the top, down the right side step by step, back up the left side.
        var points: [(x: Double, y: Double)] = [(lines[0].left, boundaries[0]), (lines[0].right, boundaries[0])]
        for i in 0..<lines.count {
            points.append((lines[i].right, boundaries[i + 1]))
            if i + 1 < lines.count { points.append((lines[i + 1].right, boundaries[i + 1])) }
        }
        points.append((lines[lines.count - 1].left, boundaries[lines.count]))
        for i in stride(from: lines.count - 1, through: 1, by: -1) {
            points.append((lines[i].left, boundaries[i]))
            points.append((lines[i - 1].left, boundaries[i]))
        }
        let vertices = simplified(points)
        guard vertices.count >= 3 else { return nil }

        func length(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double { ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() }
        let n = vertices.count
        // Per corner: where its arc starts and ends, and its radius (no bigger than half of either edge).
        var corners: [(entry: V2PathPoint, exit: V2PathPoint, r: Double, sweep: Bool)] = []
        for k in 0..<n {
            let previous = vertices[(k + n - 1) % n], v = vertices[k], next = vertices[(k + 1) % n]
            let lengthIn = length(previous, v), lengthOut = length(v, next)
            let r = max(min(radius, lengthIn / 2, lengthOut / 2), 0)
            let dirIn = (x: (v.x - previous.x) / lengthIn, y: (v.y - previous.y) / lengthIn)
            let dirOut = (x: (next.x - v.x) / lengthOut, y: (next.y - v.y) / lengthOut)
            let cross = dirIn.x * dirOut.y - dirIn.y * dirOut.x   // > 0: a clockwise turn on screen = a convex corner
            corners.append((
                entry: V2PathPoint(x: v.x - dirIn.x * r, y: v.y - dirIn.y * r),
                exit: V2PathPoint(x: v.x + dirOut.x * r, y: v.y + dirOut.y * r),
                r: r, sweep: cross > 0
            ))
        }
        var segments: [V2PathSegment] = []
        for k in 1...n {
            let corner = corners[k % n]
            segments.append(.line(to: corner.entry))
            if corner.r > 0.001 {
                segments.append(.arc(radii: V2PathPoint(x: corner.r, y: corner.r), rotation: 0, largeArc: false, sweep: corner.sweep, to: corner.exit))
            }
        }
        return V2PathContour(id: "text-background", start: corners[0].exit, segments: segments, closed: true)
    }

    /// Drops repeated points and the middle one of three collinear points (two equal-width lines make one straight side).
    private static func simplified(_ points: [(x: Double, y: Double)]) -> [(x: Double, y: Double)] {
        var result: [(x: Double, y: Double)] = []
        for p in points where !(result.last.map { abs($0.x - p.x) < 0.01 && abs($0.y - p.y) < 0.01 } ?? false) { result.append(p) }
        if let first = result.first, let last = result.last, result.count > 1, abs(first.x - last.x) < 0.01, abs(first.y - last.y) < 0.01 { result.removeLast() }
        var changed = true
        while changed && result.count > 3 {
            changed = false
            for k in 0..<result.count {
                let a = result[(k + result.count - 1) % result.count], b = result[k], c = result[(k + 1) % result.count]
                if abs((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)) < 0.0001 { result.remove(at: k); changed = true; break }
            }
        }
        return result
    }
}
