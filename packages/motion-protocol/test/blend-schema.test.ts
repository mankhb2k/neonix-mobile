import { describe, expect, it } from "vitest";
import {
  V2BlendModeSchema,
  V2CompositeSchema,
  V2IsolationModeSchema,
} from "../src/v2/layers/base";

const cssBlendModes = [
  "normal",
  "darken",
  "multiply",
  "color-burn",
  "lighten",
  "screen",
  "color-dodge",
  "overlay",
  "soft-light",
  "hard-light",
  "difference",
  "exclusion",
  "hue",
  "saturation",
  "color",
  "luminosity",
] as const;

describe("Protocol V2 CSS blend mode schema", () => {
  it("accepts every CSS Compositing and Blending Level 1 blend name", () => {
    for (const mode of cssBlendModes) {
      expect(V2BlendModeSchema.parse(mode)).toBe(mode);
    }
  });

  it("rejects the non-CSS add alias", () => {
    expect(() => V2BlendModeSchema.parse("add")).toThrow();
  });

  it("represents isolation separately from blend mode", () => {
    expect(V2IsolationModeSchema.parse("auto")).toBe("auto");
    expect(V2IsolationModeSchema.parse("isolate")).toBe("isolate");
    expect(
      V2CompositeSchema.parse({ blendMode: "overlay", isolation: "isolate" }),
    ).toEqual({ blendMode: "overlay", isolation: "isolate" });
  });
});
