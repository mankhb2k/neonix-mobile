import Foundation

// Port of packages/motion-protocol/src/v2/mask.ts.

struct V2MaskImagePreserveAspectRatio: Codable {
    var `defer`: Bool?
    var align: String?
    var meetOrSlice: String?
}

/// `fit` mirrors a Zod `.default("fill")` field — optional here, caller
/// applies the fallback.
struct V2MaskImageSource: Codable {
    var assetId: String
    var x: Double, y: Double, width: Double, height: Double
    var opacity: Double?
    var fit: String?
    var preserveAspectRatio: V2MaskImagePreserveAspectRatio?
}

/// `maskUnits`/`maskContentUnits`/`maskType` mirror Zod `.default(...)`
/// fields — optional here, caller applies the documented fallback.
struct V2Mask: Codable {
    var id: String
    var maskUnits: String?
    var maskContentUnits: String?
    var maskType: String?
    var x: V2SvgLength?
    var y: V2SvgLength?
    var width: V2SvgLength?
    var height: V2SvgLength?
    var transform: [V2SvgTransformOperation]?
    var children: [V2SvgDefinitionNode]?
    var image: V2MaskImageSource?
    var tracks: [V2Track]?
}

/// One CSS `mask-image` layer. `composite` mirrors a Zod `.default("add")`
/// field — optional here, caller applies the fallback.
struct V2MaskLayer: Codable {
    var maskIds: [String]
    var mode: String?
    var composite: String?
}
