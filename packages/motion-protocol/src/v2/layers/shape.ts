import { z } from "zod";
import {
  V2FiniteNumberSchema,
  V2NonNegativeSvgLengthSchema,
  V2PositiveNumberSchema,
  V2PositiveSvgLengthSchema,
  V2PaintOrderSchema,
  V2SvgLengthSchema,
  V2VectorEffectSchema,
} from "../common";
import { V2PaintSchema } from "../paint";
import { V2LayerBaseSchema } from "./base";
import { V2MarkerReferenceSchema } from "../markers";

const V2ShapePointSchema = z.object({
  x: V2FiniteNumberSchema,
  y: V2FiniteNumberSchema,
}).strict();

export { V2GradientFillSchema, V2GradientStopSchema, V2PatternFillSchema } from "../paint";
export type { V2GradientFill, V2GradientStop, V2PatternFill } from "../paint";

export const V2ShapeLayerSchema = V2LayerBaseSchema.extend({
  type: z.literal("shape"),
  payload: z
    .object({
      shape: z.enum(["rectangle", "circle", "ellipse", "line", "polyline", "polygon"]),
      /** SVG pathLength calibration after the basic shape is lowered to path geometry. */
      pathLength: V2FiniteNumberSchema.nonnegative().optional(),
      cornerRadius: V2NonNegativeSvgLengthSchema.optional(),
      rx: V2NonNegativeSvgLengthSchema.optional(),
      ry: V2NonNegativeSvgLengthSchema.optional(),
      start: V2ShapePointSchema.optional(),
      end: V2ShapePointSchema.optional(),
      points: z.array(V2ShapePointSchema).min(2).optional(),
    })
    .strict()
    .superRefine((payload, ctx) => {
      if (payload.shape !== "rectangle" && payload.cornerRadius !== undefined) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "cornerRadius requires rectangle", path: ["cornerRadius"] });
      }
      if (payload.shape !== "rectangle" && (payload.rx !== undefined || payload.ry !== undefined)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "rx/ry require rectangle", path: ["rx"] });
      }
      if (payload.shape === "line" && (!payload.start || !payload.end)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "line requires start and end", path: ["start"] });
      }
      if ((payload.shape === "polyline" || payload.shape === "polygon") && !payload.points) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${payload.shape} requires points`, path: ["points"] });
      }
      if (payload.shape !== "line" && (payload.start !== undefined || payload.end !== undefined)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "start/end require line", path: ["start"] });
      }
      if (payload.shape !== "polyline" && payload.shape !== "polygon" && payload.points !== undefined) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "points require polyline or polygon", path: ["points"] });
      }
    }),
  style: z
    .object({
      fill: V2PaintSchema.optional(),
      fillOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
      stroke: V2PaintSchema.optional(),
      strokeWidth: V2PositiveSvgLengthSchema.optional(),
      strokeOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
      strokeMiterLimit: V2PositiveNumberSchema.optional(),
      strokeJoin: z.enum(["miter", "bevel", "round"]).optional(),
      strokeCap: z.enum(["butt", "square", "round"]).optional(),
      strokeDash: z
        .object({
          array: z.union([z.literal("none"), z.array(V2NonNegativeSvgLengthSchema).min(1)]),
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

export type V2ShapeLayer = z.infer<typeof V2ShapeLayerSchema>;
