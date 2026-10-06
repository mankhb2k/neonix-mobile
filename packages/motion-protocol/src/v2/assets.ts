import { z } from "zod";
import { V2IdSchema, V2MillisecondsSchema, V2PositiveNumberSchema } from "./common";

/** Renderer-neutral asset metadata. GPU textures never cross this boundary. */
const V2AssetMetadataShape = {
  id: V2IdSchema,
  uri: z.string().trim().min(1),
  mimeType: z.string().trim().min(1).optional(),
  width: V2PositiveNumberSchema.optional(),
  height: V2PositiveNumberSchema.optional(),
  integrity: z.string().trim().min(1).optional(),
};

/** Import-time audio derivative for a video asset.
 *
 * The original video URI remains the visual source. This URI is an audio-only,
 * seekable derivative and is intentionally kept as asset metadata rather than
 * duplicated in every layer's payload.
 */
export const V2VideoAudioDerivativeSchema = z.object({
  uri: z.string().trim().min(1),
  mimeType: z.string().trim().min(1).optional(),
  /** Duration metadata in milliseconds. */
  duration: V2MillisecondsSchema.optional(),
  sampleRate: V2PositiveNumberSchema.int().optional(),
  channels: V2PositiveNumberSchema.int().max(32).optional(),
  integrity: z.string().trim().min(1).optional(),
}).strict();

export const V2ImageAssetSchema = z
  .object({ ...V2AssetMetadataShape, kind: z.literal("image") })
  .strict();

export const V2VideoAssetSchema = z
  .object({
    ...V2AssetMetadataShape,
    kind: z.literal("video"),
    /** Duration metadata in milliseconds. */
    duration: V2MillisecondsSchema.optional(),
    fps: V2PositiveNumberSchema.optional(),
    audio: V2VideoAudioDerivativeSchema.optional(),
  })
  .strict();

export const V2AudioAssetSchema = z
  .object({
    id: V2IdSchema,
    kind: z.literal("audio"),
    uri: z.string().trim().min(1),
    mimeType: z.string().trim().min(1),
    /** Duration metadata in milliseconds. */
    duration: V2MillisecondsSchema.optional(),
    sampleRate: V2PositiveNumberSchema.int().optional(),
    channels: V2PositiveNumberSchema.int().max(32).optional(),
    integrity: z.string().trim().min(1).optional(),
  })
  .strict();

/** A runtime font binary. Family/style metadata belongs to the font catalog. */
export const V2FontAssetSchema = z
  .object({
    id: V2IdSchema,
    kind: z.literal("font"),
    uri: z.string().trim().min(1),
    weight: z.number().int().min(1).max(1000),
    integrity: z.string().regex(/^sha256:[a-f0-9]{64}$/i),
  })
  .strict();

export const V2AssetSchema = z.discriminatedUnion("kind", [
  V2ImageAssetSchema,
  V2VideoAssetSchema,
  V2AudioAssetSchema,
  V2FontAssetSchema,
]);
export const V2AssetListSchema = z.array(V2AssetSchema);

export type V2ImageAsset = z.infer<typeof V2ImageAssetSchema>;
export type V2VideoAsset = z.infer<typeof V2VideoAssetSchema>;
export type V2VideoAudioDerivative = z.infer<typeof V2VideoAudioDerivativeSchema>;
export type V2AudioAsset = z.infer<typeof V2AudioAssetSchema>;
export type V2FontAsset = z.infer<typeof V2FontAssetSchema>;
export type V2Asset = z.infer<typeof V2AssetSchema>;
