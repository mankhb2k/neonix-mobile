import { z } from "zod";
import { V2MillisecondsSchema, V2PositiveMillisecondsSchema } from "./common";

export const V2TimingSchema = z
  .object({
    /** Composition start in milliseconds. */
    start: V2MillisecondsSchema,
    /** Layer duration in milliseconds. */
    duration: V2PositiveMillisecondsSchema,
  })
  .strict();

export type V2Timing = z.infer<typeof V2TimingSchema>;
