import Foundation

// Port of packages/motion-protocol/src/v2/common.ts. Structural shape only —
// Zod's length/range refinements (e.g. `.positive()`, `.max(200)`) are not
// re-validated here; see ARCHITECTURE.md's "valid by construction" strategy
// for why Swift doesn't re-implement the validator.

/// A hex color string, `#RRGGBB` or `#RRGGBBAA`. Kept as a plain `String`
/// (not a branded type) since nothing here re-validates the pattern.
typealias V2Color = String

enum V2SvgLengthUnit: String, Codable {
    case number, px, pt, pc, mm, cm, in_ = "in", em, percent
}

/// Mirrors `V2SvgLengthSchema` (and the identically-shaped
/// `V2NonNegativeSvgLengthSchema`/`V2PositiveSvgLengthSchema` — the
/// constraint difference is validation-only, so one Swift type covers all
/// three): a bare number, or `{ value, unit }`.
enum V2SvgLength: Codable {
    case number(Double)
    case value(Double, unit: V2SvgLengthUnit)

    private enum CodingKeys: String, CodingKey {
        case value, unit
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let number = try? single.decode(Double.self) {
            self = .number(number)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .value(try container.decode(Double.self, forKey: .value), unit: try container.decode(V2SvgLengthUnit.self, forKey: .unit))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .number(let number):
            var single = encoder.singleValueContainer()
            try single.encode(number)
        case .value(let value, let unit):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encode(unit, forKey: .unit)
        }
    }

    /// Convenience for the Runtime renderer, which treats every unit as
    /// already being in composition/user-space units (unit conversion is a
    /// known, separate gap from protocol shape parity).
    var numericValue: Double {
        switch self {
        case .number(let n): return n
        case .value(let v, _): return v
        }
    }
}

enum V2PaintOrderItem: String, Codable {
    case fill, stroke, markers
}

typealias V2PaintOrder = [V2PaintOrderItem]

enum V2VectorEffect: String, Codable {
    case none, nonScalingStroke = "non-scaling-stroke"
}
