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

struct PresetBinding: Codable {
    var kind: PresetKind
    var durationMs: Double
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
}

struct EditorDocument: Codable {
    var id: String
    var composition: V2Composition
    var assets: [V2Asset]
    var layers: [EditorLayer]
}
