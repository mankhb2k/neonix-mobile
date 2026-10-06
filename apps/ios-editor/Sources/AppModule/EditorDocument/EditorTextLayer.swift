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

struct EditorTextLayer: Codable {
    var text: String
    var fontFamily: String
    var fontSize: Double
    var color: String
    var layout: EditorTextLayoutIntent
}
