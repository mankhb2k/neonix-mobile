import { z } from "zod";
import { V2FiniteNumberSchema } from "./common";
import { V2PathContourSchema } from "./path-geometry";

/** CSS-owned motion path source. The path is geometry, not a visible paint. */
export const V2OffsetPathSchema = z
  .object({
    type: z.literal("path"),
    contours: z.array(V2PathContourSchema).min(1),
    coordinateSpace: z.enum(["parent-local", "layer-local"]).default("parent-local"),
    referenceBox: z.enum(["border-box", "fill-box", "view-box"]).default("border-box"),
    /** Resolved source path length used to normalize CSS percentages. */
    pathLength: V2FiniteNumberSchema.positive().optional(),
    sampling: z
      .object({
        method: z.literal("adaptive-flatness"),
        tolerance: V2FiniteNumberSchema.positive(),
        maxSegments: z.number().int().positive(),
      })
      .strict()
      .optional(),
  })
  .strict();

export const V2OffsetRotateSchema = z
  .object({
    mode: z.enum(["auto", "auto-reverse", "fixed"]),
    angle: V2FiniteNumberSchema,
  })
  .strict();

export const V2OffsetAnchorSchema = z
  .object({
    /** Local layer units after CSS percentages/keywords are resolved. */
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
  })
  .strict();

/** Layer-owned CSS motion-path semantics. */
export const V2MotionPathSchema = z
  .object({
    offsetPath: V2OffsetPathSchema,
    /** Canonical normalized distance: 0 is path start, 1 is path end. */
    offsetDistance: V2FiniteNumberSchema.default(0),
    offsetRotate: V2OffsetRotateSchema.default({ mode: "auto", angle: 0 }),
    offsetAnchor: V2OffsetAnchorSchema.default({ x: 0, y: 0 }),
  })
  .strict();

export type V2OffsetPath = z.infer<typeof V2OffsetPathSchema>;
export type V2OffsetRotate = z.infer<typeof V2OffsetRotateSchema>;
export type V2OffsetAnchor = z.infer<typeof V2OffsetAnchorSchema>;
export type V2MotionPath = z.infer<typeof V2MotionPathSchema>;
