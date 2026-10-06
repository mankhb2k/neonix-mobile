import Foundation

// Port of packages/motion-protocol/src/v2/paint.ts. Structural shape only —
// see V2Common.swift's note on dropped Zod validation/defaults.

/// SVG 2D matrix: `matrix(a b c d e f)`. Distinct from the layer `V2Transform`
/// (which is 3D-capable) — paint servers only ever need the flat SVG form.
struct V2PaintTransform: Codable {
    var a: Double, b: Double, c: Double, d: Double, e: Double, f: Double
}

struct V2GradientStop: Codable {
    var offset: Double
    var color: V2Color
    var stopOpacity: Double?
}

enum V2GradientSpreadMethod: String, Codable {
    case pad, reflect, repeat_ = "repeat"
}

enum V2GradientUnits: String, Codable {
    case objectBoundingBox, userSpaceOnUse
}

struct V2GradientCommon: Codable {
    var stops: [V2GradientStop]?
    var spreadMethod: V2GradientSpreadMethod?
    var gradientUnits: V2GradientUnits?
    var gradientTransform: V2PaintTransform?
    var href: String?
}

/// No `angle` shorthand — that was only a compatibility alias for `x1/y1/x2/y2`
/// in the real schema (the compiler lowers it to x/y); this app always
/// authors the explicit coordinate form.
struct V2LinearGradient: Codable {
    var x1: V2SvgLength?
    var y1: V2SvgLength?
    var x2: V2SvgLength?
    var y2: V2SvgLength?
    var common: V2GradientCommon
}

struct V2RadialGradient: Codable {
    var cx: V2SvgLength?
    var cy: V2SvgLength?
    var radius: V2SvgLength?
    var radiusX: V2SvgLength?
    var radiusY: V2SvgLength?
    var fx: V2SvgLength?
    var fy: V2SvgLength?
    var fr: V2SvgLength?
    var common: V2GradientCommon
}

struct V2ConicGradient: Codable {
    var from: Double?
    var cx: Double?
    var cy: Double?
    var common: V2GradientCommon
}

enum V2PatternAlign: String, Codable {
    case none, xMinYMin, xMidYMin, xMaxYMin, xMinYMid, xMidYMid, xMaxYMid, xMinYMax, xMidYMax, xMaxYMax
}

struct V2PatternViewBox: Codable {
    var x: Double, y: Double, width: Double, height: Double
    var align: V2PatternAlign?
    var meetOrSlice: String?
}

/// Shared fill/stroke style on a pattern content node.
struct V2PatternNodeStyle: Codable {
    var fill: V2Paint?
    var fillOpacity: Double?
    var stroke: V2Paint?
    var strokeWidth: V2SvgLength?
    var strokeOpacity: Double?
}

/// Pattern content is a recursive SVG-node tree. `V2PatternFill.content` is
/// always an `Array`, which is heap-indirect in Swift regardless of element
/// type — that's what breaks the value-type recursion cycle with `V2Paint`
/// (via `V2PatternNodeStyle.fill`/`stroke`) without needing `indirect` on
/// `V2Paint` itself.
indirect enum V2PatternContent: Codable {
    case rect(x: Double, y: Double, width: Double, height: Double, rx: Double?, ry: Double?, style: V2PatternNodeStyle)
    case circle(cx: Double, cy: Double, radius: Double, style: V2PatternNodeStyle)
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double, style: V2PatternNodeStyle)
    case line(x1: Double, y1: Double, x2: Double, y2: Double, style: V2PatternNodeStyle)
    case polyline(points: [V2PathPoint], style: V2PatternNodeStyle)
    case polygon(points: [V2PathPoint], style: V2PatternNodeStyle)
    case path(contours: [V2PathContour], fillRule: String?, style: V2PatternNodeStyle)
    case group(transform: V2PaintTransform?, opacity: Double?, children: [V2PatternContent])

    private enum CodingKeys: String, CodingKey {
        case type, x, y, width, height, rx, ry, cx, cy, radius, x1, y1, x2, y2, points, contours, fillRule, transform, opacity, children
        case fill, fillOpacity, stroke, strokeWidth, strokeOpacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        func style() throws -> V2PatternNodeStyle {
            V2PatternNodeStyle(
                fill: try c.decodeIfPresent(V2Paint.self, forKey: .fill),
                fillOpacity: try c.decodeIfPresent(Double.self, forKey: .fillOpacity),
                stroke: try c.decodeIfPresent(V2Paint.self, forKey: .stroke),
                strokeWidth: try c.decodeIfPresent(V2SvgLength.self, forKey: .strokeWidth),
                strokeOpacity: try c.decodeIfPresent(Double.self, forKey: .strokeOpacity)
            )
        }
        switch type {
        case "rect":
            self = .rect(
                x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
                width: try c.decode(Double.self, forKey: .width), height: try c.decode(Double.self, forKey: .height),
                rx: try c.decodeIfPresent(Double.self, forKey: .rx), ry: try c.decodeIfPresent(Double.self, forKey: .ry),
                style: try style()
            )
        case "circle":
            self = .circle(cx: try c.decode(Double.self, forKey: .cx), cy: try c.decode(Double.self, forKey: .cy), radius: try c.decode(Double.self, forKey: .radius), style: try style())
        case "ellipse":
            self = .ellipse(
                cx: try c.decode(Double.self, forKey: .cx), cy: try c.decode(Double.self, forKey: .cy),
                rx: try c.decode(Double.self, forKey: .rx), ry: try c.decode(Double.self, forKey: .ry), style: try style()
            )
        case "line":
            self = .line(
                x1: try c.decode(Double.self, forKey: .x1), y1: try c.decode(Double.self, forKey: .y1),
                x2: try c.decode(Double.self, forKey: .x2), y2: try c.decode(Double.self, forKey: .y2), style: try style()
            )
        case "polyline":
            self = .polyline(points: try c.decode([V2PathPoint].self, forKey: .points), style: try style())
        case "polygon":
            self = .polygon(points: try c.decode([V2PathPoint].self, forKey: .points), style: try style())
        case "path":
            self = .path(contours: try c.decode([V2PathContour].self, forKey: .contours), fillRule: try c.decodeIfPresent(String.self, forKey: .fillRule), style: try style())
        case "group":
            self = .group(
                transform: try c.decodeIfPresent(V2PaintTransform.self, forKey: .transform),
                opacity: try c.decodeIfPresent(Double.self, forKey: .opacity),
                children: try c.decode([V2PatternContent].self, forKey: .children)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown pattern content type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func encodeStyle(_ style: V2PatternNodeStyle) throws {
            try c.encodeIfPresent(style.fill, forKey: .fill)
            try c.encodeIfPresent(style.fillOpacity, forKey: .fillOpacity)
            try c.encodeIfPresent(style.stroke, forKey: .stroke)
            try c.encodeIfPresent(style.strokeWidth, forKey: .strokeWidth)
            try c.encodeIfPresent(style.strokeOpacity, forKey: .strokeOpacity)
        }
        switch self {
        case .rect(let x, let y, let width, let height, let rx, let ry, let style):
            try c.encode("rect", forKey: .type)
            try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
            try c.encode(width, forKey: .width); try c.encode(height, forKey: .height)
            try c.encodeIfPresent(rx, forKey: .rx); try c.encodeIfPresent(ry, forKey: .ry)
            try encodeStyle(style)
        case .circle(let cx, let cy, let radius, let style):
            try c.encode("circle", forKey: .type)
            try c.encode(cx, forKey: .cx); try c.encode(cy, forKey: .cy); try c.encode(radius, forKey: .radius)
            try encodeStyle(style)
        case .ellipse(let cx, let cy, let rx, let ry, let style):
            try c.encode("ellipse", forKey: .type)
            try c.encode(cx, forKey: .cx); try c.encode(cy, forKey: .cy)
            try c.encode(rx, forKey: .rx); try c.encode(ry, forKey: .ry)
            try encodeStyle(style)
        case .line(let x1, let y1, let x2, let y2, let style):
            try c.encode("line", forKey: .type)
            try c.encode(x1, forKey: .x1); try c.encode(y1, forKey: .y1)
            try c.encode(x2, forKey: .x2); try c.encode(y2, forKey: .y2)
            try encodeStyle(style)
        case .polyline(let points, let style):
            try c.encode("polyline", forKey: .type)
            try c.encode(points, forKey: .points)
            try encodeStyle(style)
        case .polygon(let points, let style):
            try c.encode("polygon", forKey: .type)
            try c.encode(points, forKey: .points)
            try encodeStyle(style)
        case .path(let contours, let fillRule, let style):
            try c.encode("path", forKey: .type)
            try c.encode(contours, forKey: .contours)
            try c.encodeIfPresent(fillRule, forKey: .fillRule)
            try encodeStyle(style)
        case .group(let transform, let opacity, let children):
            try c.encode("group", forKey: .type)
            try c.encodeIfPresent(transform, forKey: .transform)
            try c.encodeIfPresent(opacity, forKey: .opacity)
            try c.encode(children, forKey: .children)
        }
    }
}

struct V2PatternFill: Codable {
    var x: V2SvgLength?
    var y: V2SvgLength?
    var width: V2SvgLength?
    var height: V2SvgLength?
    var patternUnits: V2GradientUnits?
    var patternContentUnits: V2GradientUnits?
    var patternTransform: V2PaintTransform?
    var href: String?
    var viewBox: V2PatternViewBox?
    var content: [V2PatternContent]?
}

struct V2PaintReference: Codable {
    var id: String
    var fallback: V2Color?
}

enum V2PaintKeyword: String, Codable {
    case none, currentColor
    case contextFill = "context-fill"
    case contextStroke = "context-stroke"
}

/// Mirrors `V2PaintSchema`: a bare color string, a keyword, or a structured
/// paint server (solid/gradient/pattern/reference). Also reused for
/// `V2PaintServerDefinition.paint` (which the real schema restricts to
/// solid/gradient/pattern, no reference/color/keyword) — one Swift type
/// covers both since nothing here re-validates which subset is legal where.
indirect enum V2Paint: Codable {
    case color(V2Color)
    case keyword(V2PaintKeyword)
    case none
    case solid(color: V2Color, opacity: Double?)
    case linearGradient(V2LinearGradient)
    case radialGradient(V2RadialGradient)
    case conicGradient(V2ConicGradient)
    case pattern(V2PatternFill)
    case reference(V2PaintReference)

    private enum CodingKeys: String, CodingKey {
        case type, color, opacity, id, fallback
        case x1, y1, x2, y2, cx, cy, radius, radiusX, radiusY, fx, fy, fr, from
        case stops, spreadMethod, gradientUnits, gradientTransform, href
        case x, y, width, height, patternUnits, patternContentUnits, patternTransform, viewBox, content
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
            if let keyword = V2PaintKeyword(rawValue: string) {
                self = .keyword(keyword)
            } else {
                self = .color(string)
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        func common() throws -> V2GradientCommon {
            V2GradientCommon(
                stops: try c.decodeIfPresent([V2GradientStop].self, forKey: .stops),
                spreadMethod: try c.decodeIfPresent(V2GradientSpreadMethod.self, forKey: .spreadMethod),
                gradientUnits: try c.decodeIfPresent(V2GradientUnits.self, forKey: .gradientUnits),
                gradientTransform: try c.decodeIfPresent(V2PaintTransform.self, forKey: .gradientTransform),
                href: try c.decodeIfPresent(String.self, forKey: .href)
            )
        }
        switch type {
        case "none":
            self = .none
        case "solid":
            self = .solid(color: try c.decode(V2Color.self, forKey: .color), opacity: try c.decodeIfPresent(Double.self, forKey: .opacity))
        case "linear-gradient":
            self = .linearGradient(V2LinearGradient(
                x1: try c.decodeIfPresent(V2SvgLength.self, forKey: .x1), y1: try c.decodeIfPresent(V2SvgLength.self, forKey: .y1),
                x2: try c.decodeIfPresent(V2SvgLength.self, forKey: .x2), y2: try c.decodeIfPresent(V2SvgLength.self, forKey: .y2),
                common: try common()
            ))
        case "radial-gradient":
            self = .radialGradient(V2RadialGradient(
                cx: try c.decodeIfPresent(V2SvgLength.self, forKey: .cx), cy: try c.decodeIfPresent(V2SvgLength.self, forKey: .cy),
                radius: try c.decodeIfPresent(V2SvgLength.self, forKey: .radius),
                radiusX: try c.decodeIfPresent(V2SvgLength.self, forKey: .radiusX), radiusY: try c.decodeIfPresent(V2SvgLength.self, forKey: .radiusY),
                fx: try c.decodeIfPresent(V2SvgLength.self, forKey: .fx), fy: try c.decodeIfPresent(V2SvgLength.self, forKey: .fy),
                fr: try c.decodeIfPresent(V2SvgLength.self, forKey: .fr), common: try common()
            ))
        case "conic-gradient":
            self = .conicGradient(V2ConicGradient(
                from: try c.decodeIfPresent(Double.self, forKey: .from),
                cx: try c.decodeIfPresent(Double.self, forKey: .cx), cy: try c.decodeIfPresent(Double.self, forKey: .cy),
                common: try common()
            ))
        case "pattern":
            self = .pattern(V2PatternFill(
                x: try c.decodeIfPresent(V2SvgLength.self, forKey: .x), y: try c.decodeIfPresent(V2SvgLength.self, forKey: .y),
                width: try c.decodeIfPresent(V2SvgLength.self, forKey: .width), height: try c.decodeIfPresent(V2SvgLength.self, forKey: .height),
                patternUnits: try c.decodeIfPresent(V2GradientUnits.self, forKey: .patternUnits),
                patternContentUnits: try c.decodeIfPresent(V2GradientUnits.self, forKey: .patternContentUnits),
                patternTransform: try c.decodeIfPresent(V2PaintTransform.self, forKey: .patternTransform),
                href: try c.decodeIfPresent(String.self, forKey: .href),
                viewBox: try c.decodeIfPresent(V2PatternViewBox.self, forKey: .viewBox),
                content: try c.decodeIfPresent([V2PatternContent].self, forKey: .content)
            ))
        case "reference":
            self = .reference(V2PaintReference(id: try c.decode(String.self, forKey: .id), fallback: try c.decodeIfPresent(V2Color.self, forKey: .fallback)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown paint type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .color(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
            return
        case .keyword(let keyword):
            var single = encoder.singleValueContainer()
            try single.encode(keyword.rawValue)
            return
        default:
            break
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        func encodeCommon(_ common: V2GradientCommon) throws {
            try c.encodeIfPresent(common.stops, forKey: .stops)
            try c.encodeIfPresent(common.spreadMethod, forKey: .spreadMethod)
            try c.encodeIfPresent(common.gradientUnits, forKey: .gradientUnits)
            try c.encodeIfPresent(common.gradientTransform, forKey: .gradientTransform)
            try c.encodeIfPresent(common.href, forKey: .href)
        }
        switch self {
        case .none:
            try c.encode("none", forKey: .type)
        case .solid(let color, let opacity):
            try c.encode("solid", forKey: .type)
            try c.encode(color, forKey: .color)
            try c.encodeIfPresent(opacity, forKey: .opacity)
        case .linearGradient(let gradient):
            try c.encode("linear-gradient", forKey: .type)
            try c.encodeIfPresent(gradient.x1, forKey: .x1); try c.encodeIfPresent(gradient.y1, forKey: .y1)
            try c.encodeIfPresent(gradient.x2, forKey: .x2); try c.encodeIfPresent(gradient.y2, forKey: .y2)
            try encodeCommon(gradient.common)
        case .radialGradient(let gradient):
            try c.encode("radial-gradient", forKey: .type)
            try c.encodeIfPresent(gradient.cx, forKey: .cx); try c.encodeIfPresent(gradient.cy, forKey: .cy)
            try c.encodeIfPresent(gradient.radius, forKey: .radius)
            try c.encodeIfPresent(gradient.radiusX, forKey: .radiusX); try c.encodeIfPresent(gradient.radiusY, forKey: .radiusY)
            try c.encodeIfPresent(gradient.fx, forKey: .fx); try c.encodeIfPresent(gradient.fy, forKey: .fy)
            try c.encodeIfPresent(gradient.fr, forKey: .fr)
            try encodeCommon(gradient.common)
        case .conicGradient(let gradient):
            try c.encode("conic-gradient", forKey: .type)
            try c.encodeIfPresent(gradient.from, forKey: .from)
            try c.encodeIfPresent(gradient.cx, forKey: .cx); try c.encodeIfPresent(gradient.cy, forKey: .cy)
            try encodeCommon(gradient.common)
        case .pattern(let pattern):
            try c.encode("pattern", forKey: .type)
            try c.encodeIfPresent(pattern.x, forKey: .x); try c.encodeIfPresent(pattern.y, forKey: .y)
            try c.encodeIfPresent(pattern.width, forKey: .width); try c.encodeIfPresent(pattern.height, forKey: .height)
            try c.encodeIfPresent(pattern.patternUnits, forKey: .patternUnits)
            try c.encodeIfPresent(pattern.patternContentUnits, forKey: .patternContentUnits)
            try c.encodeIfPresent(pattern.patternTransform, forKey: .patternTransform)
            try c.encodeIfPresent(pattern.href, forKey: .href)
            try c.encodeIfPresent(pattern.viewBox, forKey: .viewBox)
            try c.encodeIfPresent(pattern.content, forKey: .content)
        case .reference(let reference):
            try c.encode("reference", forKey: .type)
            try c.encode(reference.id, forKey: .id)
            try c.encodeIfPresent(reference.fallback, forKey: .fallback)
        case .color, .keyword:
            break // handled above
        }
    }

    /// Flattens a bare color or solid paint to a hex string for the Runtime
    /// renderer, which only draws plain colors — gradients/patterns/
    /// references/keywords are a known, separate gap from protocol shape
    /// parity (see `V2Layer.fillColor`).
    var flatColor: V2Color? {
        switch self {
        case .color(let value): return value
        case .solid(let color, _): return color
        default: return nil
        }
    }

    /// `"none"` has 2 wire forms in the real schema — a bare keyword string
    /// or a structured `{type:"none"}` object — both kept as-is (see
    /// CLAUDE.md's "no SVG-alias fields" note: this isn't an alias, it's a
    /// real dual representation in the TS schema itself). This property lets
    /// callers check "is this paint absent" without handling both cases.
    var isNone: Bool {
        switch self {
        case .none, .keyword(.none): return true
        default: return false
        }
    }
}

struct V2PaintServerDefinition: Codable {
    var id: String
    var paint: V2Paint
    var tracks: [V2Track]?
}
