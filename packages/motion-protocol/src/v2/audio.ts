import { z } from "zod";
import {
  V2FiniteNumberSchema,
  V2IdSchema,
  V2MillisecondsSchema,
  V2PositiveMillisecondsSchema,
  V2PositiveNumberSchema,
} from "./common";

export const V2AudioFadeCurveSchema = z.enum(["linear", "equal-power"]);

export const V2AudioFadeSchema = z
  .object({
    // A zero-length fade is the explicit "disabled" state. Keeping the
    // object present lets editors expose fade controls without an add/remove
    // toggle while preserving a no-op audio mix by default.
    /** Fade duration in milliseconds. */
    duration: V2MillisecondsSchema,
    curve: V2AudioFadeCurveSchema,
  })
  .strict();

/**
 * Per-input controls shared by embedded video audio and standalone clips.
 * Timing/source identity live with their respective authoring objects.
 */
export const V2EmbeddedVideoAudioSchema = z
  .object({
    enabled: z.boolean(),
    /** JSON omission means unity gain; editors may still persist an explicit value. */
    gainDb: V2FiniteNumberSchema.default(0),
    pan: V2FiniteNumberSchema.min(-1).max(1).default(0),
    fadeIn: V2AudioFadeSchema.optional(),
    fadeOut: V2AudioFadeSchema.optional(),
  })
  .strict();

export const V2AudioClipSchema = z
  .object({
    id: V2IdSchema,
    assetId: V2IdSchema,
    timing: z
      .object({
        start: V2MillisecondsSchema,
        duration: V2PositiveMillisecondsSchema,
      })
      .strict(),
    trim: z
      .object({
        start: V2MillisecondsSchema,
        end: V2PositiveMillisecondsSchema.optional(),
      })
      .strict(),
    playbackRate: V2PositiveNumberSchema,
    /** `false` keeps the clip on the timeline but makes its mix input silent. */
    enabled: z.boolean().default(true),
    /** JSON omission means unity gain. */
    gainDb: V2FiniteNumberSchema.default(0),
    pan: V2FiniteNumberSchema.min(-1).max(1).default(0),
    fadeIn: V2AudioFadeSchema.optional(),
    fadeOut: V2AudioFadeSchema.optional(),
  })
  .strict()
  .superRefine((clip, ctx) => {
    if (clip.trim.end !== undefined && clip.trim.end <= clip.trim.start) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Audio trim end must be greater than trim start",
        path: ["trim", "end"],
      });
    }
    if (
      clip.trim.end !== undefined &&
      clip.timing.duration * clip.playbackRate >
        clip.trim.end - clip.trim.start + Number.EPSILON
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Audio clip duration cannot exceed its bounded trim range at the selected playback rate",
        path: ["timing", "duration"],
      });
    }
    for (const [field, fade] of [
      ["fadeIn", clip.fadeIn],
      ["fadeOut", clip.fadeOut],
    ] as const) {
      if (fade && fade.duration > clip.timing.duration) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Audio ${field} duration cannot exceed clip duration`,
          path: [field, "duration"],
        });
      }
    }
  });

export const V2AudioTrackSchema = z
  .object({
    id: V2IdSchema,
    /** JSON omission means unity gain. */
    gainDb: V2FiniteNumberSchema.default(0),
    pan: V2FiniteNumberSchema.min(-1).max(1),
    muted: z.boolean(),
    clips: z.array(V2AudioClipSchema),
  })
  .strict();

export const V2AudioDomainSchema = z
  .object({
    sampleRate: z.literal(48000),
    tracks: z.array(V2AudioTrackSchema),
  })
  .strict();

export type V2AudioFadeCurve = z.infer<typeof V2AudioFadeCurveSchema>;
export type V2AudioFade = z.infer<typeof V2AudioFadeSchema>;
export type V2EmbeddedVideoAudio = z.infer<typeof V2EmbeddedVideoAudioSchema>;
export type V2AudioClip = z.infer<typeof V2AudioClipSchema>;
export type V2AudioTrack = z.infer<typeof V2AudioTrackSchema>;
export type V2AudioDomain = z.infer<typeof V2AudioDomainSchema>;
