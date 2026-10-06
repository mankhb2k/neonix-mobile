import { z } from "zod";
import {
  V2ColorSchema,
  V2FiniteNumberSchema,
  V2IdSchema,
  V2NonNegativeNumberSchema,
  V2PositiveNumberSchema,
} from "../common";
import { V2TimingSchema } from "../timing";
import { V2TransformSchema } from "../transform";
import { V2LayerTrackListSchema } from "../animation";
import { V2BackfaceVisibilitySchema } from "../render3d";
import { V2CompositeSchema } from "../blend";
import { V2MaskLayerListSchema } from "../mask";
import { V2MotionPathSchema } from "../motion-path";

// Compatibility exports: blend semantics now live in v2/blend.ts.
export {
  V2BlendModeSchema,
  V2IsolationModeSchema,
  V2CompositeSchema,
  type V2BlendMode,
  type V2IsolationMode,
  type V2Composite,
} from "../blend";

export const V2FrameSchema = z
  .object({
    width: V2PositiveNumberSchema,
    height: V2PositiveNumberSchema,
  })
  .strict();

export { V2PaintOrderSchema, V2PaintOrderItemSchema } from "../common";
export type { V2PaintOrder, V2PaintOrderItem } from "../common";

/** SVG visibility presentation property. */
export const V2VisibilitySchema = z.enum(["visible", "hidden", "collapse"]);

export const V2LayerBaseSchema = z
  .object({
    id: V2IdSchema,
    parentLayerId: V2IdSchema.nullable(),
    /** Paint order within the layer's sibling scope. Higher values paint later. */
    order: V2NonNegativeNumberSchema.int(),
    frame: V2FrameSchema,
    transform: V2TransformSchema,
    /** Source alpha shared by normal and non-normal blend modes. */
    opacity: V2FiniteNumberSchema.min(0).max(1).default(1),
    /** SVG inherited `color` property used by currentColor paint. */
    color: V2ColorSchema.optional(),
    /** Editor/runtime enable state; omitted means enabled. */
    enabled: z.boolean().optional(),
    /** SVG visibility presentation property; omitted means visible. */
    visibility: V2VisibilitySchema.optional(),
    /** Whether the reverse side of the accumulated 3D transform may paint. */
    backfaceVisibility: V2BackfaceVisibilitySchema.optional(),
    /** SVG presentation references resolved against project clipPath definitions. */
    clipPath: V2IdSchema.optional(),
    /** SVG presentation reference resolved against project mask definitions. */
    mask: V2IdSchema.optional(),
    /** CSS mask-image stack. maskIds within one entry are repeated tiles; composite applies between entries. */
    maskLayers: V2MaskLayerListSchema.optional(),
    /**
     * SVG filter reference resolved against project filter definitions —
     * the atomic representation of this layer's own-source effect graph.
     * Per CLAUDE.md's "Protocol V2 stays atomic" rule, there is no
     * `effects: V2Effect[]` field: a named effect (glow, blur, sepia, ...)
     * is an Editor-tier preset that compiles down into the primitive chain
     * this filter points to.
     */
    filter: V2IdSchema.optional(),
    /**
     * Same idea as `filter`, but for the CSS `backdrop-filter` contract
     * (samples the already-painted backdrop, not this layer's own source).
     */
    backdropFilter: V2IdSchema.optional(),
    /** CSS offset-* semantics owned by this layer; motion does not affect layout. */
    motion: V2MotionPathSchema.optional(),
    composite: V2CompositeSchema.optional(),
    timing: V2TimingSchema,
    /** Optional local property tracks; omitted for static layers. */
    tracks: V2LayerTrackListSchema.optional(),
  })
  .strict();

export type V2Frame = z.infer<typeof V2FrameSchema>;
export type V2Visibility = z.infer<typeof V2VisibilitySchema>;
