import { describe, expect, it } from "vitest";
import { V2_AUDIO_FIXTURES } from "../src/v2/audio-fixtures";
import { MotionProtocolV2Schema } from "../src/v2/project";

describe("Protocol V2 audio fixture catalog", () => {
  it("has parseable fixtures for the audio shapes", () => {
    expect(V2_AUDIO_FIXTURES.length).toBeGreaterThan(0);
    for (const fixture of V2_AUDIO_FIXTURES) {
      expect(MotionProtocolV2Schema.parse(fixture.project)).toEqual(fixture.project);
    }
  });

  it("uses the local MP3 asset and keeps audio separate from visual layers", () => {
    for (const fixture of V2_AUDIO_FIXTURES.filter((item) => item.id !== "audio.video-source")) {
      expect(fixture.project.layers).toEqual([]);
      expect(fixture.project.audio.sampleRate).toBe(48000);
      expect(fixture.project.assets.some((asset) => asset.kind === "audio" && asset.uri === "/preview/audio/Music-MBB-Island-Tropical_128k.mp3" && asset.mimeType === "audio/mpeg")).toBe(true);
    }
  });

  it("requires an explicit clip when a video asset contributes audio", () => {
    const fixture = V2_AUDIO_FIXTURES.find((item) => item.id === "audio.video-source");
    expect(fixture?.project.assets[0]).toMatchObject({ kind: "video" });
    expect(fixture?.project.audio.tracks[0]?.clips[0]?.assetId).toBe("example-video-audio-source");
  });
});
