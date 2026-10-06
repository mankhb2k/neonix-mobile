import { z } from "zod";
import { V2FiniteNumberSchema, V2PositiveNumberSchema } from "./common";

const Vec3Schema = z
  .object({
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
    z: V2FiniteNumberSchema,
  })
  .strict();

export const V2ProjectionSchema = z
  .discriminatedUnion("kind", [
    z
      .object({
        kind: z.literal("orthographic"),
        zoom: V2PositiveNumberSchema,
        near: V2PositiveNumberSchema,
        far: V2PositiveNumberSchema,
      })
      .strict(),
    z
      .object({
        kind: z.literal("perspective"),
        fov: V2FiniteNumberSchema.min(0.001).max(179.999),
        near: V2PositiveNumberSchema,
        far: V2PositiveNumberSchema,
      })
      .strict(),
  ])
  .superRefine((value, ctx) => {
    if (value.far <= value.near) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `${value.kind} far must be greater than near`,
        path: ["far"],
      });
    }
  });

export const V2ViewSchema = z
  .object({
    projection: V2ProjectionSchema,
    transform: z
      .object({
        translate: Vec3Schema,
        rotate: Vec3Schema,
      })
      .strict(),
  })
  .strict();

export type V2View = z.infer<typeof V2ViewSchema>;
export type V2Projection = z.infer<typeof V2ProjectionSchema>;
