import { describe, expect, it } from "vitest";
import { V2FilterSchema } from "../src/v2/filter";

describe("Protocol V2 SVG filter primitives", () => {
  it("accepts SVG filter graph primitives with explicit inputs and results", () => {
    const filter = {
      id: "outer-glow",
      filterUnits: "objectBoundingBox",
      primitiveUnits: "userSpaceOnUse",
      colorInterpolationFilters: "linearRGB",
      primitives: [
        { id: "blur", type: "feGaussianBlur", in: "SourceAlpha", stdDeviation: { x: 12, y: 12 }, result: "blurred" },
        { id: "color", type: "feFlood", color: "#00e5ff", opacity: 0.75, result: "flooded" },
        { id: "composite", type: "feComposite", in: "flooded", in2: "blurred", operator: "in", result: "glow" },
        { id: "merge", type: "feMerge", nodes: [{ in: "glow" }, { in: "SourceGraphic" }] },
      ],
    } as const;
    expect(V2FilterSchema.parse(filter)).toEqual(filter);
  });

  it("rejects duplicate SVG filter results and malformed convolution kernels", () => {
    expect(() => V2FilterSchema.parse({
      id: "duplicate-result",
      primitives: [
        { id: "a", type: "feFlood", color: "#000000", result: "same" },
        { id: "b", type: "feFlood", color: "#ffffff", result: "same" },
      ],
    })).toThrow(/Duplicate filter result/);
    expect(() => V2FilterSchema.parse({
      id: "bad-convolve",
      primitives: [{ id: "kernel", type: "feConvolveMatrix", order: { x: 3, y: 3 }, kernelMatrix: [1] }],
    })).toThrow(/kernelMatrix length/);
  });

  it("requires feGaussianBlur/feDropShadow stdDeviation.x and .y tracks to animate in lockstep", () => {
    // The runtime only executes an isotropic blur/shadow radius, so an
    // independently-animated x or y would make ANISOTROPIC_FILTER_UNSUPPORTED
    // depend on the sampled time instead of failing at parse time.
    const base = {
      id: "pulsing-glow",
      primitives: [{ id: "blur1", type: "feGaussianBlur" as const, stdDeviation: { x: 4, y: 4 } }],
    };
    const track = (path: string, value: number) => ({ id: path, path, keyframes: [{ time: 0, value: { type: "number" as const, value } }] });

    expect(() => V2FilterSchema.parse({
      ...base,
      tracks: [track("primitives.blur1.stdDeviation.x", 4)],
    })).toThrow(/requires animating both x and y together/);

    expect(() => V2FilterSchema.parse({
      ...base,
      tracks: [
        track("primitives.blur1.stdDeviation.x", 4),
        { id: "y", path: "primitives.blur1.stdDeviation.y", keyframes: [{ time: 0, value: { type: "number" as const, value: 8 } }] },
      ],
    })).toThrow(/must share identical keyframes/);

    const synced = {
      ...base,
      tracks: [track("primitives.blur1.stdDeviation.x", 4), track("primitives.blur1.stdDeviation.y", 4)],
    };
    expect(V2FilterSchema.parse(synced)).toMatchObject(synced);
  });
});
