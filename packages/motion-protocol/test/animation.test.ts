import { describe, expect, it } from "vitest";
import { MotionProtocolV2Schema } from "../src/v2/project";
import { V2TrackListSchema, V2TrackSchema, V2LayerTrackSchema } from "../src/v2/animation";

const baseShape = {
  type: "shape" as const,
  id: "card",
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
  opacity: 1,
  timing: { start: 0, duration: 2000 },
  style: { fill: "#101820" },
  payload: { shape: "rectangle" as const },
};

const baseProject = (layer: unknown) => ({
  format: "motion-protocol" as const,
  formatVersion: 2 as const,
  id: "animated-v2",
  composition: {
    width: 320,
    height: 180,
    fps: 30,
    background: "#000000",
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
  layers: [layer],
  audio: { sampleRate: 48000, tracks: [] },
});

describe("Protocol V2 keyframe tracks", () => {
  it("accepts typed, strictly ordered keyframes", () => {
    const track = V2TrackSchema.parse({
      id: "move-x",
      path: "transform.translate.x",
      keyframes: [
        { time: 0, value: { type: "number", value: -120 } },
        { time: 600, value: { type: "number", value: 0 }, easing: { type: "linear" } },
      ],
    });
    expect(track.keyframes).toHaveLength(2);
    expect(() => V2TrackSchema.parse({
      ...track,
      keyframes: [track.keyframes[1], track.keyframes[0]],
    })).toThrow(/strictly increasing/);
  });

  it("rejects duplicate track ids and property paths per layer", () => {
    const track = {
      id: "opacity",
      path: "opacity",
      keyframes: [{ time: 0, value: { type: "number", value: 1 } }],
    };
    expect(() => V2TrackListSchema.parse([track, { ...track }])).toThrow(/Duplicate layer track id/);
    expect(() => V2TrackListSchema.parse([track, { ...track, id: "opacity-2" }])).toThrow(/Duplicate animated property path/);
  });

  it("accepts multiple layer-local animation tracks on different property paths", () => {
    const layer = {
      ...baseShape,
      tracks: [
        {
          id: "fade",
          path: "opacity",
          keyframes: [
            { time: 0, value: { type: "number" as const, value: 0 } },
            { time: 1000, value: { type: "number" as const, value: 1 } },
          ],
        },
        {
          id: "spin",
          path: "transform.rotate.z",
          keyframes: [{ time: 0, value: { type: "number" as const, value: 0 } }],
        },
      ],
    };
    expect(MotionProtocolV2Schema.parse(baseProject(layer)).layers[0]).toMatchObject({
      tracks: layer.tracks,
    });
  });

  it("rejects unknown paths, mismatched value types, and out-of-range local times", () => {
    const invalid = (track: unknown) =>
      MotionProtocolV2Schema.parse(baseProject({ ...baseShape, tracks: [track] }));
    expect(() => invalid({
      id: "unknown",
      path: "style.notAProperty",
      keyframes: [{ time: 0, value: { type: "number", value: 1 } }],
    })).toThrow(/animatable property/);
    expect(() => invalid({
      id: "wrong-kind",
      path: "opacity",
      keyframes: [{ time: 0, value: { type: "color", value: [1, 1, 1, 1] } }],
    })).toThrow(/value type does not match/);
    expect(() => invalid({
      id: "late",
      path: "opacity",
      keyframes: [{ time: 2100, value: { type: "number", value: 1 } }],
    })).toThrow(/cannot exceed layer duration/);
  });
});

describe("Protocol V2 layer-track keyframe anchors", () => {
  it("accepts a bare number, a start anchor, and an end anchor as equivalent keyframe time shapes", () => {
    for (const time of [600, { anchor: "start" as const, offsetMs: 600 }, { anchor: "end" as const, offsetMs: 400 }]) {
      const track = V2LayerTrackSchema.parse({
        id: "move-x",
        path: "transform.translate.x",
        keyframes: [
          { time: 0, value: { type: "number", value: -120 } },
          { time, value: { type: "number", value: 0 } },
        ],
      });
      expect(track.keyframes[1]?.time).toEqual(time);
    }
  });

  it("rejects an end-anchored keyframe combined with a looping animation at the schema level", () => {
    expect(() => V2LayerTrackSchema.parse({
      id: "bad-loop",
      path: "opacity",
      keyframes: [{ time: { anchor: "end", offsetMs: 100 }, value: { type: "number", value: 1 } }],
      animation: {
        durationMs: 500,
        delayMs: 0,
        iterations: "infinite",
        direction: "normal",
        fillMode: "none",
        playState: "running",
      },
    })).toThrow(/cannot be combined with a looping animation/);
  });
});
