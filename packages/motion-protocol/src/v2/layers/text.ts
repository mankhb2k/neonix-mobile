import { z } from "zod";
import {
  V2FiniteNumberSchema,
  V2IdSchema,
  V2NonNegativeNumberSchema,
  V2PaintOrderSchema,
  V2PositiveNumberSchema,
  V2PositiveSvgLengthSchema,
  V2SvgLengthSchema,
} from "../common";
import { V2PaintSchema } from "../paint";
import { V2LayerTrackSchema } from "../animation";
import { V2LayerBaseSchema } from "./base";

const V2NfcTextSchema = z.string().refine(
  (value) => value === value.normalize("NFC"),
  "Text source must be NFC normalized",
);

const V2FontVariationAxisTagSchema = z
  .string()
  .regex(/^[ -~]{4}$/, "Font variation axis tag must contain exactly four printable ASCII characters");

const V2TextRangeSchema = z
  .object({
    /** UTF-16 offsets, matching JavaScript/editor string indexing. */
    start: V2NonNegativeNumberSchema.int(),
    end: V2NonNegativeNumberSchema.int(),
  })
  .strict()
  .superRefine((range, ctx) => {
    if (range.end < range.start) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text range end must not precede start", path: ["end"] });
    }
  });

const V2TextRunIdSchema = V2IdSchema.refine(
  (value) => !value.includes("."),
  "Text span id cannot contain a dot",
);

export const V2TextFontSchema = z
  .object({
    /** SVG font-family is an ordered fallback list, not one resolved asset. */
    families: z.array(z.string().trim().min(1)).min(1),
    size: V2PositiveSvgLengthSchema,
    weight: z.number().int().min(1).max(1000).optional(),
    style: z.enum(["normal", "italic", "oblique"]).optional(),
    stretch: z.enum([
      "ultra-condensed",
      "extra-condensed",
      "condensed",
      "semi-condensed",
      "normal",
      "semi-expanded",
      "expanded",
      "extra-expanded",
      "ultra-expanded",
    ]).optional(),
    variations: z.record(V2FontVariationAxisTagSchema, V2FiniteNumberSchema).optional(),
  })
  .strict();

export const V2TextDecorationStyleSchema = z
  .object({
    fill: V2PaintSchema.optional(),
    stroke: V2PaintSchema.optional(),
    strokeWidth: V2PositiveSvgLengthSchema.optional(),
    /** CSS text-decoration-style. Omitted/`solid` keeps the existing filled-rectangle line; the others draw a dashed/dotted/wavy stroke instead. `double` is not supported. */
    style: z.enum(["solid", "dotted", "dashed", "wavy"]).optional(),
  })
  .strict();

const V2TextSpacingSchema = z.union([z.literal("normal"), V2SvgLengthSchema]);
const V2BaselineShiftSchema = z.union([
  z.enum(["baseline", "subscript", "superscript"]),
  V2SvgLengthSchema,
]);

/** Normalized CSS-independent text layout contract for AI, authoring and HTML/CSS lowering. */
export const V2TextLayoutSchema = z
  .object({
    /** Whether the text frame is derived from shaping or authored by the user. */
    sizing: z.enum(["auto-width-height", "fixed-width-auto-height", "fixed"]).optional(),
    /** Resolved line box height in composition units. */
    lineHeight: V2PositiveNumberSchema,
    /** Inline content box width used for wrapping and horizontal alignment. */
    contentWidth: V2NonNegativeNumberSchema.optional(),
    /** Inline content box height used for vertical alignment. */
    contentHeight: V2NonNegativeNumberSchema.optional(),
    /** Content-box origin inside the layer border box. */
    contentOffsetX: V2NonNegativeNumberSchema.optional(),
    contentOffsetY: V2NonNegativeNumberSchema.optional(),
    /** UTF-16 offsets at which authored hard line breaks begin. */
    hardBreaks: z.array(V2NonNegativeNumberSchema.int()).min(1).optional(),
    textAlign: z.enum(["left", "right", "center", "start", "end", "justify", "match-parent", "justify-all"]),
    whiteSpace: z.enum(["normal", "nowrap", "pre", "pre-wrap", "pre-line", "break-spaces"]),
    /**
     * Normalized line breaking policy after white-space resolution.
     * `word-break-long` is CSS overflow-wrap/word-wrap: break-word - wraps at
     * word boundaries like `word`, but also breaks a single word that still
     * doesn't fit alone on an empty line. `character` is CSS word-break:
     * break-all - breaks anywhere, ignoring word boundaries entirely.
     */
    wrap: z.enum(["none", "word", "character", "word-break-long"]),
    textOverflow: z.enum(["clip", "ellipsis"]),
    maxLines: V2NonNegativeNumberSchema.int().positive().optional(),
    /** CSS text-indent: offsets the first line only (negative allowed, for hanging-indent authoring). */
    textIndent: V2FiniteNumberSchema.optional(),
  })
  .strict();

/** A normalized, non-overlapping SVG text/tspan style range. */
export const V2TextSpanSchema = z
  .object({
    id: V2TextRunIdSchema,
    sourceRange: V2TextRangeSchema,
    /** Ordered compiler result for deterministic font-face and glyph fallback. */
    resolvedFontAssetIds: z.array(V2IdSchema).min(1).optional(),
    font: V2TextFontSchema,
    fill: V2PaintSchema.optional(),
    fillOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
    stroke: V2PaintSchema.optional(),
    strokeWidth: V2PositiveSvgLengthSchema.optional(),
    strokeOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
    paintOrder: V2PaintOrderSchema.optional(),
    letterSpacing: V2TextSpacingSchema.optional(),
    wordSpacing: V2TextSpacingSchema.optional(),
    dominantBaseline: z.enum([
      "auto",
      "use-script",
      "no-change",
      "reset-size",
      "ideographic",
      "alphabetic",
      "hanging",
      "mathematical",
      "central",
      "middle",
      "text-after-edge",
      "text-before-edge",
    ]).optional(),
    alignmentBaseline: z.enum([
      "auto",
      "baseline",
      "before-edge",
      "text-before-edge",
      "middle",
      "central",
      "after-edge",
      "text-after-edge",
      "ideographic",
      "alphabetic",
      "hanging",
      "mathematical",
    ]).optional(),
    baselineShift: V2BaselineShiftSchema.optional(),
    textLength: V2PositiveSvgLengthSchema.optional(),
    lengthAdjust: z.enum(["spacing", "spacingAndGlyphs"]).optional(),
    textDecoration: z
      .object({
        underline: V2TextDecorationStyleSchema.optional(),
        overline: V2TextDecorationStyleSchema.optional(),
        lineThrough: V2TextDecorationStyleSchema.optional(),
      })
      .strict()
      .optional(),
    kerning: z.enum(["auto", "normal", "none"]).optional(),
    opticalSizing: z.enum(["auto", "none"]).optional(),
    smallCaps: z.boolean().optional(),
  })
  .strict();

export const V2TextPathSchema = z
  .object({
    /** Reference to a path element/definition in the same Protocol document. */
    pathId: V2IdSchema,
    startOffset: V2SvgLengthSchema.optional(),
    method: z.enum(["align", "stretch"]).optional(),
    spacing: z.enum(["auto", "exact"]).optional(),
  })
  .strict();

/** A normalized SVG text chunk. Its ranges point into source.text. */
export const V2TextChunkSchema = z
  .object({
    id: V2IdSchema,
    sourceRange: V2TextRangeSchema,
    x: z.array(V2SvgLengthSchema).min(1).optional(),
    y: z.array(V2SvgLengthSchema).min(1).optional(),
    dx: z.array(V2SvgLengthSchema).min(1).optional(),
    dy: z.array(V2SvgLengthSchema).min(1).optional(),
    rotate: z.array(V2FiniteNumberSchema).min(1).optional(),
    textAnchor: z.enum(["start", "middle", "end"]).optional(),
    textPath: V2TextPathSchema.optional(),
    spans: z.array(V2TextSpanSchema).min(1),
  })
  .strict()
  .superRefine((chunk, ctx) => {
    let previousEnd = chunk.sourceRange.start;
    const seen = new Set<string>();
    for (const [index, span] of chunk.spans.entries()) {
      if (seen.has(span.id)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate text span id: ${span.id}`, path: ["spans", index, "id"] });
      }
      seen.add(span.id);
      if (span.sourceRange.start < chunk.sourceRange.start || span.sourceRange.end > chunk.sourceRange.end) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text span range must be contained by its chunk", path: ["spans", index, "sourceRange"] });
      }
      if (span.sourceRange.start < previousEnd) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text spans must be ordered and non-overlapping", path: ["spans", index, "sourceRange"] });
      }
      previousEnd = span.sourceRange.end;
    }
  });

export const V2TextSourceSchema = z
  .object({
    text: V2NfcTextSchema,
    language: z.string().trim().min(1).max(35).optional(),
    direction: z.enum(["ltr", "rtl"]).optional(),
    writingMode: z.enum(["horizontal-tb", "vertical-rl", "vertical-lr"]).optional(),
    whiteSpace: z.enum(["default", "preserve"]).optional(),
    textRendering: z.enum(["auto", "optimizeSpeed", "geometricPrecision"]).optional(),
  })
  .strict();

/**
 * Authoring shorthand for a typewriter/stagger effect: expand at compile time
 * into real per-character spans and id-addressed tracks (see
 * `expandTextRangeSelectors` in `motion-compiler`), rather than requiring the
 * author to hand-split spans and duplicate a track per character. `unit:
 * "word"` is reserved but not yet implemented; the compiler fails closed with
 * a diagnostic instead of silently ignoring it.
 */
export const V2TextRangeSelectorSchema = z
  .object({
    id: V2IdSchema,
    unit: z.enum(["character", "word"]),
    /** UTF-16 offsets into the layer's source text; "all" covers the whole source. */
    range: z.union([
      z.literal("all"),
      V2TextRangeSchema,
    ]),
    stagger: z
      .object({
        perUnitDelayMs: V2NonNegativeNumberSchema,
        direction: z.enum(["forward", "reverse"]).default("forward"),
      })
      .strict(),
    /**
     * Template track cloned once per unit. `path` is relative to the
     * synthetic per-character span this selector generates (e.g.
     * "fillOpacity"), not the layer-root `payload.chunks.spans.<id>.` form.
     * Uses the layer-scoped track family so a template can end-anchor a
     * keyframe (e.g. the last character fading out at the clip's end).
     */
    track: V2LayerTrackSchema,
  })
  .strict();

export const V2TextLayerSchema = V2LayerBaseSchema.extend({
  type: z.literal("text"),
  payload: z
    .object({
      source: V2TextSourceSchema,
      /** Optional for backward compatibility; required when CSS text layout is authored. */
      layout: V2TextLayoutSchema.optional(),
      chunks: z.array(V2TextChunkSchema).min(1),
      /**
       * Authoring shorthand expanded at compile time into real per-character
       * spans and tracks (see `expandTextRangeSelectors` in motion-compiler).
       * Scoped under `payload` (not the layer root) so this cross-check can
       * validate a selector's range against `source.text.length` in the same
       * refinement that already validates chunk/span ranges here.
       */
      rangeSelectors: z.array(V2TextRangeSelectorSchema).max(32).optional(),
    })
    .strict()
    .superRefine((payload, ctx) => {
      const sourceLength = payload.source.text.length;
      const hardBreaks = payload.layout?.hardBreaks ?? [];
      let previousHardBreak = -1;
      for (const [index, offset] of hardBreaks.entries()) {
        if (offset >= sourceLength) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text hard break offset must point inside source text", path: ["layout", "hardBreaks", index] });
        }
        if (offset <= previousHardBreak) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text hard break offsets must be strictly increasing", path: ["layout", "hardBreaks", index] });
        }
        previousHardBreak = offset;
      }
      const chunkIds = new Set<string>();
      const spanIds = new Set<string>();
      for (const [index, chunk] of payload.chunks.entries()) {
        if (chunkIds.has(chunk.id)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate text chunk id: ${chunk.id}`, path: ["chunks", index, "id"] });
        }
        chunkIds.add(chunk.id);
        if (chunk.sourceRange.end > sourceLength) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text chunk range exceeds source text", path: ["chunks", index, "sourceRange"] });
        }
        for (const [spanIndex, span] of chunk.spans.entries()) {
          if (spanIds.has(span.id)) {
            ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate text span id: ${span.id}`, path: ["chunks", index, "spans", spanIndex, "id"] });
          }
          spanIds.add(span.id);
          if (span.sourceRange.end > sourceLength) {
            ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text span range exceeds source text", path: ["chunks", index, "spans", spanIndex, "sourceRange"] });
          }
        }
      }
      for (const [index, selector] of (payload.rangeSelectors ?? []).entries()) {
        if (selector.range !== "all" && selector.range.end > sourceLength) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Text range selector end exceeds source text", path: ["rangeSelectors", index, "range", "end"] });
        }
      }
    }),
}).strict();

export type V2TextRangeSelector = z.infer<typeof V2TextRangeSelectorSchema>;
export type V2TextRange = z.infer<typeof V2TextRangeSchema>;
export type V2TextFont = z.infer<typeof V2TextFontSchema>;
export type V2TextDecorationStyle = z.infer<typeof V2TextDecorationStyleSchema>;
export type V2TextLayout = z.infer<typeof V2TextLayoutSchema>;
export type V2TextSpan = z.infer<typeof V2TextSpanSchema>;
export type V2TextPath = z.infer<typeof V2TextPathSchema>;
export type V2TextChunk = z.infer<typeof V2TextChunkSchema>;
export type V2TextSource = z.infer<typeof V2TextSourceSchema>;
export type V2TextLayer = z.infer<typeof V2TextLayerSchema>;
