import Foundation

// The "Editor Document" half of the two-tier model from ARCHITECTURE.md:
// authoring intent (which media, which named preset) — never persisted as
// raw Protocol V2 tracks. `PresetCompiler.compile(_:)` lowers this into a
// `V2Project`, which is the only thing the Runtime/renderer ever sees.

enum PresetKind: String, Codable, CaseIterable {
    case fade, slide, zoom
}

enum PresetDirection: String, Codable {
    case `in`
    case out
}

/// "linear" | "easeIn" | "easeOut" | "easeInOut" — a named shorthand for a
/// specific `V2Easing.cubicBezier(x1:y1:x2:y2:)` curve (matching the
/// standard CSS `ease-in`/`ease-out`/`ease-in-out` constants), resolved by
/// `PresetCompiler` before anything becomes Protocol V2 JSON — see
/// CLAUDE.md's "Protocol V2 must stay atomic" rule: the name is an
/// Editor-tier convenience, Protocol V2 only ever sees the literal
/// cubic-bezier numbers (already atomic there, nothing to change in the
/// schema for this).
struct PresetBinding: Codable {
    var kind: PresetKind
    var durationMs: Double
    var easing: String?
}

struct EditorLayer: Codable {
    var id: String
    /// "shape" | "image" | "video" | "text"
    var kind: String
    var assetId: String?
    var fill: String?
    var frame: V2Frame
    var timing: V2Timing
    var inPreset: PresetBinding?
    var outPreset: PresetBinding?
    /// Named visual-effect presets (glow, blur, sepia, ...) — see
    /// `EffectPresets.swift` and CLAUDE.md's "Protocol V2 stays atomic"
    /// rule. Compiled into a `V2Filter` definition, never persisted as
    /// named effects in Protocol V2 itself.
    var effectPresets: [EffectPresetKind]?
    /// Text authoring intent (`kind == "text"` only) — see
    /// `EditorTextLayer.swift` and CLAUDE.md's "Text layout stays atomic"
    /// note. Compiled by `TextLayoutCompiler` into Protocol V2's resolved
    /// `V2TextLayout` + `V2TextChunk`s, never persisted as wrap/align intent
    /// in Protocol V2 itself.
    var text: EditorTextLayer?
    /// Resting position/scale/rotation on the canvas; nil = centred, upright, own size (see `EditorTransform`).
    var transform: EditorTransform?
    /// 0...1, nil = fully opaque. Presets (fade) animate on top of it.
    var opacity: Double?
}

struct EditorDocument: Codable {
    var id: String
    var composition: V2Composition
    var assets: [V2Asset]
    var layers: [EditorLayer]
    /// Editor-only authoring intent. The compiler lowers each adjacent cut into V2 groups/tracks;
    /// renderers extend only those wrappers across the cut, while clip timings remain contiguous.
    var transitions: [EditorTransitionIntent]? = nil
    /// Background music etc. Audio has its own domain, not a layer (CLAUDE.md, "Timeline lanes"); present in
    /// template documents, nil for plain projects.
    var audio: V2AudioDomain?
}

struct EditorTransitionIntent: Codable, Equatable {
    var outgoingId: String
    var incomingId: String
    var kind: TransitionKind
    var durationMs: Double
}
