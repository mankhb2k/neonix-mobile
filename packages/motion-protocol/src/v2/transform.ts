import { z } from "zod";
import { V2FiniteNumberSchema } from "./common";

export const V2Vec2Schema = z
  .object({ x: V2FiniteNumberSchema, y: V2FiniteNumberSchema })
  .strict();

export const V2Vec3Schema = z
  .object({
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
    z: V2FiniteNumberSchema,
  })
  .strict();

/** SVG's six-value affine matrix: x'=a*x+c*y+e, y'=b*x+d*y+f. */
export const V2SvgMatrixSchema = z.tuple([
  V2FiniteNumberSchema,
  V2FiniteNumberSchema,
  V2FiniteNumberSchema,
  V2FiniteNumberSchema,
  V2FiniteNumberSchema,
  V2FiniteNumberSchema,
]);

const V2SvgTranslateOperationSchema = z
  .object({ type: z.literal("translate"), x: V2FiniteNumberSchema, y: V2FiniteNumberSchema })
  .strict();
const V2SvgScaleOperationSchema = z
  .object({ type: z.literal("scale"), x: V2FiniteNumberSchema, y: V2FiniteNumberSchema })
  .strict();
const V2SvgRotateOperationSchema = z
  .object({
    type: z.literal("rotate"),
    angle: V2FiniteNumberSchema,
    center: V2Vec2Schema.optional(),
  })
  .strict();
const V2SvgSkewXOperationSchema = z
  .object({ type: z.literal("skewX"), angle: V2FiniteNumberSchema })
  .strict();
const V2SvgSkewYOperationSchema = z
  .object({ type: z.literal("skewY"), angle: V2FiniteNumberSchema })
  .strict();
const V2SvgMatrixOperationSchema = z
  .object({ type: z.literal("matrix"), values: V2SvgMatrixSchema })
  .strict();

export const V2SvgTransformOperationSchema = z.discriminatedUnion("type", [
  V2SvgTranslateOperationSchema,
  V2SvgScaleOperationSchema,
  V2SvgRotateOperationSchema,
  V2SvgSkewXOperationSchema,
  V2SvgSkewYOperationSchema,
  V2SvgMatrixOperationSchema,
]);

/**
 * A layer transform is authored through exactly these fields — no ordered
 * `operations[]`/`extensions` list alongside them. See CLAUDE.md's "Layer
 * transform: one explicit component form, no `operations[]`" section for the
 * full rationale (2D/3D field mapping, and why the previous dual
 * representation — component fields plus an "operations[] wins when present"
 * list — was a real correctness hazard, not just redundancy).
 *
 * clip-path/mask/pattern-definition transforms are a different object with a
 * legitimately 2D-only need; they keep their own ordered list,
 * `V2SvgTransformOperationSchema` above, which this does not duplicate or
 * conflict with.
 */
export const V2TransformSchema = z
  .object({
    translate: V2Vec3Schema,
    scale: V2Vec3Schema,
    rotate: V2Vec3Schema,
    skew: V2Vec2Schema,
    /** Local-unit pivot; it may be inside or outside the layer bounds. */
    anchor: V2Vec3Schema,
    /**
     * CSS-style perspective distance for 3D rotations (`rotate.x`/`rotate.y`).
     * Only meaningful once one of those is non-zero.
     */
    perspective: V2FiniteNumberSchema.positive().optional(),
  })
  .strict();

export type V2Transform = z.infer<typeof V2TransformSchema>;
export type V2Vec2 = z.infer<typeof V2Vec2Schema>;
export type V2Vec3 = z.infer<typeof V2Vec3Schema>;
export type V2SvgMatrix = z.infer<typeof V2SvgMatrixSchema>;
export type V2SvgTransformOperation = z.infer<typeof V2SvgTransformOperationSchema>;
