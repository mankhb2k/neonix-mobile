import { describe, expect, it } from "vitest";
import { V2GroupLayerSchema } from "../src/v2/layers/group";
import { V2Render3DSchema } from "../src/v2/render3d";

const baseGroup = {
  type: "group" as const,
  id: "group-3d",
  parentLayerId: null,
  order: 0,
  frame: { width: 800, height: 600 },
  transform: {
    translate: { x: 0, y: 0, z: 0 },
    scale: { x: 1, y: 1, z: 1 },
    rotate: { x: 0, y: 0, z: 0 },
    skew: { x: 0, y: 0 },
    anchor: { x: 0, y: 0, z: 0 },
  },
  timing: { start: 0, duration: 1000 },
};

describe("Protocol V2 3D rendering context", () => {
  it("accepts a local perspective and preserve-3d group boundary", () => {
    const render3d = V2Render3DSchema.parse({
      transformStyle: "preserve-3d",
      perspective: { distance: 800, origin: { x: 400, y: 300 } },
    });
    expect(render3d.perspective?.distance).toBe(800);

    const group = V2GroupLayerSchema.parse({
      ...baseGroup,
      render3d,
    });
    expect(group.render3d?.transformStyle).toBe("preserve-3d");
  });

  it("accepts backface visibility on a layer", () => {
    const group = V2GroupLayerSchema.parse({
      ...baseGroup,
      backfaceVisibility: "hidden",
    });
    expect(group.backfaceVisibility).toBe("hidden");
  });

  it("rejects a non-positive local perspective distance", () => {
    expect(() =>
      V2Render3DSchema.parse({
        transformStyle: "flat",
        perspective: { distance: 0, origin: { x: 0, y: 0 } },
      }),
    ).toThrow();
  });
});
