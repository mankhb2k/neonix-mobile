import { z } from "zod";
import {
  V2FiniteNumberSchema,
  V2IdSchema,
  V2MillisecondsSchema,
  V2NonNegativeNumberSchema,
  V2PositiveMillisecondsSchema,
  V2PositiveNumberSchema,
} from "./common";

/** A finite scalar or fixed-size value that can be sampled over time. */
const V2Vec2ValueSchema = z
  .tuple([V2FiniteNumberSchema, V2FiniteNumberSchema])
  .readonly();
const V2Vec3ValueSchema = z
  .tuple([V2FiniteNumberSchema, V2FiniteNumberSchema, V2FiniteNumberSchema])
  .readonly();
const V2Vec4ValueSchema = z
  .tuple([
    V2FiniteNumberSchema,
    V2FiniteNumberSchema,
    V2FiniteNumberSchema,
    V2FiniteNumberSchema,
  ])
  .readonly();

/**
 * Typed values keep interpolation deterministic and prevent a track from
 * silently changing a property's type. Colors are RGBA components in 0..1.
 */
export const V2AnimatableValueSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("number"), value: V2FiniteNumberSchema }).strict(),
  z.object({ type: z.literal("vec2"), value: V2Vec2ValueSchema }).strict(),
  z.object({ type: z.literal("vec3"), value: V2Vec3ValueSchema }).strict(),
  z.object({ type: z.literal("vec4"), value: V2Vec4ValueSchema }).strict(),
  z
    .object({
      type: z.literal("color"),
      value: z
        .tuple([
          V2FiniteNumberSchema.min(0).max(1),
          V2FiniteNumberSchema.min(0).max(1),
          V2FiniteNumberSchema.min(0).max(1),
          V2FiniteNumberSchema.min(0).max(1),
        ])
        .readonly(),
    })
    .strict(),
  z.object({ type: z.literal("boolean"), value: z.boolean() }).strict(),
  z.object({ type: z.literal("string"), value: z.string() }).strict(),
  z.object({ type: z.literal("enum"), value: z.string().min(1) }).strict(),
]);

export type V2AnimatableValue = z.infer<typeof V2AnimatableValueSchema>;

/** Runtime animation policy for a track. Times remain milliseconds to match V2 keyframes. */
export const V2AnimationPlaybackSchema = z
  .object({
    durationMs: V2PositiveMillisecondsSchema,
    delayMs: V2FiniteNumberSchema,
    iterations: z.union([V2NonNegativeNumberSchema, z.literal("infinite")]),
    direction: z.enum(["normal", "reverse", "alternate", "alternate-reverse"]),
    fillMode: z.enum(["none", "forwards", "backwards", "both"]),
    playState: z.enum(["running", "paused"]),
  })
  .strict()
  .default({
    durationMs: 1,
    delayMs: 0,
    iterations: 1,
    direction: "normal",
    fillMode: "none",
    playState: "running",
  });

export type V2AnimationPlayback = z.infer<typeof V2AnimationPlaybackSchema>;

/** @deprecated Use V2AnimationPlaybackSchema. */
export const V2TrackPlaybackSchema = V2AnimationPlaybackSchema;
/** @deprecated Use V2AnimationPlayback. */
export type V2TrackPlayback = V2AnimationPlayback;

/** Temporal interpolation is attached to the segment leaving a keyframe. */
export const V2EasingSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("linear") }).strict(),
  z
    .object({
      type: z.literal("step"),
      count: V2PositiveNumberSchema.int().default(1),
      position: z.enum(["jump-start", "jump-end", "jump-none", "jump-both"]).default("jump-end"),
    })
    .strict(),
  z
    .object({
      type: z.literal("cubicBezier"),
      x1: V2FiniteNumberSchema.min(0).max(1),
      y1: V2FiniteNumberSchema,
      x2: V2FiniteNumberSchema.min(0).max(1),
      y2: V2FiniteNumberSchema,
    })
    .strict(),
  z
    .object({
      type: z.literal("spring"),
      mass: V2FiniteNumberSchema.positive(),
      stiffness: V2FiniteNumberSchema.positive(),
      damping: V2FiniteNumberSchema.nonnegative(),
      velocity: V2FiniteNumberSchema.optional(),
    })
    .strict(),
]);

export type V2Easing = z.infer<typeof V2EasingSchema>;

/**
 * Property paths are dot-separated leaf paths. An id-addressed segment (e.g.
 * a filter primitive id in `primitives.<id>.<field>`, see `filter.ts`)
 * occupies exactly one segment, so an id used this way must not contain a dot.
 */
export const V2PropertyPathSchema = z
  .string()
  .trim()
  .min(1)
  .max(200)
  .regex(
    /^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/,
    "Property path must contain dot-separated non-empty segments",
  );

export type V2PropertyPath = z.infer<typeof V2PropertyPathSchema>;

export const V2InterpolationSchema = z
  .object({
    type: z.enum(["linear", "discrete"]),
  })
  .strict();

export type V2Interpolation = z.infer<typeof V2InterpolationSchema>;

export const V2KeyframeSchema = z
  .object({
    /** Local time relative to the owning layer, in milliseconds. */
    time: V2MillisecondsSchema,
    value: V2AnimatableValueSchema,
    /** Easing from this keyframe to the next one. */
    easing: V2EasingSchema.optional(),
  })
  .strict();

export type V2Keyframe = z.infer<typeof V2KeyframeSchema>;

export const V2TrackSchema = z
  .object({
    id: V2IdSchema,
    path: V2PropertyPathSchema,
    keyframes: z.array(V2KeyframeSchema).min(1),
    interpolation: V2InterpolationSchema.optional(),
    animation: V2AnimationPlaybackSchema.optional(),
  })
  .strict()
  .superRefine((track, ctx) => {
    for (let index = 1; index < track.keyframes.length; index += 1) {
      const previous = track.keyframes[index - 1]!;
      const current = track.keyframes[index]!;
      if (current.time <= previous.time) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "Track keyframe times must be strictly increasing",
          path: ["keyframes", index, "time"],
        });
      }
    }
  });

export type V2Track = z.infer<typeof V2TrackSchema>;

/** Shared duplicate-id/duplicate-path validation for a list of tracks, regardless of keyframe time shape. */
function validateTrackListIds(
  tracks: readonly { id: string; path: string }[],
  ctx: z.RefinementCtx,
): void {
  const ids = new Set<string>();
  const paths = new Set<string>();
  for (const [index, track] of tracks.entries()) {
    if (ids.has(track.id)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `Duplicate layer track id: ${track.id}`,
        path: [index, "id"],
      });
    }
    ids.add(track.id);
    if (paths.has(track.path)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `Duplicate animated property path: ${track.path}`,
        path: [index, "path"],
      });
    }
    paths.add(track.path);
  }
}

export const V2TrackListSchema = z
  .array(V2TrackSchema)
  .superRefine(validateTrackListIds);

export type V2TrackList = z.infer<typeof V2TrackListSchema>;

/**
 * Layer-scoped keyframe time. A bare number is shorthand for
 * `{ anchor: "start", offsetMs: time }` and is fully backward compatible
 * with every existing document. `anchor: "end"` is resolved against a bound
 * (the owning layer's `timing.duration`, or `animation.durationMs` for a
 * looping track) by `resolveV2KeyframeTime`, letting an "out" animation
 * stay correctly placed when a clip is trimmed or extended instead of
 * requiring the editor to recompute absolute keyframe times by hand.
 *
 * This anchor concept only applies to layer tracks: definition-level tracks
 * (filters/masks/paintServers) are sampled at absolute composition time and
 * have no layer duration to anchor "end" against, so they keep using the
 * plain-number-only `V2KeyframeSchema`/`V2TrackSchema` above, unchanged.
 */
export const V2KeyframeAnchorSchema = z.enum(["start", "end"]);

export const V2AnchoredKeyframeTimeSchema = z
  .object({
    anchor: V2KeyframeAnchorSchema,
    offsetMs: V2MillisecondsSchema,
  })
  .strict();

export const V2KeyframeTimeSchema = z.union([
  V2MillisecondsSchema,
  V2AnchoredKeyframeTimeSchema,
]);

export type V2KeyframeAnchor = z.infer<typeof V2KeyframeAnchorSchema>;
export type V2AnchoredKeyframeTime = z.infer<typeof V2AnchoredKeyframeTimeSchema>;
export type V2KeyframeTime = z.infer<typeof V2KeyframeTimeSchema>;

/**
 * Resolves a layer-track keyframe time to an absolute layer-local
 * millisecond offset. `boundMs` is the owning layer's `timing.duration` for
 * an ordinary track, or `track.animation.durationMs` (the length of one
 * cycle) for a looping track — see the "Animation and timing" README
 * section for the full normative spec.
 */
export function resolveV2KeyframeTime(time: V2KeyframeTime, boundMs: number): number {
  if (typeof time === "number") return time;
  return time.anchor === "start" ? time.offsetMs : boundMs - time.offsetMs;
}

export const V2LayerKeyframeSchema = z
  .object({
    time: V2KeyframeTimeSchema,
    value: V2AnimatableValueSchema,
    /** Easing from this keyframe to the next one. */
    easing: V2EasingSchema.optional(),
  })
  .strict();

export type V2LayerKeyframe = z.infer<typeof V2LayerKeyframeSchema>;

/**
 * Keyframe ordering and bounds are validated at the project level (see
 * `project.ts`), not here, because resolving `anchor: "end"` requires the
 * owning layer's `timing.duration` (or `animation.durationMs`), which isn't
 * available at this schema's scope.
 */
export const V2LayerTrackSchema = z
  .object({
    id: V2IdSchema,
    path: V2PropertyPathSchema,
    keyframes: z.array(V2LayerKeyframeSchema).min(1),
    interpolation: V2InterpolationSchema.optional(),
    animation: V2AnimationPlaybackSchema.optional(),
  })
  .strict()
  .superRefine((track, ctx) => {
    if (!track.animation) return;
    for (const [index, keyframe] of track.keyframes.entries()) {
      if (typeof keyframe.time !== "number" && keyframe.time.anchor === "end") {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "End-anchored keyframe time cannot be combined with a looping animation",
          path: ["keyframes", index, "time"],
        });
      }
    }
  });

export type V2LayerTrack = z.infer<typeof V2LayerTrackSchema>;

export const V2LayerTrackListSchema = z
  .array(V2LayerTrackSchema)
  .superRefine(validateTrackListIds);

export type V2LayerTrackList = z.infer<typeof V2LayerTrackListSchema>;
