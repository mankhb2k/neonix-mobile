import { z } from "zod";
import { V2FiniteNumberSchema } from "./common";

export const V2PathPointSchema = z
  .object({
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
  })
  .strict();

export const V2PathSegmentSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("line"), to: V2PathPointSchema }).strict(),
  z
    .object({
      kind: z.literal("quadratic"),
      control: V2PathPointSchema,
      to: V2PathPointSchema,
    })
    .strict(),
  z
    .object({
      kind: z.literal("cubic"),
      control1: V2PathPointSchema,
      control2: V2PathPointSchema,
      to: V2PathPointSchema,
    })
    .strict(),
  z
    .object({
      kind: z.literal("arc"),
      radii: z
        .object({
          x: V2FiniteNumberSchema.nonnegative(),
          y: V2FiniteNumberSchema.nonnegative(),
        })
        .strict(),
      rotation: V2FiniteNumberSchema,
      largeArc: z.boolean(),
      sweep: z.boolean(),
      to: V2PathPointSchema,
    })
    .strict(),
]);

export const V2PathContourSchema = z
  .object({
    id: z.string().min(1).max(200),
    start: V2PathPointSchema,
    segments: z.array(V2PathSegmentSchema).min(1),
    closed: z.boolean(),
  })
  .strict();

export type V2PathPoint = z.infer<typeof V2PathPointSchema>;
export type V2PathSegment = z.infer<typeof V2PathSegmentSchema>;
export type V2PathContour = z.infer<typeof V2PathContourSchema>;
