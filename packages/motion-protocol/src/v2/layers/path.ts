import { z } from "zod";
import { V2FiniteNumberSchema, V2NonNegativeSvgLengthSchema, V2PaintOrderSchema, V2PositiveSvgLengthSchema, V2SvgLengthSchema, V2VectorEffectSchema } from "../common";
import { V2PaintSchema } from "../paint";
import { V2LayerBaseSchema } from "./base";
import { V2MarkerReferenceSchema } from "../markers";
import {
  V2PathContourSchema,
} from "../path-geometry";

export {
  V2PathContourSchema,
  V2PathPointSchema,
  V2PathSegmentSchema,
} from "../path-geometry";

const V2PathMorphSchema = z
  .object({
    targetContours: z.array(V2PathContourSchema).min(1),
    progress: V2FiniteNumberSchema.min(0).max(1),
  })
  .strict();

export const V2PathLayerSchema = V2LayerBaseSchema.extend({
  type: z.literal("path"),
  payload: z
    .object({
      contours: z.array(V2PathContourSchema).min(1),
      fillRule: z.enum(["nonzero", "evenodd"]).default("nonzero"),
      /** SVG pathLength calibration for all subpaths in this path element. */
      pathLength: V2FiniteNumberSchema.nonnegative().optional(),
      morph: V2PathMorphSchema.optional(),
    })
    .strict(),
  style: z
    .object({
      /** SVG default is black when fill is omitted. */
      fill: V2PaintSchema.optional(),
      fillOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
      stroke: V2PaintSchema.optional(),
      strokeWidth: V2PositiveSvgLengthSchema.optional(),
      strokeOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
      strokeMiterLimit: V2FiniteNumberSchema.positive().optional(),
      strokeJoin: z.enum(["miter", "bevel", "round"]).optional(),
      strokeCap: z.enum(["butt", "square", "round"]).optional(),
      strokeDash: z
        .object({
          /** SVG accepts none, zero entries, and odd lists (odd lists repeat). */
          array: z.union([
            z.literal("none"),
            z.array(V2NonNegativeSvgLengthSchema).min(1),
          ]),
          offset: V2SvgLengthSchema.optional(),
        })
        .strict()
        .optional(),
      paintOrder: V2PaintOrderSchema.optional(),
      vectorEffect: V2VectorEffectSchema.optional(),
      markerStart: V2MarkerReferenceSchema.optional(),
      markerMid: V2MarkerReferenceSchema.optional(),
      markerEnd: V2MarkerReferenceSchema.optional(),
    })
    .strict(),
}).strict();

export type V2PathLayer = z.infer<typeof V2PathLayerSchema>;
