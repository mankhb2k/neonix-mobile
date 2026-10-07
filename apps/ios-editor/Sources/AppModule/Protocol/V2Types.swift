import Foundation

// Minimal, hand-written mirror of a subset of Protocol V2
// (packages/motion-protocol/src/v2). Field names and shapes match the Zod
// schema exactly so a fixture JSON authored against the TS schema decodes
// here unchanged. This is a deliberately small subset (shape/image/video
// layers, `.number` keyframe values only) for the first vertical slice —
// full parity is meant to come later from generated Codable types, per
// ARCHITECTURE.md, not from hand-maintaining this file forever.
//
// Codable (not just Decodable): the preset compiler builds a `V2Project` in
// memory and needs to serialize it straight to disk as the saved Protocol
// V2 document, reusing this one model for both decode (the static fixtures)
// and encode (compiler output) rather than a second DTO.

/// Full port of packages/motion-protocol/src/v2/project.ts's root shape.
/// No `superRefine` cross-field validation is ported (duplicate IDs,
/// dangling references, track-path/kind matching, etc.) — see
/// ARCHITECTURE.md's "valid by construction" strategy.
struct V2Project: Codable {
    var format: String = "motion-protocol"
    var formatVersion: Int = 2
    var id: String = "untitled"
    let composition: V2Composition
    let assets: [V2Asset]
    var markers: [V2Marker]?
    var clipPaths: [V2ClipPath]?
    var masks: [V2Mask]?
    var filters: [V2Filter]?
    var paintServers: [V2PaintServerDefinition]?
    let layers: [V2Layer]
    var audio: V2AudioDomain = V2AudioDomain(sampleRate: 48000, tracks: [])

    init(
        format: String = "motion-protocol", formatVersion: Int = 2, id: String = "untitled",
        composition: V2Composition, assets: [V2Asset], markers: [V2Marker]? = nil, clipPaths: [V2ClipPath]? = nil,
        masks: [V2Mask]? = nil, filters: [V2Filter]? = nil, paintServers: [V2PaintServerDefinition]? = nil,
        layers: [V2Layer], audio: V2AudioDomain = V2AudioDomain(sampleRate: 48000, tracks: [])
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.id = id
        self.composition = composition
        self.assets = assets
        self.markers = markers
        self.clipPaths = clipPaths
        self.masks = masks
        self.filters = filters
        self.paintServers = paintServers
        self.layers = layers
        self.audio = audio
    }
}

/// `colorSpace` mirrors a Zod `.default("srgb")` field — optional here,
/// caller applies the fallback.
struct V2Composition: Codable {
    let width: Double
    let height: Double
    let fps: Double
    let background: String
    var colorSpace: String?
    var view: V2View?

    init(width: Double, height: Double, fps: Double, background: String, colorSpace: String? = nil, view: V2View? = nil) {
        self.width = width
        self.height = height
        self.fps = fps
        self.background = background
        self.colorSpace = colorSpace
        self.view = view
    }
}

/// Import-time audio derivative for a video asset (video only).
struct V2VideoAudioDerivative: Codable {
    var uri: String
    var mimeType: String?
    var duration: Double?
    var sampleRate: Double?
    var channels: Int?
    var integrity: String?
}

struct V2ImageAsset {
    var id: String
    /// Bundled resource filename (e.g. "photo.jpg"), looked up via
    /// `Bundle.module` — see the note on `PreviewCanvas`.
    var uri: String
    var mimeType: String?
    var width: Double
    var height: Double
    var integrity: String?
}

struct V2VideoAsset {
    var id: String
    var uri: String
    var mimeType: String?
    var width: Double
    var height: Double
    /// Milliseconds.
    var duration: Double
    var fps: Double?
    var integrity: String?
    /// The audio-only derivative; the video's own `uri` stays the visual
    /// source.
    var audio: V2VideoAudioDerivative?
}

struct V2AudioAsset {
    var id: String
    var uri: String
    var mimeType: String
    /// Milliseconds.
    var duration: Double
    var sampleRate: Double?
    var channels: Int?
    var integrity: String?
}

struct V2FontAsset {
    var id: String
    var uri: String
    var mimeType: String?
    var weight: Int
    var integrity: String
}

/// A 3D color LUT (Look-Up Table) — a precomputed grid of input→output RGB
/// mappings, not a formula (unlike `feColorMatrix`/`feComponentTransfer`,
/// which can't express an arbitrary, non-linear, cross-channel color grade).
/// `uri` points to a standard `.cube` file (Adobe/ACES Cube LUT format) —
/// chosen over a custom format so a LUT a user imports from anywhere online
/// just works, no conversion step. `dimension` is the cube's edge length
/// (`LUT_3D_SIZE` in the `.cube` file header, e.g. 17/33/64) — read from the
/// file itself, not duplicated/guessable from `uri` alone. See
/// `ui-design-note.md` for the full design discussion (why a new asset kind
/// instead of inlining the grid data, why `.cube` over a custom format).
struct V2LutAsset {
    var id: String
    var uri: String
    var dimension: Int
    var mimeType: String?
    var integrity: String?
}

/// Full port of packages/motion-protocol/src/v2/assets.ts as a true
/// discriminated union (`z.discriminatedUnion("kind", ...)` in the real
/// schema) — see the atomicity audit this was built from: the earlier
/// flattened-struct Swift port let a video-only field (e.g. `fps`) be
/// present on an image asset at the type level, which this fixes.
enum V2Asset: Codable {
    case image(V2ImageAsset)
    case video(V2VideoAsset)
    case audio(V2AudioAsset)
    case font(V2FontAsset)
    case lut(V2LutAsset)

    var id: String {
        switch self {
        case .image(let a): return a.id
        case .video(let a): return a.id
        case .audio(let a): return a.id
        case .font(let a): return a.id
        case .lut(let a): return a.id
        }
    }

    var uri: String {
        switch self {
        case .image(let a): return a.uri
        case .video(let a): return a.uri
        case .audio(let a): return a.uri
        case .font(let a): return a.uri
        case .lut(let a): return a.uri
        }
    }

    var mimeType: String? {
        switch self {
        case .image(let a): return a.mimeType
        case .video(let a): return a.mimeType
        case .audio(let a): return a.mimeType
        case .font(let a): return a.mimeType
        case .lut(let a): return a.mimeType
        }
    }

    var kind: String {
        switch self {
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .font: return "font"
        case .lut: return "lut"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, uri, mimeType, width, height, integrity, duration, fps, audio, sampleRate, channels, weight, dimension
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let uri = try c.decode(String.self, forKey: .uri)
        let mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        let integrity = try c.decodeIfPresent(String.self, forKey: .integrity)
        switch try c.decode(String.self, forKey: .kind) {
        case "image":
            self = .image(V2ImageAsset(
                id: id, uri: uri, mimeType: mimeType,
                width: try c.decode(Double.self, forKey: .width), height: try c.decode(Double.self, forKey: .height),
                integrity: integrity
            ))
        case "video":
            self = .video(V2VideoAsset(
                id: id, uri: uri, mimeType: mimeType,
                width: try c.decode(Double.self, forKey: .width), height: try c.decode(Double.self, forKey: .height),
                duration: try c.decode(Double.self, forKey: .duration), fps: try c.decodeIfPresent(Double.self, forKey: .fps),
                integrity: integrity, audio: try c.decodeIfPresent(V2VideoAudioDerivative.self, forKey: .audio)
            ))
        case "audio":
            self = .audio(V2AudioAsset(
                id: id, uri: uri, mimeType: try c.decode(String.self, forKey: .mimeType),
                duration: try c.decode(Double.self, forKey: .duration),
                sampleRate: try c.decodeIfPresent(Double.self, forKey: .sampleRate), channels: try c.decodeIfPresent(Int.self, forKey: .channels),
                integrity: integrity
            ))
        case "font":
            self = .font(V2FontAsset(
                id: id, uri: uri, mimeType: mimeType,
                weight: try c.decode(Int.self, forKey: .weight), integrity: try c.decode(String.self, forKey: .integrity)
            ))
        case "lut":
            self = .lut(V2LutAsset(
                id: id, uri: uri, dimension: try c.decode(Int.self, forKey: .dimension),
                mimeType: mimeType, integrity: integrity
            ))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown asset kind: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(uri, forKey: .uri)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
        switch self {
        case .image(let a):
            try c.encode(a.width, forKey: .width); try c.encode(a.height, forKey: .height)
            try c.encodeIfPresent(a.integrity, forKey: .integrity)
        case .video(let a):
            try c.encode(a.width, forKey: .width); try c.encode(a.height, forKey: .height)
            try c.encode(a.duration, forKey: .duration); try c.encodeIfPresent(a.fps, forKey: .fps)
            try c.encodeIfPresent(a.integrity, forKey: .integrity); try c.encodeIfPresent(a.audio, forKey: .audio)
        case .audio(let a):
            try c.encode(a.duration, forKey: .duration)
            try c.encodeIfPresent(a.sampleRate, forKey: .sampleRate); try c.encodeIfPresent(a.channels, forKey: .channels)
            try c.encodeIfPresent(a.integrity, forKey: .integrity)
        case .font(let a):
            try c.encode(a.weight, forKey: .weight); try c.encode(a.integrity, forKey: .integrity)
        case .lut(let a):
            try c.encode(a.dimension, forKey: .dimension); try c.encodeIfPresent(a.integrity, forKey: .integrity)
        }
    }
}

struct V2Frame: Codable {
    let width: Double
    let height: Double
}

struct V2Timing: Codable {
    let start: Double
    let duration: Double
}

struct V2Vec3: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct V2Vec2: Codable {
    let x: Double
    let y: Double
}

/// Full port of packages/motion-protocol/src/v2/transform.ts. One explicit
/// component form only — no ordered `operations[]` list; don't re-add one.
/// See CLAUDE.md's "Layer transform: one explicit component form, no
/// `operations[]`" section for the full rationale (2D/3D field mapping, why
/// the old dual representation was a real bug, and how this differs from
/// `V2SvgTransformOperation` in `V2Clip.swift`).
struct V2Transform: Codable {
    let translate: V2Vec3
    let scale: V2Vec3
    let rotate: V2Vec3
    let skew: V2Vec2
    let anchor: V2Vec3
    /// CSS-style perspective distance for 3D rotations (`rotate.x`/`rotate.y`).
    /// `nil`/absent means "no 3D tilt in use" — only meaningful once either
    /// of those is non-zero.
    var perspective: Double?

    init(
        translate: V2Vec3, scale: V2Vec3, rotate: V2Vec3, skew: V2Vec2, anchor: V2Vec3,
        perspective: Double? = nil
    ) {
        self.translate = translate
        self.scale = scale
        self.rotate = rotate
        self.skew = skew
        self.anchor = anchor
        self.perspective = perspective
    }

    static let identity = V2Transform(
        translate: V2Vec3(x: 0, y: 0, z: 0),
        scale: V2Vec3(x: 1, y: 1, z: 1),
        rotate: V2Vec3(x: 0, y: 0, z: 0),
        skew: V2Vec2(x: 0, y: 0),
        anchor: V2Vec3(x: 0, y: 0, z: 0)
    )
}

// V2Layer itself now lives in V2Layers.swift (full base fields + the
// group/shape/path/image/video/text discriminated payload), replacing the
// flattened `fill`/`assetId`/`fit` shortcut this file used to define.

struct V2Track: Codable {
    let id: String
    let path: String
    let keyframes: [V2Keyframe]
    let animation: V2AnimationPlayback?
}

/// Full port of the keyframe value union in animation.ts. The Runtime
/// sampler (`KeyframeSampler.swift`) only ever interpolates `.number` (via
/// `asNumber`) — every other kind decodes/encodes faithfully but isn't
/// animated by this app's renderer yet, a known, separate gap from protocol
/// shape parity.
enum V2AnimatableValue: Codable {
    case number(Double)
    case vec2(Double, Double)
    case vec3(Double, Double, Double)
    case vec4(Double, Double, Double, Double)
    /// RGBA components in `0...1`.
    case color(Double, Double, Double, Double)
    case boolean(Bool)
    case string(String)
    case enumValue(String)

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "number":
            self = .number(try c.decode(Double.self, forKey: .value))
        case "vec2":
            let v = try c.decode([Double].self, forKey: .value)
            self = .vec2(v[0], v[1])
        case "vec3":
            let v = try c.decode([Double].self, forKey: .value)
            self = .vec3(v[0], v[1], v[2])
        case "vec4":
            let v = try c.decode([Double].self, forKey: .value)
            self = .vec4(v[0], v[1], v[2], v[3])
        case "color":
            let v = try c.decode([Double].self, forKey: .value)
            self = .color(v[0], v[1], v[2], v[3])
        case "boolean":
            self = .boolean(try c.decode(Bool.self, forKey: .value))
        case "string":
            self = .string(try c.decode(String.self, forKey: .value))
        case "enum":
            self = .enumValue(try c.decode(String.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown animatable value kind: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let n):
            try c.encode("number", forKey: .type); try c.encode(n, forKey: .value)
        case .vec2(let x, let y):
            try c.encode("vec2", forKey: .type); try c.encode([x, y], forKey: .value)
        case .vec3(let x, let y, let z):
            try c.encode("vec3", forKey: .type); try c.encode([x, y, z], forKey: .value)
        case .vec4(let x, let y, let z, let w):
            try c.encode("vec4", forKey: .type); try c.encode([x, y, z, w], forKey: .value)
        case .color(let r, let g, let b, let a):
            try c.encode("color", forKey: .type); try c.encode([r, g, b, a], forKey: .value)
        case .boolean(let b):
            try c.encode("boolean", forKey: .type); try c.encode(b, forKey: .value)
        case .string(let s):
            try c.encode("string", forKey: .type); try c.encode(s, forKey: .value)
        case .enumValue(let s):
            try c.encode("enum", forKey: .type); try c.encode(s, forKey: .value)
        }
    }

    /// Used by the sampler, which only interpolates numeric tracks.
    var asNumber: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}

struct V2Keyframe: Codable {
    let time: V2KeyframeTime
    let value: V2AnimatableValue
    let easing: V2Easing?

    init(time: V2KeyframeTime, value: Double, easing: V2Easing? = nil) {
        self.time = time
        self.value = .number(value)
        self.easing = easing
    }

    init(time: V2KeyframeTime, value: V2AnimatableValue, easing: V2Easing? = nil) {
        self.time = time
        self.value = value
        self.easing = easing
    }
}

/// Mirrors `V2KeyframeTimeSchema` exactly: a bare number, or
/// `{ anchor: "start" | "end", offsetMs }`.
enum V2KeyframeTime: Codable {
    case absolute(Double)
    case anchored(anchor: Anchor, offsetMs: Double)

    enum Anchor: String, Codable {
        case start, end
    }

    private enum CodingKeys: String, CodingKey {
        case anchor, offsetMs
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let number = try? single.decode(Double.self) {
            self = .absolute(number)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let anchor = try container.decode(Anchor.self, forKey: .anchor)
        let offsetMs = try container.decode(Double.self, forKey: .offsetMs)
        self = .anchored(anchor: anchor, offsetMs: offsetMs)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .absolute(let ms):
            var single = encoder.singleValueContainer()
            try single.encode(ms)
        case .anchored(let anchor, let offsetMs):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(anchor, forKey: .anchor)
            try container.encode(offsetMs, forKey: .offsetMs)
        }
    }
}

/// Full port of the easing union in animation.ts. The sampler
/// (`KeyframeSampler.swift`) only evaluates `.linear`/`.cubicBezier` so far;
/// `.step`/`.spring` decode/encode faithfully but fall back to linear at
/// sample time — a known, separate gap from protocol shape parity.
enum V2Easing: Codable {
    case linear
    /// `count`/`position` mirror Zod `.default(1)`/`.default("jump-end")`
    /// fields — optional here, caller applies the fallback.
    case step(count: Int?, position: String?)
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)
    case spring(mass: Double, stiffness: Double, damping: Double, velocity: Double?)

    private enum CodingKeys: String, CodingKey {
        case type, x1, y1, x2, y2, count, position, mass, stiffness, damping, velocity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "linear":
            self = .linear
        case "step":
            self = .step(count: try c.decodeIfPresent(Int.self, forKey: .count), position: try c.decodeIfPresent(String.self, forKey: .position))
        case "cubicBezier":
            self = .cubicBezier(
                x1: try c.decode(Double.self, forKey: .x1), y1: try c.decode(Double.self, forKey: .y1),
                x2: try c.decode(Double.self, forKey: .x2), y2: try c.decode(Double.self, forKey: .y2)
            )
        case "spring":
            self = .spring(
                mass: try c.decode(Double.self, forKey: .mass), stiffness: try c.decode(Double.self, forKey: .stiffness),
                damping: try c.decode(Double.self, forKey: .damping), velocity: try c.decodeIfPresent(Double.self, forKey: .velocity)
            )
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown easing: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .linear:
            try c.encode("linear", forKey: .type)
        case .step(let count, let position):
            try c.encode("step", forKey: .type)
            try c.encodeIfPresent(count, forKey: .count); try c.encodeIfPresent(position, forKey: .position)
        case .cubicBezier(let x1, let y1, let x2, let y2):
            try c.encode("cubicBezier", forKey: .type)
            try c.encode(x1, forKey: .x1); try c.encode(y1, forKey: .y1); try c.encode(x2, forKey: .x2); try c.encode(y2, forKey: .y2)
        case .spring(let mass, let stiffness, let damping, let velocity):
            try c.encode("spring", forKey: .type)
            try c.encode(mass, forKey: .mass); try c.encode(stiffness, forKey: .stiffness)
            try c.encode(damping, forKey: .damping); try c.encodeIfPresent(velocity, forKey: .velocity)
        }
    }
}

struct V2AnimationPlayback: Codable {
    let durationMs: Double
    let delayMs: Double
    let iterations: Iterations
    let direction: Direction
    let fillMode: String
    let playState: PlayState

    enum Direction: String, Codable {
        case normal, reverse, alternate
        case alternateReverse = "alternate-reverse"
    }

    enum PlayState: String, Codable {
        case running, paused
    }

    enum Iterations: Codable {
        case count(Double)
        case infinite

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self), string == "infinite" {
                self = .infinite
            } else {
                self = .count(try container.decode(Double.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .count(let value): try container.encode(value)
            case .infinite: try container.encode("infinite")
            }
        }
    }
}
