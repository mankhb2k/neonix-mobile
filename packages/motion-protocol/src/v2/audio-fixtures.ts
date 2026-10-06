import type { V2AudioClip, V2AudioDomain, V2AudioTrack } from "./audio";
import type { V2AudioAsset, V2VideoAsset } from "./assets";
import type { MotionProtocolV2 } from "./types";

const MUSIC_ASSET: V2AudioAsset = {
  id: "music-mbb-island-tropical",
  kind: "audio",
  uri: "/preview/audio/Music-MBB-Island-Tropical_128k.mp3",
  mimeType: "audio/mpeg",
  duration: 124_551.837,
  sampleRate: 44100,
  channels: 2,
};

const VIDEO_AUDIO_ASSET: V2VideoAsset = {
  id: "example-video-audio-source",
  kind: "video",
  uri: "/preview/video/demo-video.mp4",
  mimeType: "video/mp4",
  width: 1920,
  height: 1080,
  duration: 60_500,
  fps: 30,
  audio: {
    uri: "/preview/audio/Music-MBB-Island-Tropical_128k.mp3",
    mimeType: "audio/mpeg",
    duration: 60_500,
    sampleRate: 48000,
    channels: 2,
  },
};

function clip(id: string, overrides: Partial<V2AudioClip> = {}): V2AudioClip {
  const { timing, trim, fadeIn, fadeOut, ...otherOverrides } = overrides;
  return {
    id,
    assetId: MUSIC_ASSET.id,
    timing: timing ?? { start: 0, duration: 4000 },
    trim: trim ?? { start: 0 },
    playbackRate: 1,
    enabled: true,
    gainDb: 0,
    pan: 0,
    ...otherOverrides,
    ...(fadeIn ? { fadeIn } : {}),
    ...(fadeOut ? { fadeOut } : {}),
  };
}

function track(
  id: string,
  clips: V2AudioClip[],
  overrides: Partial<V2AudioTrack> = {},
): V2AudioTrack {
  return { id, gainDb: 0, pan: 0, muted: false, clips, ...overrides };
}

function audioProject(
  id: string,
  tracks: V2AudioTrack[],
  assets: MotionProtocolV2["assets"] = [MUSIC_ASSET],
): MotionProtocolV2 {
  const audio: V2AudioDomain = { sampleRate: 48000, tracks };
  return {
    format: "motion-protocol",
    formatVersion: 2,
    id,
    composition: {
      width: 1920,
      height: 1080,
      fps: 30,
      background: "#101820",
      colorSpace: "srgb",
      view: {
        projection: { kind: "orthographic", zoom: 1, near: 1, far: 4000 },
        transform: {
          translate: { x: 0, y: 0, z: 0 },
          rotate: { x: 0, y: 0, z: 0 },
        },
      },
    },
    assets,
    layers: [],
    audio,
  };
}

export type V2AudioFixture = {
  id: string;
  label: string;
  hint: string;
  project: MotionProtocolV2;
  previewTime?: number;
};

export const V2_AUDIO_FIXTURES: V2AudioFixture[] = [
  { id: "audio.asset", label: "Audio / asset", hint: "Local MP3 metadata is referenced by an immutable V2 audio asset.", project: audioProject("preview-audio-asset-v2", []) },
  { id: "audio.timing", label: "Audio / timing", hint: "The clip starts at 0.5 seconds and occupies four seconds of composition time.", project: audioProject("preview-audio-timing-v2", [track("timing-track", [clip("timing-clip", { timing: { start: 500, duration: 4000 } })])]), previewTime: 0.5 },
  { id: "audio.trim", label: "Audio / trim", hint: "The composition clip uses source seconds 8 through 14 from the MP3.", project: audioProject("preview-audio-trim-v2", [track("trim-track", [clip("trim-clip", { timing: { start: 1000, duration: 5000 }, trim: { start: 8000, end: 14000 } })])]), previewTime: 1 },
  { id: "audio.gain", label: "Audio / gain", hint: "Independent -6 dB track and clip gains combine to a clearly audible -12 dB attenuation over ten seconds.", project: audioProject("preview-audio-gain-v2", [track("gain-track", [clip("gain-clip", { timing: { start: 0, duration: 10000 }, gainDb: -6 })], { gainDb: -6 })]) },
  { id: "audio.pan", label: "Audio / pan", hint: "The ten-second clip is hard-panned fully right with the normalized input +1.", project: audioProject("preview-audio-pan-v2", [track("pan-track", [clip("pan-clip", { timing: { start: 0, duration: 10000 } })], { pan: 1 })]) },
  { id: "audio.fade", label: "Audio / fade", hint: "A centered twenty-second excerpt uses four-second linear fade-in and equal-power fade-out ramps.", project: audioProject("preview-audio-fade-v2", [track("fade-track", [clip("fade-clip", { timing: { start: 0, duration: 20000 }, trim: { start: 52000, end: 72000 }, fadeIn: { duration: 4000, curve: "linear" }, fadeOut: { duration: 4000, curve: "equal-power" } })])]), previewTime: 0 },
  { id: "audio.track.mute", label: "Audio / track mute", hint: "The track remains in the protocol but is muted without deleting its clip.", project: audioProject("preview-audio-track-mute-v2", [track("muted-track", [clip("muted-clip")], { muted: true })]) },
  { id: "audio.track.overlap", label: "Audio / overlapping clips", hint: "Two independent clips overlap on one track and will later become two mix inputs.", project: audioProject("preview-audio-overlap-v2", [track("overlap-track", [clip("overlap-a", { timing: { start: 0, duration: 5000 } }), clip("overlap-b", { timing: { start: 3000, duration: 5000 }, trim: { start: 12000, end: 17000 } })])]), previewTime: 4 },
  { id: "audio.video-source", label: "Audio / video source", hint: "The first ten seconds of a video's audio stream are referenced explicitly without creating a visual layer.", project: audioProject("preview-audio-video-source-v2", [track("video-audio-track", [clip("video-audio-clip", { assetId: VIDEO_AUDIO_ASSET.id, timing: { start: 0, duration: 10000 }, trim: { start: 0, end: 10000 } })])], [VIDEO_AUDIO_ASSET]) },
  { id: "audio.mix.two-tracks", label: "Audio mix / two tracks", hint: "Dialogue and background music occupy separate tracks and overlap from 2 to 8 seconds; the compiler preserves both mix inputs.", project: audioProject("preview-audio-mix-two-tracks-v2", [track("dialogue", [clip("dialogue-clip", { timing: { start: 0, duration: 8000 }, trim: { start: 4000, end: 12000 }, gainDb: -3 })]), track("music", [clip("music-bed", { timing: { start: 2000, duration: 10000 }, trim: { start: 24000, end: 34000 }, gainDb: -12 })])]), previewTime: 4 },
  { id: "audio.mix.video-plus-music", label: "Audio mix / video + music", hint: "A video clip contributes its embedded audio while a separate music bed plays underneath; Runtime emits two independent inputs.", project: audioProject("preview-audio-mix-video-plus-music-v2", [track("video-audio", [clip("video-01-audio", { assetId: VIDEO_AUDIO_ASSET.id, timing: { start: 0, duration: 10000 }, trim: { start: 0, end: 10000 }, gainDb: -3 })]), track("music", [clip("music-01", { timing: { start: 0, duration: 10000 }, trim: { start: 36000, end: 46000 }, gainDb: -14 })])], [VIDEO_AUDIO_ASSET, MUSIC_ASSET]), previewTime: 4 },
];
