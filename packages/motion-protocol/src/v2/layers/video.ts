import { z } from "zod";
import { V2IdSchema, V2MillisecondsSchema, V2PositiveMillisecondsSchema, V2PositiveNumberSchema } from "../common";
import { V2LayerBaseSchema } from "./base";
import { V2EmbeddedVideoAudioSchema } from "../audio";

export const V2VideoFitSchema = z.enum(["contain", "cover", "fill", "none"]);
export const V2VideoFramePolicySchema = z.enum(["floor", "round", "ceil"]);

export const V2VideoLayerSchema = V2LayerBaseSchema.extend({
  id: V2IdSchema,
  type: z.literal("video"),
  payload: z
    .object({
      assetId: V2IdSchema,
      fit: V2VideoFitSchema.optional(),
      /** Source trim positions in milliseconds. */
      trimStart: V2MillisecondsSchema.optional(),
      trimEnd: V2PositiveMillisecondsSchema.optional(),
      /** Visual playback speed multiplier; omitted means 1 (source rate). Mirrors the audio clip's `playbackRate`. */
      playbackRate: V2PositiveNumberSchema.optional(),
      audio: V2EmbeddedVideoAudioSchema.optional(),
      framePolicy: V2VideoFramePolicySchema.optional(),
    })
    .strict()
    .superRefine((payload, ctx) => {
      if (payload.trimStart !== undefined && payload.trimEnd !== undefined && payload.trimEnd <= payload.trimStart) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "Video trimEnd must be greater than trimStart",
          path: ["trimEnd"],
        });
      }
    }),
  });

export type V2VideoFramePolicy = z.infer<typeof V2VideoFramePolicySchema>;
export type V2VideoFit = z.infer<typeof V2VideoFitSchema>;
export type V2VideoLayer = z.infer<typeof V2VideoLayerSchema>;
