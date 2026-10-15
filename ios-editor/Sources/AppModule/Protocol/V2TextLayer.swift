import Foundation

// Port of packages/motion-protocol/src/v2/layers/text.ts — the most complex
// single file in the schema.

struct V2TextFont: Codable {
    var families: [String]
    var size: V2SvgLength
    var weight: Int?
    var style: String?
    var stretch: String?
    var variations: [String: Double]?
}

struct V2TextDecorationStyle: Codable {
    var fill: V2Paint?
    var stroke: V2Paint?
    var strokeWidth: V2SvgLength?
    var style: String?
}

struct V2TextDecoration: Codable {
    var underline: V2TextDecorationStyle?
    var overline: V2TextDecorationStyle?
    var lineThrough: V2TextDecorationStyle?
}

/// `"normal"` or a length.
enum V2TextSpacing: Codable {
    case normal
    case length(V2SvgLength)

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self), s == "normal" {
            self = .normal; return
        }
        self = .length(try V2SvgLength(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .normal:
            var single = encoder.singleValueContainer(); try single.encode("normal")
        case .length(let length):
            try length.encode(to: encoder)
        }
    }
}

/// `"baseline"`/`"subscript"`/`"superscript"`, or a length.
enum V2BaselineShift: Codable {
    case keyword(String)
    case length(V2SvgLength)

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self = .keyword(s); return
        }
        self = .length(try V2SvgLength(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .keyword(let s):
            var single = encoder.singleValueContainer(); try single.encode(s)
        case .length(let length):
            try length.encode(to: encoder)
        }
    }
}

struct V2TextRange: Codable {
    var start: Int
    var end: Int
}

/// A text shadow (CSS `text-shadow`): a blurred copy of the glyphs behind them. Atomic: colour with its own alpha, offset and blur in
/// layer units. A glow is the same thing with a zero offset - the Editor tier keeps the names, V2 only ever sees these numbers.
struct V2TextShadow: Codable, Equatable {
    var color: V2Color
    var offsetX: Double
    var offsetY: Double
    var blur: Double
}

struct V2TextSpan: Codable {
    var id: String
    var sourceRange: V2TextRange
    /// Ordered compiler result for deterministic font-face and glyph
    /// fallback.
    var resolvedFontAssetIds: [String]?
    var font: V2TextFont
    var fill: V2Paint?
    var fillOpacity: Double?
    var stroke: V2Paint?
    var strokeWidth: V2SvgLength?
    var strokeOpacity: Double?
    var paintOrder: V2PaintOrder?
    var letterSpacing: V2TextSpacing?
    var wordSpacing: V2TextSpacing?
    var dominantBaseline: String?
    var alignmentBaseline: String?
    var baselineShift: V2BaselineShift?
    var textLength: V2SvgLength?
    var lengthAdjust: String?
    var textDecoration: V2TextDecoration?
    var kerning: String?
    var opticalSizing: String?
    var smallCaps: Bool?
    /// Back to front. Absent = no shadow.
    var shadows: [V2TextShadow]?
    /// CSS `text-transform`: `"uppercase"` | `"lowercase"` | `"capitalize"`. The source text keeps what was typed; the renderer (and the
    /// layout compiler, which measures the transformed words) applies it.
    var textTransform: String?
}

struct V2TextPath: Codable {
    var pathId: String
    var startOffset: V2SvgLength?
    var method: String?
    var spacing: String?
}

struct V2TextChunk: Codable {
    var id: String
    var sourceRange: V2TextRange
    var x: [V2SvgLength]?
    var y: [V2SvgLength]?
    var dx: [V2SvgLength]?
    var dy: [V2SvgLength]?
    var rotate: [Double]?
    var textAnchor: String?
    var textPath: V2TextPath?
    var spans: [V2TextSpan]
}

/// `direction`/`writingMode`/`whiteSpace`/`textRendering` mirror Zod
/// `.optional()` fields (no defaults here, unlike most of this port).
struct V2TextSource: Codable {
    var text: String
    var language: String?
    var direction: String?
    var writingMode: String?
    var whiteSpace: String?
    var textRendering: String?
}

/// Protocol V2's half of text layout — resolved, renderer-ready facts only,
/// produced by real text shaping. The *intent* half (wrap policy, alignment,
/// overflow, sizing mode, hard breaks, ...) is deliberately not here: it
/// lives only in the Editor tier (`EditorTextLayoutIntent` in
/// `EditorDocument/EditorTextLayer.swift`) and is always fully resolved by
/// `TextLayoutCompiler` into this struct plus required per-line
/// `V2TextChunk.x`/`.y` before Protocol V2 JSON exists. See CLAUDE.md's
/// "Text layout stays atomic" note: keeping the intent fields here too would
/// let two renderers (e.g. Core Text vs HarfBuzz vs a browser engine) each
/// re-wrap the same source text differently, breaking the renderer-neutral
/// guarantee every other part of Protocol V2 already has.
struct V2TextLayout: Codable {
    var lineHeight: Double
    var contentWidth: Double?
    var contentHeight: Double?
    var contentOffsetX: Double?
    var contentOffsetY: Double?
    /// A filled shape behind the text, already resolved (see `V2TextBackground`). Optional: absent = no background.
    var background: V2TextBackground?
}

/// The background label of a text layer (rounded, hugging every line - Facebook / Instagram story style). Atomic and renderer-neutral:
/// plain path geometry in the layer's own coordinates (the same space as the chunks' `x`/`y`) and a fill. The Editor tier keeps the
/// intent (colour, "story style"); the compiler resolves the corners, so no renderer ever re-derives them.
struct V2TextBackground: Codable {
    var contours: [V2PathContour]
    var fill: V2Paint
}

/// Authoring shorthand for a typewriter/stagger effect. Kept compact and
/// unexpanded in Protocol V2 on purpose (see CLAUDE.md's "`rangeSelectors`
/// stays in Protocol V2" note) — this app's Runtime (`KeyframeSampler.swift`)
/// interprets it directly at sample time rather than expanding it into real
/// per-character spans/tracks ahead of time.
struct V2TextRangeSelectorStagger: Codable {
    var perUnitDelayMs: Double
    /// Mirrors a Zod `.default("forward")` field — optional here, caller
    /// applies the fallback.
    var direction: String?
}

/// `range` is `"all"` or an explicit `{start, end}`.
enum V2TextRangeSelectorRange: Codable {
    case all
    case range(V2TextRange)

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self), s == "all" {
            self = .all; return
        }
        self = .range(try V2TextRange(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .all:
            var single = encoder.singleValueContainer(); try single.encode("all")
        case .range(let r):
            try r.encode(to: encoder)
        }
    }
}

struct V2TextRangeSelector: Codable {
    var id: String
    var unit: String // "character" | "word"
    var range: V2TextRangeSelectorRange
    var stagger: V2TextRangeSelectorStagger
    /// Template track cloned once per unit; `path` is relative to the
    /// synthetic per-character span, not the layer-root
    /// `payload.chunks.spans.<id>.` form.
    var track: V2Track
}

struct V2TextLayerPayload: Codable {
    var source: V2TextSource
    var layout: V2TextLayout?
    var chunks: [V2TextChunk]
    var rangeSelectors: [V2TextRangeSelector]?
}
