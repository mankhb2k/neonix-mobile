import { z } from "zod";
import {
  V2PositiveNumberSchema,
  V2ColorSchema,
} from "./common";
import { V2ViewSchema, type V2View } from "./view";

export const V2CompositionSchema = z
  .object({
    width: V2PositiveNumberSchema,
    height: V2PositiveNumberSchema,
    fps: V2PositiveNumberSchema,
    background: V2ColorSchema,
    colorSpace: z.literal("srgb"),
    view: V2ViewSchema,
  })
  .strict();

export type V2Composition = z.infer<typeof V2CompositionSchema>;
export type { V2View };
