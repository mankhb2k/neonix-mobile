import { z } from "zod";
import { V2FiniteNumberSchema, V2IdSchema } from "./common";
import {
  V2ClipPathNodeSchema,
  V2SvgDefinitionTransformSchema,
  type V2SvgDefinitionNode,
} from "./clip";
import { V2TrackListSchema } from "./animation";

/** SVG mask units. The default follows SVG/usvg: objectBoundingBox. */
export const V2MaskUnitsSchema = z.enum(["userSpaceOnUse", "objectBoundingBox"]);
export const V2MaskContentUnitsSchema = z.enum(["userSpaceOnUse", "objectBoundingBox"]);
export const V2MaskTypeSchema = z.enum(["alpha", "luminance"]);
/** CSS mask layer compositing operators. */
export const V2MaskCompositeSchema = z.enum(["add", "subtract", "intersect", "exclude"]);
const V2MaskImagePreserveAspectRatioSchema = z.object({
  defer: z.boolean().optional(),
  align: z.enum(["none", "xMinYMin", "xMidYMin", "xMaxYMin", "xMinYMid", "xMidYMid", "xMaxYMid", "xMinYMax", "xMidYMax", "xMaxYMax"]).optional(),
  meetOrSlice: z.enum(["meet", "slice"]).optional(),
}).strict();

/** A number is a user-space/unit value; an object explicitly represents an SVG percentage. */
export const V2MaskLengthSchema = z.union([
  V2FiniteNumberSchema,
  z.object({ value: V2FiniteNumberSchema, unit: z.literal("percent") }).strict(),
]);

/** A mask image source is kept semantic until the runtime resolves the asset. */
export const V2MaskImageSourceSchema = z
  .object({
    type: z.literal("image"),
    assetId: V2IdSchema,
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
    width: V2FiniteNumberSchema,
    height: V2FiniteNumberSchema,
    /** Coverage multiplier used by image()/cross-fade() mask sources. */
    opacity: V2FiniteNumberSchema.min(0).max(1).optional(),
    fit: z.enum(["contain", "cover", "fill", "none"]).default("fill"),
    preserveAspectRatio: V2MaskImagePreserveAspectRatioSchema.optional(),
  })
  .strict();

export const V2MaskSchema = z
  .object({
    id: V2IdSchema,
    maskUnits: V2MaskUnitsSchema.default("objectBoundingBox"),
    maskContentUnits: V2MaskContentUnitsSchema.default("userSpaceOnUse"),
    maskType: V2MaskTypeSchema.default("luminance"),
    x: V2MaskLengthSchema.optional(),
    y: V2MaskLengthSchema.optional(),
    width: V2MaskLengthSchema.optional(),
    height: V2MaskLengthSchema.optional(),
    transform: V2SvgDefinitionTransformSchema.optional(),
    children: z.array(V2ClipPathNodeSchema).min(1).optional(),
    image: V2MaskImageSourceSchema.optional(),
    /** Project-level animation, sampled at absolute composition time (no `timing.start`); see `sampleMotionProjectDefsAtTime`. */
    tracks: V2TrackListSchema.optional(),
  })
  .strict()
  .superRefine((mask, ctx) => {
    if ((mask.children === undefined) === (mask.image === undefined)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "A mask must contain either children or image, but not both", path: ["children"] });
    }
  });

/** One CSS mask-image layer. Multiple maskIds are tiles of the same CSS layer. */
type V2MaskLayerValue = {
  maskIds: string[];
  mode?: "alpha" | "luminance";
  composite: "add" | "subtract" | "intersect" | "exclude";
};

export const V2MaskLayerSchema: z.ZodType<V2MaskLayerValue, z.ZodTypeDef, unknown> = z
  .object({
    maskIds: z.array(V2IdSchema).min(1).max(4096),
    mode: V2MaskTypeSchema.optional(),
    composite: V2MaskCompositeSchema.default("add"),
  })
  .strict();

export const V2MaskLayerListSchema: z.ZodType<V2MaskLayerValue[], z.ZodTypeDef, unknown> = z.array(V2MaskLayerSchema).min(1).max(64);

export const V2MaskListSchema = z
  .array(V2MaskSchema)
  .max(256)
  .superRefine((masks, ctx) => {
    const ids = new Set<string>();
    masks.forEach((mask, index) => {
      if (ids.has(mask.id)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate mask id: ${mask.id}`, path: [index, "id"] });
      ids.add(mask.id);
    });
  });

export type V2MaskLength = z.infer<typeof V2MaskLengthSchema>;
export type V2MaskUnits = z.infer<typeof V2MaskUnitsSchema>;
export type V2MaskContentUnits = z.infer<typeof V2MaskContentUnitsSchema>;
export type V2MaskType = z.infer<typeof V2MaskTypeSchema>;
export type V2MaskComposite = z.infer<typeof V2MaskCompositeSchema>;
export type V2MaskImageSource = z.infer<typeof V2MaskImageSourceSchema>;
export type V2Mask = z.infer<typeof V2MaskSchema>;
export type V2MaskLayer = z.infer<typeof V2MaskLayerSchema>;
export type V2MaskLayerList = z.infer<typeof V2MaskLayerListSchema>;
export type V2MaskList = z.infer<typeof V2MaskListSchema>;
export type V2MaskContentNode = V2SvgDefinitionNode;
