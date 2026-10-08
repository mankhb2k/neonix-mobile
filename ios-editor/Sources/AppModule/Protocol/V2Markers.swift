import Foundation

// Port of packages/motion-protocol/src/v2/markers.ts.

/// `"auto"` | `"auto-start-reverse"` | a finite angle.
enum V2MarkerOrient: Codable {
    case auto
    case autoStartReverse
    case angle(Double)

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            switch string {
            case "auto": self = .auto
            case "auto-start-reverse": self = .autoStartReverse
            default: throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unknown marker orient: \(string)")
            }
        } else {
            self = .angle(try single.decode(Double.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .auto: try single.encode("auto")
        case .autoStartReverse: try single.encode("auto-start-reverse")
        case .angle(let value): try single.encode(value)
        }
    }
}

struct V2MarkerViewBox: Codable {
    var x: Double, y: Double, width: Double, height: Double
}

struct V2MarkerContent: Codable {
    var contours: [V2PathContour]
    var fill: V2Paint?
    var fillOpacity: Double?
    var stroke: V2Paint?
    var strokeWidth: Double?
    var strokeOpacity: Double?
    var paintOrder: V2PaintOrder?
}

/// `markerUnits`/`refX`/`refY`/`markerWidth`/`markerHeight`/`orient` all
/// mirror Zod `.default(...)` fields — optional here, caller applies the
/// documented fallback (`"strokeWidth"`, `0`, `0`, `3`, `3`, `0`).
struct V2Marker: Codable {
    var id: String
    var markerUnits: String?
    var refX: Double?
    var refY: Double?
    var markerWidth: Double?
    var markerHeight: Double?
    var orient: V2MarkerOrient?
    var viewBox: V2MarkerViewBox?
    var content: V2MarkerContent
}
