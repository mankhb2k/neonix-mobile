import { z } from "zod";
import { V2FiniteNumberSchema, V2IdSchema, V2PositiveNumberSchema } from "../common";
import { V2LayerBaseSchema } from "./base";

export const V2ImageAlignSchema = z.enum([
  "none",
  "xMinYMin",
  "xMidYMin",
  "xMaxYMin",
  "xMinYMid",
  "xMidYMid",
  "xMaxYMid",
  "xMinYMax",
  "xMidYMax",
  "xMaxYMax",
]);

export const V2ImagePreserveAspectRatioSchema = z
  .object({
    /** SVG's optional `defer` keyword, retained for image semantics. */
    defer: z.boolean().optional(),
    align: V2ImageAlignSchema.optional(),
    meetOrSlice: z.enum(["meet", "slice"]).optional(),
  })
  .strict();

export const V2ImageRenderingSchema = z.enum([
  "auto",
  "optimizeQuality",
  "optimizeSpeed",
  "smooth",
  "high-quality",
  "crisp-edges",
  "pixelated",
]);

/** CSS object-fit semantics for an image viewport. */
export const V2ImageFitSchema = z.enum(["contain", "cover", "fill", "none"]);

export const V2ImageLayerSchema = V2LayerBaseSchema.extend({
  type: z.literal("image"),
  payload: z
    .object({
      assetId: V2IdSchema,
      fit: V2ImageFitSchema.optional(),
      /** SVG image viewport origin. Defaults to 0 when omitted. */
      x: V2FiniteNumberSchema.optional(),
      y: V2FiniteNumberSchema.optional(),
      /** Omitted dimensions are resolved from the asset intrinsic size. */
      width: V2PositiveNumberSchema.optional(),
      height: V2PositiveNumberSchema.optional(),
      preserveAspectRatio: V2ImagePreserveAspectRatioSchema.optional(),
      imageRendering: V2ImageRenderingSchema.optional(),
    })
    .strict(),
}).strict();

export type V2ImageAlign = z.infer<typeof V2ImageAlignSchema>;
export type V2ImagePreserveAspectRatio = z.infer<typeof V2ImagePreserveAspectRatioSchema>;
export type V2ImageRendering = z.infer<typeof V2ImageRenderingSchema>;
export type V2ImageFit = z.infer<typeof V2ImageFitSchema>;
export type V2ImageLayer = z.infer<typeof V2ImageLayerSchema>;
