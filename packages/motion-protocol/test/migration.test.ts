import { describe, expect, it } from "vitest";
import { migrateMotionProtocolV2, parseMotionProtocolV2WithMigration } from "../src/migration";

const legacy = {
  format: "motion-protocol",
  formatVersion: 2,
  id: "legacy-video",
  composition: {
    width: 320,
    height: 180,
    fps: 30,
    background: "#000000",
    colorSpace: "srgb",
    view: {
      projection: { kind: "orthographic", zoom: 1, near: 1, far: 4000 },
      transform: { translate: { x: 0, y: 0, z: 0 }, rotate: { x: 0, y: 0, z: 0 } },
    },
  },
  assets: [{ id: "clip", kind: "video", uri: "/clip.mp4", mimeType: "video/mp4", duration: 2000, fps: 30 }],
  layers: [{
    id: "video",
    type: "video",
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
    payload: { assetId: "clip", muted: true },
  }],
  audio: { sampleRate: 48000, tracks: [] },
};

describe("Protocol V2 legacy migration", () => {
  it("maps legacy muted without mutating the input", () => {
    const result = migrateMotionProtocolV2(legacy);
    expect(result.input).not.toBe(legacy);
    expect((result.input as typeof legacy).layers[0]?.payload).toEqual({
      assetId: "clip",
      audio: { enabled: false, gainDb: 0 },
    });
    expect(result.diagnostics).toHaveLength(1);
    expect(legacy.layers[0]?.payload).toHaveProperty("muted", true);
  });

  it("parses the migrated document and returns its diagnostic", () => {
    const result = parseMotionProtocolV2WithMigration(legacy);
    expect(result.project.layers[0]).toMatchObject({ payload: { audio: { enabled: false, gainDb: 0 } } });
    expect(result.diagnostics[0]?.code).toBe("legacy_video_muted");
  });

  it("removes the retired loop fields from persisted video and audio clips", () => {
    const legacyWithLoop = {
      ...legacy,
      layers: [{
        ...legacy.layers[0],
        payload: { ...legacy.layers[0].payload, loop: true },
      }],
      assets: [
        ...legacy.assets,
        { id: "music", kind: "audio" as const, uri: "/music.mp3", mimeType: "audio/mpeg", duration: 4000, sampleRate: 48000, channels: 2 },
      ],
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          id: "music-track",
          gainDb: 0,
          pan: 0,
          muted: false,
          clips: [{
            id: "music-clip",
            assetId: "music",
            timing: { start: 0, duration: 2000 },
            trim: { start: 0, end: 2000 },
            playbackRate: 1,
            gainDb: 0,
            loop: true,
          }],
        }],
      },
    };

    const result = parseMotionProtocolV2WithMigration(legacyWithLoop);
    expect(result.project.layers[0]?.payload).not.toHaveProperty("loop");
    expect(result.project.audio.tracks[0]?.clips[0]).not.toHaveProperty("loop");
    expect(result.diagnostics.filter((item) => item.code === "removed_loop")).toHaveLength(2);
    expect(legacyWithLoop.layers[0]?.payload).toHaveProperty("loop", true);
    expect(legacyWithLoop.audio.tracks[0]?.clips[0]).toHaveProperty("loop", true);
  });

  it("renames legacy track playback metadata to animation", () => {
    const legacyWithTrackPlayback = structuredClone(legacy) as any;
    legacyWithTrackPlayback.layers[0].tracks = [{
      id: "opacity-track",
      path: "opacity",
      keyframes: [
        { time: 0, value: { type: "number", value: 0 } },
        { time: 1000, value: { type: "number", value: 1 } },
      ],
      playback: {
        durationMs: 1000,
        delayMs: 0,
        iterations: 1,
        direction: "normal",
        fillMode: "both",
        playState: "running",
      },
    }];

    const result = parseMotionProtocolV2WithMigration(legacyWithTrackPlayback);
    const track = result.project.layers[0]?.tracks?.[0];
    expect(track?.animation).toMatchObject({ durationMs: 1000, fillMode: "both" });
    expect(track).not.toHaveProperty("playback");
    expect(result.diagnostics.some((item) => item.code === "renamed_track_playback")).toBe(true);
    expect(legacyWithTrackPlayback.layers[0].tracks[0]).toHaveProperty("playback");
  });
});
