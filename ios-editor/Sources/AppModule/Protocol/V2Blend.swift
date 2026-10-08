import Foundation

// Port of packages/motion-protocol/src/v2/blend.ts.

enum V2BlendMode: String, Codable {
    case normal, darken, multiply
    case colorBurn = "color-burn"
    case lighten, screen
    case colorDodge = "color-dodge"
    case overlay
    case softLight = "soft-light"
    case hardLight = "hard-light"
    case difference, exclusion, hue, saturation, color, luminosity
}

enum V2IsolationMode: String, Codable {
    case auto, isolate
}

/// `blendMode` mirrors a Zod `.default("normal")` field: optional here rather
/// than baking the fallback into decode (the rule used throughout this port
/// for every defaulted field — see the plan this was built from). Callers
/// apply `?? .normal` themselves.
struct V2Composite: Codable {
    var blendMode: V2BlendMode?
    var isolation: V2IsolationMode?
}
