import Foundation

/// Editor-tier authoring intent for a text layer's line layout — the "how do
/// I want it wrapped/aligned" half that Protocol V2's `V2TextLayout` no
/// longer carries (see CLAUDE.md's "Text layout stays atomic" note).
/// `TextLayoutCompiler` resolves this, together with the font and frame
/// width, into Protocol V2's resolved `V2TextLayout` plus required per-line
/// `V2TextChunk.x`/`.y` — Protocol V2 itself never sees "center" or "word
/// wrap", only the already-shaped result.
struct EditorTextLayoutIntent: Codable {
    /// "left" | "center" | "right"
    var textAlign: String
    /// "none" | "word" | "character"
    var wrap: String
}

/// Authoring intent for a per-character stagger reveal (typewriter effect).
/// Compiles into Protocol V2's compact `V2TextRangeSelector` — see
/// CLAUDE.md's "`rangeSelectors` stays in Protocol V2" note: this is one of
/// the rare cases where Protocol V2 itself keeps compact, unexpanded intent
/// rather than atomic per-character tracks, so the Editor-tier intent here
/// and the Protocol V2 field it compiles into end up shaped almost the same.
struct EditorTypewriterIntent: Codable {
    var perUnitDelayMs: Double
    /// "forward" | "reverse"
    var direction: String
    /// "instant" (hard on/off, no blending — CSS step easing) | "fade"
    /// (300ms opacity ramp). This is the "look" choice and belongs here,
    /// not hardcoded in `PresetCompiler.swift` — see CLAUDE.md's "Protocol
    /// V2 must stay atomic" rule: a named per-character reveal style is an
    /// Editor-tier concept the same way a named effect/animation preset is.
    var reveal: String
}

/// Authoring intent for a per-character wave (arc-text style) effect.
/// Compiles into real, fully atomic per-character `V2TextChunk.dx`/`.dy`/
/// `.rotate` arrays — unlike `typewriter`, there is no compact/unexpanded
/// form here: these three fields are already the atomic, lowest-level SVG
/// per-character primitives, so "wave" is a true Editor-tier preset that
/// expands into literal numbers before anything becomes Protocol V2 JSON,
/// the same shape of relationship as an animation preset.
struct EditorTextWaveIntent: Codable {
    /// Vertical swing, in points.
    var amplitude: Double
    /// Max per-character rotation, in degrees.
    var rotationDegrees: Double
    /// Characters per full wave cycle.
    var periodChars: Double
}

/// Authoring intent for "text on a path" (circle only in this slice — see
/// `TextPathResolver.swift`). Like `wave`, this expands fully into literal
/// per-character `dx`/`dy`/`rotate` at compile time — computed from real
/// path geometry (arc-length placement) rather than a closed-form sine
/// formula, but landing in the exact same Protocol V2 fields, so it reuses
/// the already-verified rendering path unchanged.
struct EditorTextPathIntent: Codable {
    /// Circle radius, in points.
    var radius: Double
    /// Points — distance from the path's own start where the text begins.
    var startOffset: Double
}

struct EditorTextLayer: Codable {
    var text: String
    var fontFamily: String
    var fontSize: Double
    var color: String
    var layout: EditorTextLayoutIntent
    var typewriter: EditorTypewriterIntent?
    var wave: EditorTextWaveIntent?
    var textPath: EditorTextPathIntent?
}
