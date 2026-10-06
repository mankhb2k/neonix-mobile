import { describe, expect, it } from "vitest";
import { V2TextLayerSchema } from "../src/v2/layers/text";

const BASE_LAYER = {
  id: "title",
  parentLayerId: null,
  order: 0,
  frame: { width: 200, height: 80 },
  transform: {
    translate: { x: 0, y: 0, z: 0 },
    scale: { x: 1, y: 1, z: 1 },
    rotate: { x: 0, y: 0, z: 0 },
    skew: { x: 0, y: 0 },
    anchor: { x: 0, y: 0, z: 0 },
  },
  opacity: 1,
  timing: { start: 0, duration: 1000 },
  type: "text" as const,
};

const TEXT_LAYER = {
  ...BASE_LAYER,
  payload: {
    source: { text: "A fi", language: "en" },
    chunks: [{
      id: "chunk-1",
      sourceRange: { start: 0, end: 4 },
      textAnchor: "middle" as const,
      spans: [{
        id: "span-1",
        sourceRange: { start: 0, end: 4 },
        font: { families: ["Noto Sans", "sans-serif"], size: 32, weight: 400, style: "normal" as const },
        fill: "#ffffffff",
        letterSpacing: { value: 1, unit: "px" as const },
      }],
    }],
  },
};

describe("Protocol V2 semantic SVG text", () => {
  it("accepts text chunks, tspan ranges, SVG font properties and paint", () => {
    expect(V2TextLayerSchema.parse(TEXT_LAYER)).toEqual(TEXT_LAYER);
  });

  it("accepts textPath and editor-safe UTF-16 ranges", () => {
    const layer = {
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        source: { text: "A😀", language: "en", direction: "ltr" as const },
        chunks: [{
          ...TEXT_LAYER.payload.chunks[0],
          sourceRange: { start: 0, end: 3 },
          textPath: { pathId: "baseline", startOffset: { value: 12, unit: "px" as const } },
          spans: [{ ...TEXT_LAYER.payload.chunks[0].spans[0], sourceRange: { start: 0, end: 3 } }],
        }],
      },
    };
    expect(V2TextLayerSchema.parse(layer)).toEqual(layer);
  });

  it("rejects overlapping spans and ranges outside source text", () => {
    expect(() => V2TextLayerSchema.parse({
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        chunks: [{
          ...TEXT_LAYER.payload.chunks[0],
          spans: [
            TEXT_LAYER.payload.chunks[0].spans[0],
            { ...TEXT_LAYER.payload.chunks[0].spans[0], id: "span-2", sourceRange: { start: 3, end: 4 } },
          ],
        }],
      },
    })).toThrow(/non-overlapping/);

    expect(() => V2TextLayerSchema.parse({
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        chunks: [{ ...TEXT_LAYER.payload.chunks[0], sourceRange: { start: 0, end: 99 } }],
      },
    })).toThrow(/exceeds source text/);
  });

  it("accepts the normalized text layout contract", () => {
    const layer = {
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        layout: {
          sizing: "fixed" as const,
          lineHeight: 40,
          contentWidth: 180,
          contentHeight: 60,
          contentOffsetX: 10,
          contentOffsetY: 8,
          textAlign: "center" as const,
          whiteSpace: "pre-wrap" as const,
          wrap: "none" as const,
          textOverflow: "clip" as const,
        },
      },
    };
    expect(V2TextLayerSchema.parse(layer)).toEqual(layer);
  });

  it("accepts ordered UTF-16 hard break offsets", () => {
    const layer = {
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        source: { text: "Video title\nline two", language: "en" },
        layout: {
          lineHeight: 40,
          textAlign: "left" as const,
          whiteSpace: "normal" as const,
          wrap: "word" as const,
          textOverflow: "clip" as const,
          hardBreaks: [11],
        },
      },
    };
    expect(V2TextLayerSchema.parse(layer).payload.layout?.hardBreaks).toEqual([11]);
  });

  it("rejects unsorted or out-of-range hard break offsets", () => {
    const layout = {
      lineHeight: 40,
      textAlign: "left" as const,
      whiteSpace: "normal" as const,
      wrap: "word" as const,
      textOverflow: "clip" as const,
    };
    expect(() => V2TextLayerSchema.parse({
      ...TEXT_LAYER,
      payload: { ...TEXT_LAYER.payload, source: { text: "A\nB" }, layout: { ...layout, hardBreaks: [2, 1] } },
    })).toThrow(/strictly increasing/);
    expect(() => V2TextLayerSchema.parse({
      ...TEXT_LAYER,
      payload: { ...TEXT_LAYER.payload, source: { text: "A\nB" }, layout: { ...layout, hardBreaks: [3] } },
    })).toThrow(/point inside source text/);
  });

  it("accepts every Protocol V2 textAlign value", () => {
    const values = ["start", "end", "left", "right", "center", "justify", "match-parent", "justify-all"] as const;
    for (const textAlign of values) {
      const layer = {
        ...TEXT_LAYER,
        payload: {
          ...TEXT_LAYER.payload,
          layout: {
            lineHeight: 40,
            textAlign,
            whiteSpace: "normal" as const,
            wrap: "word" as const,
            textOverflow: "clip" as const,
          },
        },
      };
      expect(V2TextLayerSchema.parse(layer).payload.layout?.textAlign).toBe(textAlign);
    }
  });

  it("accepts the three explicit text sizing modes", () => {
    for (const sizing of ["auto-width-height", "fixed-width-auto-height", "fixed"] as const) {
      const parsed = V2TextLayerSchema.parse({
        ...TEXT_LAYER,
        payload: {
          ...TEXT_LAYER.payload,
          layout: {
            sizing,
            lineHeight: 40,
            textAlign: "left" as const,
            whiteSpace: "normal" as const,
            wrap: "none" as const,
            textOverflow: "clip" as const,
          },
        },
      });
      expect(parsed.payload.layout?.sizing).toBe(sizing);
    }
  });

  it("accepts ellipsis when the layer provides a clipPath", () => {
    expect(V2TextLayerSchema.parse({
      ...TEXT_LAYER,
      clipPath: "title-clip",
      payload: {
        ...TEXT_LAYER.payload,
        layout: {
          lineHeight: 40,
          textAlign: "center" as const,
          whiteSpace: "nowrap" as const,
          wrap: "none" as const,
          textOverflow: "ellipsis" as const,
          maxLines: 1,
        },
      },
    })).toMatchObject({ clipPath: "title-clip" });
  });

  it("rejects an incomplete text layout payload", () => {
    expect(() => V2TextLayerSchema.parse({
      ...BASE_LAYER,
      payload: { source: { text: "A" }, layout: {} },
    })).toThrow();
  });

  it("accepts a typewriter rangeSelector template (expanded later by the compiler, not the schema)", () => {
    const layer = {
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        rangeSelectors: [
          {
            id: "typewriter",
            unit: "character" as const,
            range: "all" as const,
            stagger: { perUnitDelayMs: 40, direction: "forward" as const },
            track: {
              id: "reveal",
              path: "fillOpacity",
              keyframes: [
                { time: 0, value: { type: "number" as const, value: 0 } },
                { time: 50, value: { type: "number" as const, value: 1 } },
              ],
            },
          },
        ],
      },
    };
    expect(V2TextLayerSchema.parse(layer).payload.rangeSelectors).toHaveLength(1);
  });

  it("rejects a rangeSelector range that exceeds the source text", () => {
    expect(() => V2TextLayerSchema.parse({
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        rangeSelectors: [
          {
            id: "typewriter",
            unit: "character" as const,
            range: { start: 0, end: 99 },
            stagger: { perUnitDelayMs: 40, direction: "forward" as const },
            track: {
              id: "reveal",
              path: "fillOpacity",
              keyframes: [{ time: 0, value: { type: "number" as const, value: 1 } }],
            },
          },
        ],
      },
    })).toThrow(/exceeds source text/);
  });

  it("accepts an end-anchored keyframe inside a rangeSelector template track", () => {
    const layer = {
      ...TEXT_LAYER,
      payload: {
        ...TEXT_LAYER.payload,
        rangeSelectors: [
          {
            id: "typewriter-out",
            unit: "character" as const,
            range: "all" as const,
            stagger: { perUnitDelayMs: 40, direction: "reverse" as const },
            track: {
              id: "reveal-out",
              path: "fillOpacity",
              keyframes: [
                { time: { anchor: "start" as const, offsetMs: 0 }, value: { type: "number" as const, value: 1 } },
                { time: { anchor: "end" as const, offsetMs: 100 }, value: { type: "number" as const, value: 0 } },
              ],
            },
          },
        ],
      },
    };
    expect(V2TextLayerSchema.parse(layer).payload.rangeSelectors).toHaveLength(1);
  });
});
