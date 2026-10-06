import { z } from "zod";

/** Shared SVG/CSS blend-mode semantic used by compositing and feBlend. */
export const V2BlendModeSchema = z.enum([
  "normal",
  "darken",
  "multiply",
  "color-burn",
  "lighten",
  "screen",
  "color-dodge",
  "overlay",
  "soft-light",
  "hard-light",
  "difference",
  "exclusion",
  "hue",
  "saturation",
  "color",
  "luminosity",
]);

/** SVG/CSS isolation semantic for compositing groups. */
export const V2IsolationModeSchema = z.enum(["auto", "isolate"]);

/** Element/group compositing state; distinct from filter-graph feBlend. */
export const V2CompositeSchema = z
  .object({
    blendMode: V2BlendModeSchema.default("normal"),
    isolation: V2IsolationModeSchema.optional(),
  })
  .strict();

export type V2BlendMode = z.infer<typeof V2BlendModeSchema>;
export type V2IsolationMode = z.infer<typeof V2IsolationModeSchema>;
export type V2Composite = z.infer<typeof V2CompositeSchema>;
