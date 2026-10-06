import { describe, expect, it } from "vitest";
import {
  MotionProtocolV2Schema,
  V2ClipPathSchema,
  V2MaskSchema,
  V2MaskLayerSchema,
} from "../src/index";

const base = {
  format: "motion-protocol" as const,
  formatVersion: 2 as const,
  id: "clip-mask-schema",
  composition: {
    width: 320,
    height: 240,
    fps: 30,
    background: "#101820",
    colorSpace: "srgb" as const,
    view: {
      projection: { kind: "orthographic" as const, zoom: 1, near: 1, far: 1000 },
      transform: { translate: { x: 0, y: 0, z: 0 }, rotate: { x: 0, y: 0, z: 0 } },
    },
  },
  assets: [],
  layers: [],
  audio: { sampleRate: 48000, tracks: [] },
};

describe("Protocol V2 SVG clipPath and mask definitions", () => {
  it("keeps SVG clipPath units and geometry semantic", () => {
    const clip = V2ClipPathSchema.parse({
      id: "clip",
      clipPathUnits: "objectBoundingBox",
      children: [{ type: "ellipse", cx: 0.5, cy: 0.5, rx: 0.5, ry: 0.5 }],
    });
    expect(clip.clipPathUnits).toBe("objectBoundingBox");
    expect(clip.children[0]?.type).toBe("ellipse");
  });

  it("keeps SVG mask units, region values and mask type semantic", () => {
    const mask = V2MaskSchema.parse({
      id: "mask",
      maskUnits: "objectBoundingBox",
      maskContentUnits: "userSpaceOnUse",
      maskType: "luminance",
      x: { value: -10, unit: "percent" },
      width: { value: 120, unit: "percent" },
      children: [{ type: "rect", x: 0, y: 0, width: 100, height: 100, fill: "#808080" }],
    });
    expect(mask.maskType).toBe("luminance");
    expect(mask.x).toEqual({ value: -10, unit: "percent" });
  });

  it("validates layer references against project definitions", () => {
    const project = MotionProtocolV2Schema.parse({
      ...base,
      clipPaths: [{ id: "clip", children: [{ type: "rect", x: 0, y: 0, width: 100, height: 100 }] }],
      masks: [{ id: "mask", children: [{ type: "rect", x: 0, y: 0, width: 100, height: 100 }] }],
    });
    expect(project.clipPaths?.[0]?.clipPathUnits).toBe("userSpaceOnUse");
    expect(project.masks?.[0]?.maskUnits).toBe("objectBoundingBox");
    expect(project.masks?.[0]?.maskContentUnits).toBe("userSpaceOnUse");
  });

  it("keeps CSS mask layer order and composite explicit", () => {
    expect(V2MaskLayerSchema.parse({ maskIds: ["a", "b"], mode: "alpha", composite: "exclude" })).toEqual({
      maskIds: ["a", "b"], mode: "alpha", composite: "exclude",
    });
  });

  it("keeps image mask coverage multiplier semantic", () => {
    const mask = V2MaskSchema.parse({
      id: "image-mask",
      maskType: "alpha",
      image: { type: "image", assetId: "asset", x: 0, y: 0, width: 100, height: 100, fit: "fill", opacity: 0.25 },
    });
    expect(mask.image?.opacity).toBe(0.25);
  });
});
