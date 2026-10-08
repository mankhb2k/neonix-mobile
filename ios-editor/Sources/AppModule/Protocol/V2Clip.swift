import Foundation

// Port of packages/motion-protocol/src/v2/clip.ts.

/// SVG's six-value affine matrix: `x'=a*x+c*y+e, y'=b*x+d*y+f`.
typealias V2SvgMatrix = (Double, Double, Double, Double, Double, Double)

func decodeTuple6(_ array: [Double]) -> V2SvgMatrix { (array[0], array[1], array[2], array[3], array[4], array[5]) }

/// The 2D-only ordered-operation union used by clip-path/mask/pattern
/// definitions — SVG's own `transform` list (`translate`/`scale`/`rotate`/
/// `skewX`/`skewY`/`matrix`), no 3D extensions. Distinct from the layer
/// `V2Transform` (fully explicit component form, see `V2Types.swift`): these
/// definition-tree contexts are inherently 2D SVG coordinate systems, so an
/// ordered list of SVG ops is already the most atomic representation here —
/// mirrors `V2SvgTransformOperationSchema` exactly (as opposed to the layer's
/// now-removed `V2TransformOperationSchema`, which added 3D extensions).
enum V2SvgTransformOperation: Codable {
    case translate(x: Double, y: Double)
    case scale(x: Double, y: Double)
    case rotate(angle: Double, center: V2Vec2?)
    case skewX(angle: Double)
    case skewY(angle: Double)
    case matrix(values: V2SvgMatrix)

    private enum CodingKeys: String, CodingKey {
        case type, x, y, angle, center, values
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "translate":
            self = .translate(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
        case "scale":
            self = .scale(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
        case "rotate":
            self = .rotate(angle: try c.decode(Double.self, forKey: .angle), center: try c.decodeIfPresent(V2Vec2.self, forKey: .center))
        case "skewX":
            self = .skewX(angle: try c.decode(Double.self, forKey: .angle))
        case "skewY":
            self = .skewY(angle: try c.decode(Double.self, forKey: .angle))
        case "matrix":
            self = .matrix(values: decodeTuple6(try c.decode([Double].self, forKey: .values)))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown SVG transform operation: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .translate(let x, let y):
            try c.encode("translate", forKey: .type); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        case .scale(let x, let y):
            try c.encode("scale", forKey: .type); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        case .rotate(let angle, let center):
            try c.encode("rotate", forKey: .type); try c.encode(angle, forKey: .angle); try c.encodeIfPresent(center, forKey: .center)
        case .skewX(let angle):
            try c.encode("skewX", forKey: .type); try c.encode(angle, forKey: .angle)
        case .skewY(let angle):
            try c.encode("skewY", forKey: .type); try c.encode(angle, forKey: .angle)
        case .matrix(let values):
            try c.encode("matrix", forKey: .type)
            try c.encode([values.0, values.1, values.2, values.3, values.4, values.5], forKey: .values)
        }
    }
}

/// Shared style/transform/clipPath fields every SVG definition node carries.
struct V2SvgDefinitionNodeCommon: Codable {
    var transform: [V2SvgTransformOperation]?
    var clipPath: String?
    var fill: V2Paint?
    var fillOpacity: Double?
    var stroke: V2Paint?
    var strokeWidth: Double?
    var strokeOpacity: Double?
}

/// Recursive SVG definition node tree, shared by clipPath and mask children.
/// See `V2PatternContent` for why the recursive `[V2SvgDefinitionNode]` in
/// `.group` doesn't require `indirect` size-wise, but this is marked
/// `indirect` anyway for the same defensive-simplicity reason.
indirect enum V2SvgDefinitionNode: Codable {
    case path(contours: [V2PathContour], fillRule: String?, common: V2SvgDefinitionNodeCommon)
    case rect(x: Double, y: Double, width: Double, height: Double, rx: Double?, ry: Double?, common: V2SvgDefinitionNodeCommon)
    case circle(cx: Double, cy: Double, r: Double, common: V2SvgDefinitionNodeCommon)
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double, common: V2SvgDefinitionNodeCommon)
    case line(x1: Double, y1: Double, x2: Double, y2: Double, common: V2SvgDefinitionNodeCommon)
    case polyline(points: [V2PathPoint], common: V2SvgDefinitionNodeCommon)
    case polygon(points: [V2PathPoint], common: V2SvgDefinitionNodeCommon)
    case group(children: [V2SvgDefinitionNode], opacity: Double?, common: V2SvgDefinitionNodeCommon)

    private enum CodingKeys: String, CodingKey {
        case type, contours, fillRule, x, y, width, height, rx, ry, cx, cy, r, x1, y1, x2, y2, points, children, opacity
        case transform, clipPath, fill, fillOpacity, stroke, strokeWidth, strokeOpacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let common = V2SvgDefinitionNodeCommon(
            transform: try c.decodeIfPresent([V2SvgTransformOperation].self, forKey: .transform),
            clipPath: try c.decodeIfPresent(String.self, forKey: .clipPath),
            fill: try c.decodeIfPresent(V2Paint.self, forKey: .fill),
            fillOpacity: try c.decodeIfPresent(Double.self, forKey: .fillOpacity),
            stroke: try c.decodeIfPresent(V2Paint.self, forKey: .stroke),
            strokeWidth: try c.decodeIfPresent(Double.self, forKey: .strokeWidth),
            strokeOpacity: try c.decodeIfPresent(Double.self, forKey: .strokeOpacity)
        )
        switch try c.decode(String.self, forKey: .type) {
        case "path":
            self = .path(contours: try c.decode([V2PathContour].self, forKey: .contours), fillRule: try c.decodeIfPresent(String.self, forKey: .fillRule), common: common)
        case "rect":
            self = .rect(
                x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
                width: try c.decode(Double.self, forKey: .width), height: try c.decode(Double.self, forKey: .height),
                rx: try c.decodeIfPresent(Double.self, forKey: .rx), ry: try c.decodeIfPresent(Double.self, forKey: .ry), common: common
            )
        case "circle":
            self = .circle(cx: try c.decode(Double.self, forKey: .cx), cy: try c.decode(Double.self, forKey: .cy), r: try c.decode(Double.self, forKey: .r), common: common)
        case "ellipse":
            self = .ellipse(
                cx: try c.decode(Double.self, forKey: .cx), cy: try c.decode(Double.self, forKey: .cy),
                rx: try c.decode(Double.self, forKey: .rx), ry: try c.decode(Double.self, forKey: .ry), common: common
            )
        case "line":
            self = .line(
                x1: try c.decode(Double.self, forKey: .x1), y1: try c.decode(Double.self, forKey: .y1),
                x2: try c.decode(Double.self, forKey: .x2), y2: try c.decode(Double.self, forKey: .y2), common: common
            )
        case "polyline":
            self = .polyline(points: try c.decode([V2PathPoint].self, forKey: .points), common: common)
        case "polygon":
            self = .polygon(points: try c.decode([V2PathPoint].self, forKey: .points), common: common)
        case "group":
            self = .group(children: try c.decode([V2SvgDefinitionNode].self, forKey: .children), opacity: try c.decodeIfPresent(Double.self, forKey: .opacity), common: common)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown SVG definition node: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func encodeCommon(_ common: V2SvgDefinitionNodeCommon) throws {
            try c.encodeIfPresent(common.transform, forKey: .transform)
            try c.encodeIfPresent(common.clipPath, forKey: .clipPath)
            try c.encodeIfPresent(common.fill, forKey: .fill)
            try c.encodeIfPresent(common.fillOpacity, forKey: .fillOpacity)
            try c.encodeIfPresent(common.stroke, forKey: .stroke)
            try c.encodeIfPresent(common.strokeWidth, forKey: .strokeWidth)
            try c.encodeIfPresent(common.strokeOpacity, forKey: .strokeOpacity)
        }
        switch self {
        case .path(let contours, let fillRule, let common):
            try c.encode("path", forKey: .type); try c.encode(contours, forKey: .contours); try c.encodeIfPresent(fillRule, forKey: .fillRule); try encodeCommon(common)
        case .rect(let x, let y, let width, let height, let rx, let ry, let common):
            try c.encode("rect", forKey: .type)
            try c.encode(x, forKey: .x); try c.encode(y, forKey: .y); try c.encode(width, forKey: .width); try c.encode(height, forKey: .height)
            try c.encodeIfPresent(rx, forKey: .rx); try c.encodeIfPresent(ry, forKey: .ry); try encodeCommon(common)
        case .circle(let cx, let cy, let r, let common):
            try c.encode("circle", forKey: .type); try c.encode(cx, forKey: .cx); try c.encode(cy, forKey: .cy); try c.encode(r, forKey: .r); try encodeCommon(common)
        case .ellipse(let cx, let cy, let rx, let ry, let common):
            try c.encode("ellipse", forKey: .type)
            try c.encode(cx, forKey: .cx); try c.encode(cy, forKey: .cy); try c.encode(rx, forKey: .rx); try c.encode(ry, forKey: .ry); try encodeCommon(common)
        case .line(let x1, let y1, let x2, let y2, let common):
            try c.encode("line", forKey: .type)
            try c.encode(x1, forKey: .x1); try c.encode(y1, forKey: .y1); try c.encode(x2, forKey: .x2); try c.encode(y2, forKey: .y2); try encodeCommon(common)
        case .polyline(let points, let common):
            try c.encode("polyline", forKey: .type); try c.encode(points, forKey: .points); try encodeCommon(common)
        case .polygon(let points, let common):
            try c.encode("polygon", forKey: .type); try c.encode(points, forKey: .points); try encodeCommon(common)
        case .group(let children, let opacity, let common):
            try c.encode("group", forKey: .type); try c.encode(children, forKey: .children); try c.encodeIfPresent(opacity, forKey: .opacity); try encodeCommon(common)
        }
    }
}

/// `clipPathUnits` mirrors a Zod `.default("userSpaceOnUse")` field —
/// optional here, caller applies the fallback.
struct V2ClipPath: Codable {
    var id: String
    var clipPathUnits: String?
    var transform: [V2SvgTransformOperation]?
    var children: [V2SvgDefinitionNode]
}
