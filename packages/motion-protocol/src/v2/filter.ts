import { z } from "zod";
import { V2ColorSchema, V2FiniteNumberSchema, V2IdSchema } from "./common";
import { V2BlendModeSchema } from "./blend";
import { V2TrackListSchema } from "./animation";

/** SVG filter length. Bare numbers are kept as user-space values. */
export const V2FilterLengthSchema = z.union([
  V2FiniteNumberSchema,
  z.object({
    value: V2FiniteNumberSchema,
    unit: z.enum(["number", "px", "percent"]),
  }).strict(),
]);

export const V2FilterUnitsSchema = z.enum(["objectBoundingBox", "userSpaceOnUse"]);
export const V2FilterColorInterpolationSchema = z.enum(["sRGB", "linearRGB"]);

/** SVG filter inputs use SourceGraphic/SourceAlpha or a previous result name. */
export const V2FilterInputSchema = z.string().min(1).max(200);

const V2FilterPrimitiveBase = {
  id: V2IdSchema,
  in: V2FilterInputSchema.optional(),
  result: V2IdSchema.optional(),
  region: z.object({
    x: V2FilterLengthSchema.optional(),
    y: V2FilterLengthSchema.optional(),
    width: V2FilterLengthSchema.optional(),
    height: V2FilterLengthSchema.optional(),
  }).strict().optional(),
  colorInterpolationFilters: V2FilterColorInterpolationSchema.optional(),
} as const;

const V2FilterStdDeviationSchema = z.object({
  x: V2FiniteNumberSchema.nonnegative(),
  y: V2FiniteNumberSchema.nonnegative(),
}).strict();

const V2FilterTransferFunctionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("identity") }).strict(),
  z.object({ type: z.literal("table"), values: z.array(V2FiniteNumberSchema) }).strict(),
  z.object({ type: z.literal("discrete"), values: z.array(V2FiniteNumberSchema) }).strict(),
  z.object({
    type: z.literal("linear"),
    slope: V2FiniteNumberSchema,
    intercept: V2FiniteNumberSchema,
  }).strict(),
  z.object({
    type: z.literal("gamma"),
    amplitude: V2FiniteNumberSchema,
    exponent: V2FiniteNumberSchema,
    offset: V2FiniteNumberSchema,
  }).strict(),
]);

const V2FilterLightSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("feDistantLight"),
    azimuth: V2FiniteNumberSchema,
    elevation: V2FiniteNumberSchema,
  }).strict(),
  z.object({
    type: z.literal("fePointLight"),
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
    z: V2FiniteNumberSchema,
  }).strict(),
  z.object({
    type: z.literal("feSpotLight"),
    x: V2FiniteNumberSchema,
    y: V2FiniteNumberSchema,
    z: V2FiniteNumberSchema,
    pointsAtX: V2FiniteNumberSchema,
    pointsAtY: V2FiniteNumberSchema,
    pointsAtZ: V2FiniteNumberSchema,
    specularExponent: V2FiniteNumberSchema.nonnegative().optional(),
    limitingConeAngle: V2FiniteNumberSchema.nonnegative().optional(),
  }).strict(),
]);

export const V2FilterPrimitiveSchema = z.union([
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feBlend"),
    in2: V2FilterInputSchema,
    mode: V2BlendModeSchema.optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feColorMatrix"),
    kind: z.enum(["matrix", "saturate", "hueRotate", "luminanceToAlpha"]),
    values: z.array(V2FiniteNumberSchema).optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feComponentTransfer"),
    functions: z.object({
      r: V2FilterTransferFunctionSchema.optional(),
      g: V2FilterTransferFunctionSchema.optional(),
      b: V2FilterTransferFunctionSchema.optional(),
      a: V2FilterTransferFunctionSchema.optional(),
    }).strict(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feComposite"),
    in2: V2FilterInputSchema,
    operator: z.enum(["over", "in", "out", "atop", "xor", "arithmetic"]).optional(),
    k1: V2FiniteNumberSchema.optional(),
    k2: V2FiniteNumberSchema.optional(),
    k3: V2FiniteNumberSchema.optional(),
    k4: V2FiniteNumberSchema.optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feConvolveMatrix"),
    order: z.object({ x: z.number().int().positive(), y: z.number().int().positive() }).strict(),
    kernelMatrix: z.array(V2FiniteNumberSchema).min(1),
    divisor: V2FiniteNumberSchema.optional(),
    bias: V2FiniteNumberSchema.optional(),
    target: z.object({ x: z.number().int().nonnegative(), y: z.number().int().nonnegative() }).strict().optional(),
    edgeMode: z.enum(["duplicate", "wrap", "none"]).optional(),
    preserveAlpha: z.boolean().optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feDisplacementMap"),
    in2: V2FilterInputSchema,
    scale: V2FiniteNumberSchema,
    xChannelSelector: z.enum(["R", "G", "B", "A"]).optional(),
    yChannelSelector: z.enum(["R", "G", "B", "A"]).optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feDropShadow"),
    dx: V2FiniteNumberSchema,
    dy: V2FiniteNumberSchema,
    stdDeviation: V2FilterStdDeviationSchema,
    floodColor: V2ColorSchema,
    floodOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feFlood"),
    color: V2ColorSchema,
    opacity: V2FiniteNumberSchema.min(0).max(1).optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feGaussianBlur"),
    stdDeviation: V2FilterStdDeviationSchema,
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feImage"),
    href: z.string().min(1).max(2000),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feMerge"),
    nodes: z.array(z.object({ in: V2FilterInputSchema }).strict()).min(1),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feMorphology"),
    operator: z.enum(["erode", "dilate"]).optional(),
    radius: z.object({ x: V2FiniteNumberSchema.nonnegative(), y: V2FiniteNumberSchema.nonnegative() }).strict(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feOffset"),
    dx: V2FiniteNumberSchema,
    dy: V2FiniteNumberSchema,
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feTile"),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feTurbulence"),
    baseFrequency: z.object({ x: V2FiniteNumberSchema.nonnegative(), y: V2FiniteNumberSchema.nonnegative() }).strict(),
    numOctaves: z.number().int().nonnegative().optional(),
    seed: V2FiniteNumberSchema.optional(),
    stitchTiles: z.boolean().optional(),
    noiseType: z.enum(["fractalNoise", "turbulence"]).optional(),
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feDiffuseLighting"),
    surfaceScale: V2FiniteNumberSchema,
    diffuseConstant: V2FiniteNumberSchema.nonnegative(),
    kernelUnitLength: z.object({ x: V2FiniteNumberSchema.positive(), y: V2FiniteNumberSchema.positive() }).strict().optional(),
    lightingColor: V2ColorSchema.optional(),
    light: V2FilterLightSchema,
  }).strict(),
  z.object({
    ...V2FilterPrimitiveBase,
    type: z.literal("feSpecularLighting"),
    surfaceScale: V2FiniteNumberSchema,
    specularConstant: V2FiniteNumberSchema.nonnegative(),
    specularExponent: V2FiniteNumberSchema.nonnegative(),
    kernelUnitLength: z.object({ x: V2FiniteNumberSchema.positive(), y: V2FiniteNumberSchema.positive() }).strict().optional(),
    lightingColor: V2ColorSchema.optional(),
    light: V2FilterLightSchema,
  }).strict(),
]);

export const V2FilterSchema = z
  .object({
    id: V2IdSchema,
    x: V2FilterLengthSchema.optional(),
    y: V2FilterLengthSchema.optional(),
    width: V2FilterLengthSchema.optional(),
    height: V2FilterLengthSchema.optional(),
    filterUnits: V2FilterUnitsSchema.default("objectBoundingBox"),
    primitiveUnits: V2FilterUnitsSchema.default("userSpaceOnUse"),
    colorInterpolationFilters: V2FilterColorInterpolationSchema.default("linearRGB"),
    primitives: z.array(V2FilterPrimitiveSchema).min(1).max(128),
    /**
     * Project-level animation. A filter has no `timing.start` like a layer,
     * so its track keyframe times are sampled against the absolute
     * composition time (see `sampleMotionProjectDefsAtTime`), not a
     * layer-relative local time.
     */
    tracks: V2TrackListSchema.optional(),
  })
  .strict()
  .superRefine((filter, ctx) => {
    const ids = new Set<string>();
    const results = new Set<string>();
    filter.primitives.forEach((primitive, index) => {
      if (ids.has(primitive.id)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate filter primitive id: ${primitive.id}`, path: ["primitives", index, "id"] });
      }
      ids.add(primitive.id);
      if (primitive.result !== undefined) {
        if (results.has(primitive.result)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate filter result: ${primitive.result}`, path: ["primitives", index, "result"] });
        }
        results.add(primitive.result);
      }
      if (primitive.type === "feColorMatrix" && primitive.kind === "matrix" && primitive.values?.length !== 20) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "feColorMatrix matrix requires exactly 20 values", path: ["primitives", index, "values"] });
      }
      if (primitive.type === "feConvolveMatrix" && primitive.kernelMatrix.length !== primitive.order.x * primitive.order.y) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "feConvolveMatrix kernelMatrix length must match order", path: ["primitives", index, "kernelMatrix"] });
      }
      // The current runtime only executes an isotropic blur/shadow radius
      // (see `isotropicFilterRadius` in motion-compiler, which throws
      // ANISOTROPIC_FILTER_UNSUPPORTED once x !== y). Animating only one axis
      // would make that throw depend on the sampled time instead of failing
      // deterministically at parse time, so require both axes to be animated
      // in exact lockstep whenever either one is.
      if (primitive.type === "feGaussianBlur" || primitive.type === "feDropShadow") {
        const xTrack = filter.tracks?.find((track) => track.path === `primitives.${primitive.id}.stdDeviation.x`);
        const yTrack = filter.tracks?.find((track) => track.path === `primitives.${primitive.id}.stdDeviation.y`);
        if (Boolean(xTrack) !== Boolean(yTrack)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Isotropic stdDeviation requires animating both x and y together: ${primitive.id}`, path: ["primitives", index, "stdDeviation"] });
        } else if (xTrack && yTrack && !sameNumericKeyframes(xTrack.keyframes, yTrack.keyframes)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `stdDeviation.x and stdDeviation.y tracks must share identical keyframes for isotropic blur/shadow: ${primitive.id}`, path: ["primitives", index, "stdDeviation"] });
        }
      }
    });
  });

function sameNumericKeyframes(left: readonly { time: number; value: { type: string; value?: unknown } }[], right: readonly { time: number; value: { type: string; value?: unknown } }[]): boolean {
  return left.length === right.length && left.every((keyframe, index) => {
    const other = right[index]!;
    return keyframe.time === other.time && keyframe.value.type === "number" && other.value.type === "number" && keyframe.value.value === other.value.value;
  });
}

export const V2FilterListSchema = z
  .array(V2FilterSchema)
  .max(256)
  .superRefine((filters, ctx) => {
    const ids = new Set<string>();
    for (const [index, filter] of filters.entries()) {
      if (ids.has(filter.id)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate filter id: ${filter.id}`, path: [index, "id"] });
      }
      ids.add(filter.id);
    }
  });

export type V2FilterLength = z.infer<typeof V2FilterLengthSchema>;
export type V2FilterInput = z.infer<typeof V2FilterInputSchema>;
export type V2FilterPrimitive = z.infer<typeof V2FilterPrimitiveSchema>;
export type V2Filter = z.infer<typeof V2FilterSchema>;
export type V2FilterList = z.infer<typeof V2FilterListSchema>;
