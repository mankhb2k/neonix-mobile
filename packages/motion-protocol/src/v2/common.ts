import { z } from "zod";

export const V2IdSchema = z.string().min(1).max(200);
export const V2FiniteNumberSchema = z.number().finite();
export const V2PositiveNumberSchema = V2FiniteNumberSchema.positive();
export const V2NonNegativeNumberSchema = V2FiniteNumberSchema.nonnegative();
/** Protocol temporal values are milliseconds. Fractional milliseconds are allowed. */
export const V2MillisecondsSchema = V2NonNegativeNumberSchema;
export const V2PositiveMillisecondsSchema = V2PositiveNumberSchema;

/**
 * SVG length token used by geometry and paint authoring fields.
 * A bare number is a user-unit value; percentages remain semantic until the
 * compiler resolves them against the relevant viewport or bounding box.
 */
export const V2SvgLengthUnitSchema = z.enum([
  "number",
  "px",
  "pt",
  "pc",
  "mm",
  "cm",
  "in",
  "em",
  "percent",
]);
export const V2SvgLengthSchema = z.union([
  V2FiniteNumberSchema,
  z.object({ value: V2FiniteNumberSchema, unit: V2SvgLengthUnitSchema }).strict(),
]);
export const V2NonNegativeSvgLengthSchema = z.union([
  V2NonNegativeNumberSchema,
  z.object({ value: V2NonNegativeNumberSchema, unit: V2SvgLengthUnitSchema }).strict(),
]);
export const V2PositiveSvgLengthSchema = z.union([
  V2PositiveNumberSchema,
  z.object({ value: V2PositiveNumberSchema, unit: V2SvgLengthUnitSchema }).strict(),
]);
export type V2SvgLengthUnit = z.infer<typeof V2SvgLengthUnitSchema>;
export type V2SvgLength = z.infer<typeof V2SvgLengthSchema>;

/** SVG paint-order components. Unlisted components are appended by the runtime in SVG default order. */
export const V2PaintOrderItemSchema = z.enum(["fill", "stroke", "markers"]);
export const V2PaintOrderSchema = z
  .array(V2PaintOrderItemSchema)
  .min(1)
  .max(3)
  .superRefine((items, ctx) => {
    if (new Set(items).size !== items.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "paintOrder items must be unique",
      });
    }
  });
export type V2PaintOrderItem = z.infer<typeof V2PaintOrderItemSchema>;
export type V2PaintOrder = z.infer<typeof V2PaintOrderSchema>;
/** SVG vector-effect semantic. The default when omitted is `none`. */
export const V2VectorEffectSchema = z.enum(["none", "non-scaling-stroke"]);
export type V2VectorEffect = z.infer<typeof V2VectorEffectSchema>;
export const V2ColorSchema = z
  .string()
  .regex(/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i, "Expected #RRGGBB or #RRGGBBAA");
