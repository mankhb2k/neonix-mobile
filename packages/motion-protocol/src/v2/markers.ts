import { z } from "zod";
import {
  V2FiniteNumberSchema,
  V2IdSchema,
  V2PaintOrderSchema,
  V2PositiveNumberSchema,
} from "./common";
import { V2PaintSchema } from "./paint";
import { V2PathContourSchema } from "./path-geometry";

/** SVG markerUnits controls whether marker geometry follows the stroke width. */
export const V2MarkerUnitsSchema = z.enum(["strokeWidth", "userSpaceOnUse"]);

/** SVG orient semantics, including the two automatic tangent modes. */
export const V2MarkerOrientSchema = z.union([
  z.literal("auto"),
  z.literal("auto-start-reverse"),
  V2FiniteNumberSchema,
]);

export const V2MarkerViewBoxSchema = z
  .object({
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
    width: V2PositiveNumberSchema,
    height: V2PositiveNumberSchema,
  })
  .strict();

/**
 * A marker definition is semantic SVG paint data. Its path content is kept in
 * protocol form and is lowered to positioned runtime geometry at each use.
 */
export const V2MarkerSchema = z
  .object({
    id: V2IdSchema,
    markerUnits: V2MarkerUnitsSchema.default("strokeWidth"),
    refX: V2FiniteNumberSchema.default(0),
    refY: V2FiniteNumberSchema.default(0),
    markerWidth: V2PositiveNumberSchema.default(3),
    markerHeight: V2PositiveNumberSchema.default(3),
    orient: V2MarkerOrientSchema.default(0),
    viewBox: V2MarkerViewBoxSchema.optional(),
    content: z
      .object({
        contours: z.array(V2PathContourSchema).min(1),
        fill: V2PaintSchema.optional(),
        fillOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
        stroke: V2PaintSchema.optional(),
        strokeWidth: V2PositiveNumberSchema.optional(),
        strokeOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
        paintOrder: V2PaintOrderSchema.optional(),
      })
      .strict()
      .superRefine((content, ctx) => {
        if (content.fill === undefined && content.stroke === undefined) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: "Marker content requires fill or stroke",
            path: ["fill"],
          });
        }
        if (content.strokeWidth !== undefined && content.stroke === undefined) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: "Marker strokeWidth requires stroke",
            path: ["strokeWidth"],
          });
        }
        if (content.strokeOpacity !== undefined && content.stroke === undefined) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: "Marker strokeOpacity requires stroke",
            path: ["strokeOpacity"],
          });
        }
      }),
  })
  .strict();

export const V2MarkerListSchema = z
  .array(V2MarkerSchema)
  .max(256)
  .superRefine((markers, ctx) => {
    const ids = new Set<string>();
    markers.forEach((marker, index) => {
      if (ids.has(marker.id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Duplicate marker id: ${marker.id}`,
          path: [index, "id"],
        });
      }
      ids.add(marker.id);
    });
  });

export const V2MarkerReferenceSchema = V2IdSchema;

export type V2MarkerUnits = z.infer<typeof V2MarkerUnitsSchema>;
export type V2MarkerOrient = z.infer<typeof V2MarkerOrientSchema>;
export type V2MarkerViewBox = z.infer<typeof V2MarkerViewBoxSchema>;
export type V2Marker = z.infer<typeof V2MarkerSchema>;
export type V2MarkerList = z.infer<typeof V2MarkerListSchema>;
