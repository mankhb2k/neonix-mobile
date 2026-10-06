import { MotionProtocolV2Schema, type MotionProtocolV2 } from "./v2";

type JsonRecord = Record<string, unknown>;

export type ProtocolMigrationDiagnostic = {
  code: "legacy_video_muted" | "removed_loop" | "clamped_video_duration" | "renamed_track_playback";
  severity: "warning";
  path: readonly (string | number)[];
  message: string;
};

export type MotionProtocolV2Migration = {
  input: unknown;
  diagnostics: ProtocolMigrationDiagnostic[];
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * One-way migration for persisted V2 documents written before embedded video
 * audio was explicit, before loop was retired, or while track animation
 * policies were named `playback`. The returned input is safe to pass to the
 * strict V2 schema; the original value is never mutated.
 */
export function migrateMotionProtocolV2(input: unknown): MotionProtocolV2Migration {
  if (!isRecord(input)) {
    return { input, diagnostics: [] };
  }

  const diagnostics: ProtocolMigrationDiagnostic[] = [];
  const assetDurations = new Map<string, number>();
  if (Array.isArray(input.assets)) {
    for (const asset of input.assets) {
      if (isRecord(asset) && typeof asset.id === "string" && typeof asset.duration === "number" && Number.isFinite(asset.duration)) {
        assetDurations.set(asset.id, asset.duration);
      }
    }
  }
  const layersWithAnimation = Array.isArray(input.layers)
    ? input.layers.map((layer, layerIndex) => {
        if (!isRecord(layer) || !Array.isArray(layer.tracks)) return layer;
        let changed = false;
        const tracks = layer.tracks.map((track, trackIndex) => {
          if (!isRecord(track) || !Object.prototype.hasOwnProperty.call(track, "playback")) return track;
          changed = true;
          const migratedTrack = { ...track };
          if (!Object.prototype.hasOwnProperty.call(track, "animation")) {
            migratedTrack.animation = track.playback;
          }
          delete migratedTrack.playback;
          diagnostics.push({
            code: "renamed_track_playback",
            severity: "warning",
            path: ["layers", layerIndex, "tracks", trackIndex, "playback"],
            message: Object.prototype.hasOwnProperty.call(track, "animation")
              ? "Dropped legacy track.playback because track.animation is canonical."
              : "Renamed legacy track.playback to track.animation; save the project to persist the new shape.",
          });
          return migratedTrack;
        });
        return changed ? { ...layer, tracks } : layer;
      })
    : input.layers;
  const layers = Array.isArray(layersWithAnimation)
    ? layersWithAnimation.map((layer, layerIndex) => {
        if (!isRecord(layer) || layer.type !== "video" || !isRecord(layer.payload)) return layer;

        let payload = layer.payload;
        if (Object.prototype.hasOwnProperty.call(payload, "muted")) {
          payload = { ...payload };
          const muted = payload.muted === true;
          delete payload.muted;
          if (!isRecord(payload.audio)) {
            payload.audio = { enabled: !muted, gainDb: 0 };
          }
          diagnostics.push({
            code: "legacy_video_muted",
            severity: "warning",
            path: ["layers", layerIndex, "payload", "muted"],
            message: "Migrated legacy video payload.muted to payload.audio.enabled; save the project to persist the new shape.",
          });
        }
        const removedVideoLoop = Object.prototype.hasOwnProperty.call(payload, "loop");
        if (removedVideoLoop) {
          if (payload === layer.payload) payload = { ...payload };
          delete payload.loop;
          diagnostics.push({
            code: "removed_loop",
            severity: "warning",
            path: ["layers", layerIndex, "payload", "loop"],
            message: "Removed the retired video loop field; duplicate the clip when repeated playback is needed.",
          });
        }
        let migratedLayer: JsonRecord = payload === layer.payload ? layer : { ...layer, payload };
        if (removedVideoLoop && isRecord(layer.timing) && typeof layer.timing.duration === "number") {
          const sourceDuration = typeof payload.assetId === "string" ? assetDurations.get(payload.assetId) : undefined;
          const trimStart = typeof payload.trimStart === "number" ? payload.trimStart : 0;
          const trimEnd = typeof payload.trimEnd === "number" ? Math.min(payload.trimEnd, sourceDuration ?? payload.trimEnd) : sourceDuration;
          const availableDuration = trimEnd === undefined ? undefined : trimEnd - trimStart;
          if (availableDuration !== undefined && availableDuration > 0 && layer.timing.duration > availableDuration) {
            migratedLayer = {
              ...migratedLayer,
              timing: { ...layer.timing, duration: availableDuration },
            };
            diagnostics.push({
              code: "clamped_video_duration",
              severity: "warning",
              path: ["layers", layerIndex, "timing", "duration"],
              message: "Clamped a looping video to its real source duration because protocol V2 no longer supports looping.",
            });
          }
        }
        return migratedLayer;
      })
    : input.layers;

  const audio = isRecord(input.audio) && Array.isArray(input.audio.tracks)
    ? {
        ...input.audio,
        tracks: input.audio.tracks.map((track, trackIndex) => {
          if (!isRecord(track) || !Array.isArray(track.clips)) return track;
          return {
            ...track,
            clips: track.clips.map((clip, clipIndex) => {
              if (!isRecord(clip) || !Object.prototype.hasOwnProperty.call(clip, "loop")) return clip;
              const migratedClip = { ...clip };
              delete migratedClip.loop;
              diagnostics.push({
                code: "removed_loop",
                severity: "warning",
                path: ["audio", "tracks", trackIndex, "clips", clipIndex, "loop"],
                message: "Removed the retired audio loop field; duplicate the clip when repeated playback is needed.",
              });
              return migratedClip;
            }),
          };
        }),
      }
    : input.audio;

  if (layers === input.layers && audio === input.audio) {
    return { input, diagnostics };
  }

  return { input: { ...input, layers, audio }, diagnostics };
}

export function parseMotionProtocolV2WithMigration(input: unknown): {
  project: MotionProtocolV2;
  diagnostics: ProtocolMigrationDiagnostic[];
} {
  const migrated = migrateMotionProtocolV2(input);
  return {
    project: MotionProtocolV2Schema.parse(migrated.input),
    diagnostics: migrated.diagnostics,
  };
}
