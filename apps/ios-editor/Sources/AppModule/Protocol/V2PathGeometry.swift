import Foundation

// Port of packages/motion-protocol/src/v2/path-geometry.ts.

struct V2PathPoint: Codable {
    var x: Double
    var y: Double
}

enum V2PathSegment: Codable {
    case line(to: V2PathPoint)
    case quadratic(control: V2PathPoint, to: V2PathPoint)
    case cubic(control1: V2PathPoint, control2: V2PathPoint, to: V2PathPoint)
    case arc(radii: V2PathPoint, rotation: Double, largeArc: Bool, sweep: Bool, to: V2PathPoint)

    private enum CodingKeys: String, CodingKey {
        case kind, to, control, control1, control2, radii, rotation, largeArc, sweep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let to = try container.decode(V2PathPoint.self, forKey: .to)
        switch kind {
        case "line":
            self = .line(to: to)
        case "quadratic":
            self = .quadratic(control: try container.decode(V2PathPoint.self, forKey: .control), to: to)
        case "cubic":
            self = .cubic(
                control1: try container.decode(V2PathPoint.self, forKey: .control1),
                control2: try container.decode(V2PathPoint.self, forKey: .control2),
                to: to
            )
        case "arc":
            self = .arc(
                radii: try container.decode(V2PathPoint.self, forKey: .radii),
                rotation: try container.decode(Double.self, forKey: .rotation),
                largeArc: try container.decode(Bool.self, forKey: .largeArc),
                sweep: try container.decode(Bool.self, forKey: .sweep),
                to: to
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown path segment kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .line(let to):
            try container.encode("line", forKey: .kind)
            try container.encode(to, forKey: .to)
        case .quadratic(let control, let to):
            try container.encode("quadratic", forKey: .kind)
            try container.encode(control, forKey: .control)
            try container.encode(to, forKey: .to)
        case .cubic(let control1, let control2, let to):
            try container.encode("cubic", forKey: .kind)
            try container.encode(control1, forKey: .control1)
            try container.encode(control2, forKey: .control2)
            try container.encode(to, forKey: .to)
        case .arc(let radii, let rotation, let largeArc, let sweep, let to):
            try container.encode("arc", forKey: .kind)
            try container.encode(radii, forKey: .radii)
            try container.encode(rotation, forKey: .rotation)
            try container.encode(largeArc, forKey: .largeArc)
            try container.encode(sweep, forKey: .sweep)
            try container.encode(to, forKey: .to)
        }
    }
}

struct V2PathContour: Codable {
    var id: String
    var start: V2PathPoint
    var segments: [V2PathSegment]
    var closed: Bool
}
