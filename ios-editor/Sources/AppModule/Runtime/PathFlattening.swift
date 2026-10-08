import CoreGraphics

/// A path flattened to line segments, with cumulative arc length at each
/// vertex — answers "where is the point + tangent angle at arc-length D
/// along this path." Shared by `TextPathResolver` (Editor-tier, bakes
/// per-character offsets once at compile time) and `MotionPathResolver`
/// (Runtime, resolves a layer's position fresh every sampled frame since
/// `offsetDistance` is itself a live animated number) — both reduce to the
/// same "distance along a path → point + tangent" question.
struct FlattenedPath {
    var points: [CGPoint] = []
    var cumulativeLengths: [Double] = [0]

    var totalLength: Double { cumulativeLengths.last ?? 0 }

    func position(atDistance distance: Double) -> (point: CGPoint, angleDegrees: Double) {
        guard points.count >= 2 else { return (points.first ?? .zero, 0) }
        let clamped = min(max(distance, 0), totalLength)
        var segmentIndex = cumulativeLengths.count - 2
        for i in 1..<cumulativeLengths.count where cumulativeLengths[i] >= clamped {
            segmentIndex = i - 1
            break
        }
        let p0 = points[segmentIndex]
        let p1 = points[segmentIndex + 1]
        let segStart = cumulativeLengths[segmentIndex]
        let segLength = cumulativeLengths[segmentIndex + 1] - segStart
        let t = segLength > 0 ? (clamped - segStart) / segLength : 0
        let point = CGPoint(x: p0.x + (p1.x - p0.x) * CGFloat(t), y: p0.y + (p1.y - p0.y) * CGFloat(t))
        let angle = atan2(Double(p1.y - p0.y), Double(p1.x - p0.x)) * 180 / .pi
        return (point, angle)
    }
}

/// Flattens `path` into line segments — fixed subdivision count per curve,
/// good enough for glyph/layer-scale placement; not an adaptive,
/// error-bounded tessellator.
func flattenPath(_ path: CGPath) -> FlattenedPath {
    var result = FlattenedPath()
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero

    func addPoint(_ point: CGPoint) {
        if let last = result.points.last {
            let dx = Double(point.x - last.x)
            let dy = Double(point.y - last.y)
            result.cumulativeLengths.append(result.cumulativeLengths.last! + (dx * dx + dy * dy).squareRoot())
        }
        result.points.append(point)
    }

    func addCubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) {
        let steps = 24
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let u = 1 - t
            let x = u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x
            let y = u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y
            addPoint(CGPoint(x: x, y: y))
        }
    }

    path.applyWithBlock { elementPtr in
        let element = elementPtr.pointee
        switch element.type {
        case .moveToPoint:
            current = element.points[0]
            subpathStart = current
            result.points.append(current)
        case .addLineToPoint:
            addPoint(element.points[0])
            current = element.points[0]
        case .addQuadCurveToPoint:
            // Promote quadratic to cubic so there's one shared flattener.
            let c = element.points[0]
            let end = element.points[1]
            let c1 = CGPoint(x: current.x + 2.0/3.0*(c.x - current.x), y: current.y + 2.0/3.0*(c.y - current.y))
            let c2 = CGPoint(x: end.x + 2.0/3.0*(c.x - end.x), y: end.y + 2.0/3.0*(c.y - end.y))
            addCubic(current, c1, c2, end)
            current = end
        case .addCurveToPoint:
            addCubic(current, element.points[0], element.points[1], element.points[2])
            current = element.points[2]
        case .closeSubpath:
            addPoint(subpathStart)
            current = subpathStart
        @unknown default:
            break
        }
    }
    return result
}
