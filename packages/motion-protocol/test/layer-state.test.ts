import { describe, expect, it } from "vitest";
import { V2LayerBaseSchema } from "../src/v2/layers/base";

const baseLayer = {
  id: "layer-state",
  parentLayerId: null,
  order: 0,
  frame: { width: 320, height: 180 },
  transform: {
    translate: { x: 0, y: 0, z: 0 },
    scale: { x: 1, y: 1, z: 1 },
    rotate: { x: 0, y: 0, z: 0 },
    skew: { x: 0, y: 0 },
    anchor: { x: 0, y: 0, z: 0 },
  },
  timing: { start: 0, duration: 1000 },
};

describe("Protocol V2 editor layer state", () => {
  it("accepts enabled and preserves an explicitly disabled layer", () => {
    const parsed = V2LayerBaseSchema.parse({ ...baseLayer, enabled: false });
    expect(parsed.enabled).toBe(false);
  });

  it("keeps enabled optional for existing static documents", () => {
    const parsed = V2LayerBaseSchema.parse(baseLayer);
    expect(parsed).not.toHaveProperty("enabled");
  });

  it("uses SVG visibility as a separate semantic from editor enabled state", () => {
    expect(V2LayerBaseSchema.parse(baseLayer)).not.toHaveProperty("visibility");
    expect(V2LayerBaseSchema.parse({ ...baseLayer, visibility: "hidden" }).visibility).toBe("hidden");
    expect(V2LayerBaseSchema.parse({ ...baseLayer, visibility: "collapse" }).visibility).toBe("collapse");
  });
});
