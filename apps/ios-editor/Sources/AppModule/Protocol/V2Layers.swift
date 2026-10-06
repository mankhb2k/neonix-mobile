import Foundation

// Port of packages/motion-protocol/src/v2/layers/{base,group,shape,path,image,video}.ts
// (text.ts is ported separately in V2TextLayer.swift). This is the full
// `V2Layer` replacing the earlier flattened `fill`/`assetId`/`fit` shortcut
// from the first vertical slice — see the plan this was built from for the
// KeyframeSampler/PreviewCanvas/PresetCompiler follow-up fixes this requires.

enum V2Visibility: String, Codable {
    case visible, hidden, collapse
}

/// `array` is the literal `"none"` or a non-empty list of lengths (an odd
/// list repeats, per SVG `stroke-dasharray`).
enum V2StrokeDashArray: Codable {
    case none
    case lengths([V2SvgLength])

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self), s == "none" {
            self = .none; return
        }
        let single = try decoder.singleValueContainer()
        self = .lengths(try single.decode([V2SvgLength].self))
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .none: try single.encode("none")
        case .lengths(let lengths): try single.encode(lengths)
        }
    }
}

struct V2StrokeDash: Codable {
    var array: V2StrokeDashArray
    var offset: V2SvgLength?
}

/// Shared by shape and path layers — identical style field sets in the real
/// schema.
struct V2DrawStyle: Codable {
    var fill: V2Paint?
    var fillOpacity: Double?
    var stroke: V2Paint?
    var strokeWidth: V2SvgLength?
    var strokeOpacity: Double?
    var strokeMiterLimit: Double?
    var strokeJoin: String?
    var strokeCap: String?
    var strokeDash: V2StrokeDash?
    var paintOrder: V2PaintOrder?
    var vectorEffect: V2VectorEffect?
    var markerStart: String?
    var markerMid: String?
    var markerEnd: String?
}

struct V2ShapePoint: Codable {
    var x: Double
    var y: Double
}

/// A true discriminated union, one case per shape kind — each case only ever
/// carries the fields meaningful for that kind, unlike the real TS schema
/// (which uses a flat object + `superRefine` to reject mismatched fields at
/// validation time, not at the type level). This is a genuine improvement
/// over the TS schema's own shape, not just a port — see the atomicity audit
/// this was built from.
enum V2ShapePayload: Codable {
    case rectangle(cornerRadius: V2SvgLength?, rx: V2SvgLength?, ry: V2SvgLength?, pathLength: Double?)
    case circle(pathLength: Double?)
    case ellipse(pathLength: Double?)
    case line(start: V2ShapePoint, end: V2ShapePoint, pathLength: Double?)
    case polyline(points: [V2ShapePoint], pathLength: Double?)
    case polygon(points: [V2ShapePoint], pathLength: Double?)

    private enum CodingKeys: String, CodingKey {
        case shape, pathLength, cornerRadius, rx, ry, start, end, points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pathLength = try c.decodeIfPresent(Double.self, forKey: .pathLength)
        switch try c.decode(String.self, forKey: .shape) {
        case "rectangle":
            self = .rectangle(
                cornerRadius: try c.decodeIfPresent(V2SvgLength.self, forKey: .cornerRadius),
                rx: try c.decodeIfPresent(V2SvgLength.self, forKey: .rx), ry: try c.decodeIfPresent(V2SvgLength.self, forKey: .ry),
                pathLength: pathLength
            )
        case "circle":
            self = .circle(pathLength: pathLength)
        case "ellipse":
            self = .ellipse(pathLength: pathLength)
        case "line":
            self = .line(start: try c.decode(V2ShapePoint.self, forKey: .start), end: try c.decode(V2ShapePoint.self, forKey: .end), pathLength: pathLength)
        case "polyline":
            self = .polyline(points: try c.decode([V2ShapePoint].self, forKey: .points), pathLength: pathLength)
        case "polygon":
            self = .polygon(points: try c.decode([V2ShapePoint].self, forKey: .points), pathLength: pathLength)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .shape, in: c, debugDescription: "Unknown shape: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rectangle(let cornerRadius, let rx, let ry, let pathLength):
            try c.encode("rectangle", forKey: .shape)
            try c.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
            try c.encodeIfPresent(rx, forKey: .rx); try c.encodeIfPresent(ry, forKey: .ry)
            try c.encodeIfPresent(pathLength, forKey: .pathLength)
        case .circle(let pathLength):
            try c.encode("circle", forKey: .shape); try c.encodeIfPresent(pathLength, forKey: .pathLength)
        case .ellipse(let pathLength):
            try c.encode("ellipse", forKey: .shape); try c.encodeIfPresent(pathLength, forKey: .pathLength)
        case .line(let start, let end, let pathLength):
            try c.encode("line", forKey: .shape)
            try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
            try c.encodeIfPresent(pathLength, forKey: .pathLength)
        case .polyline(let points, let pathLength):
            try c.encode("polyline", forKey: .shape); try c.encode(points, forKey: .points); try c.encodeIfPresent(pathLength, forKey: .pathLength)
        case .polygon(let points, let pathLength):
            try c.encode("polygon", forKey: .shape); try c.encode(points, forKey: .points); try c.encodeIfPresent(pathLength, forKey: .pathLength)
        }
    }
}

struct V2PathMorph: Codable {
    var targetContours: [V2PathContour]
    var progress: Double
}

/// `fillRule` mirrors a Zod `.default("nonzero")` field — optional here,
/// caller applies the fallback.
struct V2PathPayload: Codable {
    var contours: [V2PathContour]
    var fillRule: String?
    var pathLength: Double?
    var morph: V2PathMorph?
}

struct V2ImagePreserveAspectRatio: Codable {
    var `defer`: Bool?
    var align: String?
    var meetOrSlice: String?
}

struct V2ImagePayload: Codable {
    var assetId: String
    var fit: String?
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?
    var preserveAspectRatio: V2ImagePreserveAspectRatio?
    var imageRendering: String?
}

struct V2VideoPayload: Codable {
    var assetId: String
    var fit: String?
    var trimStart: Double?
    var trimEnd: Double?
    var playbackRate: Double?
    var audio: V2EmbeddedVideoAudio?
    var framePolicy: String?
}

/// The per-type part of a layer: `type` discriminates which payload (and,
/// for shape/path, which sibling `style` object) applies. Kept as one
/// `indirect enum` rather than 6 separate layer structs so `V2Layer` can
/// hold a single `payload` field matching the real schema's per-type
/// `payload`/`style` nesting.
indirect enum V2LayerPayload: Codable {
    case group(render3d: V2Render3D?)
    case shape(V2ShapePayload, style: V2DrawStyle)
    case path(V2PathPayload, style: V2DrawStyle)
    case image(V2ImagePayload)
    case video(V2VideoPayload)
    case text(V2TextLayerPayload)
}

/// Full port of `V2LayerBaseSchema` plus the per-type extension from
/// `group.ts`/`shape.ts`/`path.ts`/`image.ts`/`video.ts`/`text.ts`.
/// `opacity` mirrors a Zod `.default(1)` field — optional here, caller
/// applies the fallback (this app's own `KeyframeSampler`/`PresetCompiler`
/// already always write an explicit `opacity`, so this only matters for
/// decoding a fixture that omits it).
struct V2Layer: Codable {
    var id: String
    var parentLayerId: String?
    var order: Int
    var frame: V2Frame
    var transform: V2Transform
    var opacity: Double?
    var color: V2Color?
    var enabled: Bool?
    var visibility: V2Visibility?
    var backfaceVisibility: V2BackfaceVisibility?
    var clipPath: String?
    var mask: String?
    var maskLayers: [V2MaskLayer]?
    /// References a `V2Filter` definition in the project root's `filters[]`
    /// — the atomic representation of this layer's own-source effect graph.
    /// Per CLAUDE.md's "Protocol V2 stays atomic" rule, there is no
    /// `effects: [V2Effect]` field here: a named effect (glow, blur, sepia,
    /// ...) is an Editor-tier preset that compiles down into the primitive
    /// chain this filter points to — see `EditorDocument/EffectPresets.swift`.
    var filter: String?
    /// Same idea as `filter`, but for the CSS `backdrop-filter` contract
    /// (samples the already-painted backdrop, not this layer's own source).
    var backdropFilter: String?
    var motion: V2MotionPath?
    var composite: V2Composite?
    var timing: V2Timing
    var tracks: [V2Track]?
    var payload: V2LayerPayload

    /// `type` is derived from `payload`, not stored separately, so the two
    /// can never disagree (unlike the real schema, which stores `type` as
    /// its own literal field alongside `payload` — see `encode`/`init` below
    /// for where this app bridges that difference).
    var type: String {
        switch payload {
        case .group: return "group"
        case .shape: return "shape"
        case .path: return "path"
        case .image: return "image"
        case .video: return "video"
        case .text: return "text"
        }
    }

    /// Convenience accessors for the Runtime sampler/renderer, which only
    /// needs a flat color and an asset reference regardless of layer type —
    /// see `KeyframeSampler.swift`/`PreviewCanvas.swift`.
    var assetId: String? {
        switch payload {
        case .image(let p): return p.assetId
        case .video(let p): return p.assetId
        default: return nil
        }
    }

    var fit: String? {
        switch payload {
        case .image(let p): return p.fit
        case .video(let p): return p.fit
        default: return nil
        }
    }

    /// Only a plain solid color is rendered; gradients/patterns/references
    /// are a known, separate gap from protocol shape parity (this app's
    /// renderer never constructs anything but `.color`/`.solid`, so this is
    /// only reachable when decoding a fixture authored with a richer paint).
    var fillColor: V2Color? {
        switch payload {
        case .shape(_, let style): return style.fill?.flatColor
        case .path(_, let style): return style.fill?.flatColor
        default: return nil
        }
    }

    var textPayload: V2TextLayerPayload? {
        if case .text(let payload) = payload { return payload }
        return nil
    }

    init(
        id: String, parentLayerId: String? = nil, order: Int = 0, frame: V2Frame, transform: V2Transform,
        opacity: Double? = 1, color: V2Color? = nil, enabled: Bool? = nil, visibility: V2Visibility? = nil,
        backfaceVisibility: V2BackfaceVisibility? = nil, clipPath: String? = nil, mask: String? = nil,
        maskLayers: [V2MaskLayer]? = nil, filter: String? = nil, backdropFilter: String? = nil,
        motion: V2MotionPath? = nil, composite: V2Composite? = nil,
        timing: V2Timing, tracks: [V2Track]? = nil, payload: V2LayerPayload
    ) {
        self.id = id
        self.parentLayerId = parentLayerId
        self.order = order
        self.frame = frame
        self.transform = transform
        self.opacity = opacity
        self.color = color
        self.enabled = enabled
        self.visibility = visibility
        self.backfaceVisibility = backfaceVisibility
        self.clipPath = clipPath
        self.mask = mask
        self.maskLayers = maskLayers
        self.filter = filter
        self.backdropFilter = backdropFilter
        self.motion = motion
        self.composite = composite
        self.timing = timing
        self.tracks = tracks
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case id, parentLayerId, order, frame, transform, opacity, color, enabled, visibility, backfaceVisibility
        case clipPath, mask, maskLayers, filter, backdropFilter, motion, composite, timing, tracks
        case type, payload, style, render3d
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        parentLayerId = try c.decodeIfPresent(String.self, forKey: .parentLayerId)
        order = try c.decode(Int.self, forKey: .order)
        frame = try c.decode(V2Frame.self, forKey: .frame)
        transform = try c.decode(V2Transform.self, forKey: .transform)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
        color = try c.decodeIfPresent(V2Color.self, forKey: .color)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        visibility = try c.decodeIfPresent(V2Visibility.self, forKey: .visibility)
        backfaceVisibility = try c.decodeIfPresent(V2BackfaceVisibility.self, forKey: .backfaceVisibility)
        clipPath = try c.decodeIfPresent(String.self, forKey: .clipPath)
        mask = try c.decodeIfPresent(String.self, forKey: .mask)
        maskLayers = try c.decodeIfPresent([V2MaskLayer].self, forKey: .maskLayers)
        filter = try c.decodeIfPresent(String.self, forKey: .filter)
        backdropFilter = try c.decodeIfPresent(String.self, forKey: .backdropFilter)
        motion = try c.decodeIfPresent(V2MotionPath.self, forKey: .motion)
        composite = try c.decodeIfPresent(V2Composite.self, forKey: .composite)
        timing = try c.decode(V2Timing.self, forKey: .timing)
        tracks = try c.decodeIfPresent([V2Track].self, forKey: .tracks)

        switch try c.decode(String.self, forKey: .type) {
        case "group":
            payload = .group(render3d: try c.decodeIfPresent(V2Render3D.self, forKey: .render3d))
        case "shape":
            payload = .shape(try c.decode(V2ShapePayload.self, forKey: .payload), style: try c.decode(V2DrawStyle.self, forKey: .style))
        case "path":
            payload = .path(try c.decode(V2PathPayload.self, forKey: .payload), style: try c.decode(V2DrawStyle.self, forKey: .style))
        case "image":
            payload = .image(try c.decode(V2ImagePayload.self, forKey: .payload))
        case "video":
            payload = .video(try c.decode(V2VideoPayload.self, forKey: .payload))
        case "text":
            payload = .text(try c.decode(V2TextLayerPayload.self, forKey: .payload))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown layer type: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(parentLayerId, forKey: .parentLayerId)
        try c.encode(order, forKey: .order)
        try c.encode(frame, forKey: .frame)
        try c.encode(transform, forKey: .transform)
        try c.encodeIfPresent(opacity, forKey: .opacity)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(visibility, forKey: .visibility)
        try c.encodeIfPresent(backfaceVisibility, forKey: .backfaceVisibility)
        try c.encodeIfPresent(clipPath, forKey: .clipPath)
        try c.encodeIfPresent(mask, forKey: .mask)
        try c.encodeIfPresent(maskLayers, forKey: .maskLayers)
        try c.encodeIfPresent(filter, forKey: .filter)
        try c.encodeIfPresent(backdropFilter, forKey: .backdropFilter)
        try c.encodeIfPresent(motion, forKey: .motion)
        try c.encodeIfPresent(composite, forKey: .composite)
        try c.encode(timing, forKey: .timing)
        try c.encodeIfPresent(tracks, forKey: .tracks)
        try c.encode(type, forKey: .type)
        switch payload {
        case .group(let render3d):
            try c.encodeIfPresent(render3d, forKey: .render3d)
        case .shape(let shapePayload, let style):
            try c.encode(shapePayload, forKey: .payload); try c.encode(style, forKey: .style)
        case .path(let pathPayload, let style):
            try c.encode(pathPayload, forKey: .payload); try c.encode(style, forKey: .style)
        case .image(let imagePayload):
            try c.encode(imagePayload, forKey: .payload)
        case .video(let videoPayload):
            try c.encode(videoPayload, forKey: .payload)
        case .text(let textPayload):
            try c.encode(textPayload, forKey: .payload)
        }
    }
}
