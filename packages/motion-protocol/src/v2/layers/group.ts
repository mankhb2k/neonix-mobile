import { z } from "zod";
import { V2LayerBaseSchema } from "./base";
import { V2Render3DSchema } from "../render3d";

/**
 * SVG `g` semantic container.
 *
 * The group keeps its transform, opacity, compositing and timing on the
 * semantic layer. Runtime may turn those properties into a surface boundary
 * when the SVG/usvg rules require it, but the Protocol tree is not flattened.
 */
export const V2GroupLayerSchema = V2LayerBaseSchema.extend({
  type: z.literal("group"),
  /** Optional local 3D context for this group's descendants. */
  render3d: V2Render3DSchema.optional(),
}).strict();

export type V2GroupLayer = z.infer<typeof V2GroupLayerSchema>;
