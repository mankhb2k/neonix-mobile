import Foundation

// Port of packages/motion-protocol/src/v2/render3d.ts.

enum V2TransformStyle: String, Codable {
    case flat
    case preserve3d = "preserve-3d"
}

enum V2BackfaceVisibility: String, Codable {
    case visible, hidden
}

struct V2PerspectiveContext: Codable {
    var distance: Double
    var origin: V2Vec2
}

/// `transformStyle` mirrors a Zod `.default("flat")` field — optional here,
/// caller applies `?? .flat`.
struct V2Render3D: Codable {
    var transformStyle: V2TransformStyle?
    var perspective: V2PerspectiveContext?
}
