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
    /// Swift-only addition (Mask tool, 2026-10-18; the TS package has none yet), common to every mask source. Standard deviation of a Gaussian blur
    /// applied to the finished matte, in the mask's user-space units (px of the layer's own box with the default `maskContentUnits`); absent / 0 = a hard edge.
    var feather: Double?
    /// Swift-only addition, same as `feather`: true shows what the matte hides and hides what it shows (the matte's alpha becomes `1 - alpha`). Absent = false.
    var invert: Bool?
    /// Swift-only addition (Remove BG, 2026-10-18; the TS package has none yet): a third source beside `children` and `image` - exactly one of the three. The matte is
    /// computed at render time by the platform's own segmentation (Vision on Apple) from the layer's picture; nothing of it is stored. The matte lives in **the picture's
    /// space** (not the layer box's), so a renderer applies it to the picture before crop / rotation. With this source `x/y/width/height`, `maskUnits`,
    /// `maskContentUnits` and `transform` mean nothing and should be absent; `maskType` is `alpha`; `feather` is read against the layer box and converted to the picture
    /// proportionally. An unknown `mode` or a missing `at` for `point` makes the mask a no-op (the picture shows whole).
    var segmentation: V2MaskSegmentation?
}

/// How a segmentation mask picks its subject. `mode`: `auto` (default) keeps what the platform finds most salient, `point` keeps the subject under `at`, `people` keeps every
/// person. `at` is a point in the picture as fractions 0...1 (origin top-left, the same space as `V2Crop`). `atMs` (video only) is the source time of the frame `at` was picked on.
struct V2MaskSegmentation: Codable {
    let type: String
    var mode: String?
    var at: V2Vec2?
    var atMs: Double?

    init(mode: String? = nil, at: V2Vec2? = nil, atMs: Double? = nil) {
        type = "segmentation"
        self.mode = mode
        self.at = at
        self.atMs = atMs
    }
}

/// One CSS `mask-image` layer. `composite` mirrors a Zod `.default("add")`
/// field — optional here, caller applies the fallback.
struct V2MaskLayer: Codable {
    var maskIds: [String]
    var mode: String?
    var composite: String?
}
