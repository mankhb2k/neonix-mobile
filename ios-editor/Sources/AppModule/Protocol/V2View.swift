import Foundation

// Port of packages/motion-protocol/src/v2/view.ts. The composition camera —
// distinct from a layer's own `V2Transform`.

enum V2Projection: Codable {
    case orthographic(zoom: Double, near: Double, far: Double)
    case perspective(fov: Double, near: Double, far: Double)

    private enum CodingKeys: String, CodingKey { case kind, zoom, near, far, fov }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "orthographic":
            self = .orthographic(zoom: try c.decode(Double.self, forKey: .zoom), near: try c.decode(Double.self, forKey: .near), far: try c.decode(Double.self, forKey: .far))
        case "perspective":
            self = .perspective(fov: try c.decode(Double.self, forKey: .fov), near: try c.decode(Double.self, forKey: .near), far: try c.decode(Double.self, forKey: .far))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown projection: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .orthographic(let zoom, let near, let far):
            try c.encode("orthographic", forKey: .kind); try c.encode(zoom, forKey: .zoom); try c.encode(near, forKey: .near); try c.encode(far, forKey: .far)
        case .perspective(let fov, let near, let far):
            try c.encode("perspective", forKey: .kind); try c.encode(fov, forKey: .fov); try c.encode(near, forKey: .near); try c.encode(far, forKey: .far)
        }
    }
}

struct V2ViewTransform: Codable {
    var translate: V2Vec3
    var rotate: V2Vec3
}

struct V2View: Codable {
    var projection: V2Projection
    var transform: V2ViewTransform
}
