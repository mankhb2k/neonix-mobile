import { z } from "zod";
import { V2PositiveNumberSchema } from "./common";
import { V2Vec2Schema } from "./transform";

/** Whether a group's descendants share its 3D coordinate space or are flattened. */
export const V2TransformStyleSchema = z.enum(["flat", "preserve-3d"]);

/** Whether the reverse side of a transformed layer is eligible for painting. */
export const V2BackfaceVisibilitySchema = z.enum(["visible", "hidden"]);

/**
 * A local perspective context applied by a group to its descendants.
 * `origin` is compiler-resolved in the group's local coordinate units; it may
 * be outside the group's bounds, matching CSS perspective-origin semantics.
 */
export const V2PerspectiveContextSchema = z
  .object({
    distance: V2PositiveNumberSchema,
    origin: V2Vec2Schema,
  })
  .strict();

/** Group-level 3D rendering context. */
export const V2Render3DSchema = z
  .object({
    transformStyle: V2TransformStyleSchema.default("flat"),
    perspective: V2PerspectiveContextSchema.optional(),
  })
  .strict();

export type V2TransformStyle = z.infer<typeof V2TransformStyleSchema>;
export type V2BackfaceVisibility = z.infer<typeof V2BackfaceVisibilitySchema>;
export type V2PerspectiveContext = z.infer<typeof V2PerspectiveContextSchema>;
export type V2Render3D = z.infer<typeof V2Render3DSchema>;
