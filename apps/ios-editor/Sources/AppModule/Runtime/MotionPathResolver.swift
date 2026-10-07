import CoreGraphics

/// Runtime (per-frame) resolver for CSS `offset-path` motion
/// (`V2MotionPath` — `Protocol/V2MotionPath.swift`): given a layer's static
/// path geometry plus *this frame's already-sampled* `offsetDistance`/
/// `offsetRotate`/`offsetAnchor`, computes where the layer actually sits
/// this frame.
///
/// Unlike text-on-path (`TextPathResolver`, an Editor-tier compile step that
/// bakes per-character numbers once, since a document's text never
/// re-shapes itself at runtime), this runs fresh every sampled frame:
/// `offsetDistance` is itself a live animated number, so there is nothing to
/// bake ahead of time. Both share the same arc-length machinery
/// (`PathFlattening.swift`) — "distance along a path → point + tangent" is
/// the same question either way.
enum MotionPathResolver {
    /// Converts the protocol's path-contour geometry (`V2PathContour`'s
    /// `line`/`quadratic`/`cubic`/`arc` segments) into a `CGPath` Core
    /// Graphics can flatten. `arc` uses the standard SVG endpoint-to-center
    /// parameterization (W3C SVG 1.1 Appendix F.6), split into ≤90° pieces
    /// each approximated by a cubic bezier — the same technique every
    /// conformant SVG renderer uses for path `A`/`a` commands; not a
    /// shortcut specific to this app.
    static func buildCGPath(contours: [V2PathContour]) -> CGPath {
        let path = CGMutablePath()
        for contour in contours {
            var current = CGPoint(x: contour.start.x, y: contour.start.y)
            path.move(to: current)
            for segment in contour.segments {
                switch segment {
                case .line(let to):
                    let p = CGPoint(x: to.x, y: to.y)
                    path.addLine(to: p)
                    current = p
                case .quadratic(let control, let to):
                    let p = CGPoint(x: to.x, y: to.y)
                    path.addQuadCurve(to: p, control: CGPoint(x: control.x, y: control.y))
                    current = p
                case .cubic(let control1, let control2, let to):
                    let p = CGPoint(x: to.x, y: to.y)
                    path.addCurve(
                        to: p,
                        control1: CGPoint(x: control1.x, y: control1.y),
                        control2: CGPoint(x: control2.x, y: control2.y)
                    )
                    current = p
                case .arc(let radii, let rotation, let largeArc, let sweep, let to):
                    let p = CGPoint(x: to.x, y: to.y)
                    if radii.x == 0 || radii.y == 0 {
                        path.addLine(to: p)
                    } else {
                        for (c1, c2, end) in arcToBezierSegments(
                            from: current, to: p, rx: radii.x, ry: radii.y,
                            xAxisRotationDeg: rotation, largeArc: largeArc, sweep: sweep
                        ) {
                            path.addCurve(to: end, control1: c1, control2: c2)
                        }
                    }
                    current = p
                }
            }
            if contour.closed { path.closeSubpath() }
        }
        return path
    }

    /// SVG elliptical-arc-to-cubic-bezier conversion: endpoint → center
    /// parameterization (W3C SVG 1.1 Appendix F.6.5), then each ≤90° slice
    /// of the arc is approximated via the standard unit-circle bezier
    /// (`4/3 * tan(Δ/4)` control-point distance), scaled/rotated/translated
    /// onto the real ellipse.
    static func arcToBezierSegments(
        from start: CGPoint, to end: CGPoint, rx rxIn: Double, ry ryIn: Double,
        xAxisRotationDeg: Double, largeArc: Bool, sweep: Bool
    ) -> [(CGPoint, CGPoint, CGPoint)] {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        let phi = xAxisRotationDeg * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = Double(start.x - end.x) / 2
        let dy2 = Double(start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }

        let sign: Double = (largeArc != sweep) ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = den > 0 ? sign * (num / den).squareRoot() : 0
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + Double(start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + Double(start.y + end.y) / 2

        func vectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let crossSign: Double = (ux * vy - uy * vx) < 0 ? -1 : 1
            let dot = ux * vx + uy * vy
            let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
            let cosAngle = len > 0 ? min(max(dot / len, -1), 1) : 1
            return crossSign * acos(cosAngle)
        }

        let theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dtheta = vectorAngle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segmentCount = max(Int(ceil(abs(dtheta) / (.pi / 2))), 1)
        let delta = dtheta / Double(segmentCount)

        func transform(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: cx + rx * cosPhi * x - ry * sinPhi * y,
                y: cy + rx * sinPhi * x + ry * cosPhi * y
            )
        }

        var segments: [(CGPoint, CGPoint, CGPoint)] = []
        for i in 0..<segmentCount {
            let ang1 = theta1 + Double(i) * delta
            let ang2 = theta1 + Double(i + 1) * delta
            let t = 4.0 / 3.0 * tan((ang2 - ang1) / 4)
            let bx1 = cos(ang1) - t * sin(ang1)
            let by1 = sin(ang1) + t * cos(ang1)
            let bx2 = cos(ang2) + t * sin(ang2)
            let by2 = sin(ang2) - t * cos(ang2)
            segments.append((transform(bx1, by1), transform(bx2, by2), transform(cos(ang2), sin(ang2))))
        }
        return segments
    }

    /// Resolves this frame's `(dx, dy, rotationDegrees)` to add on top of the
    /// layer's ordinary transform, from its static path geometry plus this
    /// frame's *sampled* `offsetDistance`/`offsetRotate`/`offsetAnchor`.
    /// `dx`/`dy` already have `offsetAnchor` subtracted (the anchor point is
    /// what rides the path — same role as `transform.anchor` for
    /// rotation/scale pivots elsewhere) and are relative to the layer's own
    /// untransformed position, added the same way `transform.translate.x/y`
    /// are added.
    static func resolve(
        motion: V2MotionPath, offsetDistance: Double, offsetRotateMode: String, offsetRotateAngle: Double,
        offsetAnchorX: Double, offsetAnchorY: Double
    ) -> (dx: Double, dy: Double, rotationDegrees: Double) {
        let cgPath = buildCGPath(contours: motion.offsetPath.contours)
        let flattened = flattenPath(cgPath)
        guard flattened.totalLength > 0 else { return (0, 0, 0) }
        let distance = min(max(offsetDistance, 0), 1) * flattened.totalLength
        let (point, tangentAngle) = flattened.position(atDistance: distance)

        let rotation: Double
        switch offsetRotateMode {
        case "fixed":
            rotation = offsetRotateAngle
        case "auto-reverse":
            rotation = tangentAngle + 180 + offsetRotateAngle
        default: // "auto"
            rotation = tangentAngle + offsetRotateAngle
        }

        return (Double(point.x) - offsetAnchorX, Double(point.y) - offsetAnchorY, rotation)
    }
}
