import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import * as Protocol from "../src/index";
import * as V2 from "../src/v2/index";

const validProject = {
  format: "motion-protocol" as const,
  formatVersion: 2 as const,
  id: "root-v2",
  composition: {
    width: 320,
    height: 180,
    fps: 30,
    background: "#101820",
    colorSpace: "srgb" as const,
    view: {
      projection: { kind: "orthographic" as const, zoom: 1, near: 1, far: 4000 },
      transform: {
        translate: { x: 0, y: 0, z: 0 },
        rotate: { x: 0, y: 0, z: 0 },
      },
    },
  },
  assets: [],
  layers: [],
  audio: { sampleRate: 48000, tracks: [] },
};

describe("Protocol root API V2", () => {
  it("exports the V2 schema and version", () => {
    expect(Protocol.MOTION_FORMAT_VERSION).toBe(2);
    expect(Protocol.MotionProtocolV2Schema.safeParse(validProject).success).toBe(true);
    expect(Object.keys(Protocol)).toContain("MotionProtocolV2Schema");
  });

  it("keeps root and /v2 exports aligned and retires ./runtime", () => {
    expect(V2.MotionProtocolV2Schema).toBe(Protocol.MotionProtocolV2Schema);
    const packageJson = JSON.parse(
      readFileSync(join(__dirname, "..", "package.json"), "utf8"),
    ) as { exports: Record<string, string> };
    expect(Object.keys(packageJson.exports).sort()).toEqual([".", "./v2"]);
    expect(packageJson.exports["./runtime"]).toBeUndefined();
  });

  it("parses and serializes only Protocol V2", () => {
    expect(Protocol.parseMotionProtocol(validProject)).toEqual(validProject);
    expect(JSON.parse(Protocol.serializeMotionProtocol(validProject))).toEqual(validProject);
    expect(() => Protocol.parseMotionProtocol({
      format: "motion-project",
      formatVersion: 1,
    })).toThrow();
  });

  it("does not expose retired V1 or Runtime IR symbols", () => {
    const exported = new Set(Object.keys(Protocol));
    for (const name of [
      "MotionProjectV1",
      "MotionProjectSchema",
      "parseMotionProjectV1",
      "serializeMotionProjectV1",
      "MotionRuntimeProjectSchema",
      "AssetSchema",
    ]) {
      expect(exported.has(name), `${name} must not be public`).toBe(false);
    }
  });
});
