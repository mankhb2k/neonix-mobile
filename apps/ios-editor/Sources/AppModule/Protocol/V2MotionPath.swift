import Foundation

// Port of packages/motion-protocol/src/v2/motion-path.ts.

struct V2OffsetPathSampling: Codable {
    var method: String = "adaptive-flatness"
    var tolerance: Double
    var maxSegments: Int
}

/// `coordinateSpace`/`referenceBox` mirror Zod `.default(...)` fields —
/// optional here, caller applies `?? "parent-local"`/`?? "border-box"`.
struct V2OffsetPath: Codable {
    var type: String = "path"
    var contours: [V2PathContour]
    var coordinateSpace: String?
    var referenceBox: String?
    var pathLength: Double?
    var sampling: V2OffsetPathSampling?
}

struct V2OffsetRotate: Codable {
    var mode: String // "auto" | "auto-reverse" | "fixed"
    var angle: Double
}

struct V2OffsetAnchor: Codable {
    var x: Double
    var y: Double
}

/// `offsetDistance`/`offsetRotate`/`offsetAnchor` all mirror Zod
/// `.default(...)` fields — optional here, caller applies the documented
/// fallback (`0`, `{mode:"auto",angle:0}`, `{x:0,y:0}`).
struct V2MotionPath: Codable {
    var offsetPath: V2OffsetPath
    var offsetDistance: Double?
    var offsetRotate: V2OffsetRotate?
    var offsetAnchor: V2OffsetAnchor?
}
