import { z } from "zod";
import { V2GroupLayerSchema, type V2GroupLayer } from "./group";
import { V2ImageLayerSchema, type V2ImageLayer } from "./image";
import { V2PathLayerSchema, type V2PathLayer } from "./path";
import { V2ShapeLayerSchema, type V2ShapeLayer } from "./shape";
import { V2TextLayerSchema, type V2TextLayer } from "./text";
import { V2VideoLayerSchema, type V2VideoLayer } from "./video";

export {
  V2LayerBaseSchema,
  V2FrameSchema,
  V2BlendModeSchema,
  V2IsolationModeSchema,
  V2VisibilitySchema,
  V2CompositeSchema,
  V2PaintOrderSchema,
  V2PaintOrderItemSchema,
  type V2Frame,
  type V2BlendMode,
  type V2IsolationMode,
  type V2Composite,
  type V2Visibility,
  type V2PaintOrder,
  type V2PaintOrderItem,
} from "./base";
export {
  V2AnimatableValueSchema,
  V2EasingSchema,
  V2InterpolationSchema,
  V2KeyframeSchema,
  V2PropertyPathSchema,
  V2TrackSchema,
  V2TrackListSchema,
  V2KeyframeAnchorSchema,
  V2AnchoredKeyframeTimeSchema,
  V2KeyframeTimeSchema,
  V2LayerKeyframeSchema,
  V2LayerTrackSchema,
  V2LayerTrackListSchema,
  resolveV2KeyframeTime,
  type V2AnimatableValue,
  type V2Easing,
  type V2Interpolation,
  type V2Keyframe,
  type V2PropertyPath,
  type V2Track,
  type V2TrackList,
  type V2KeyframeAnchor,
  type V2AnchoredKeyframeTime,
  type V2KeyframeTime,
  type V2LayerKeyframe,
  type V2LayerTrack,
  type V2LayerTrackList,
} from "../animation";
export { V2GroupLayerSchema, type V2GroupLayer } from "./group";
export {
  V2ImageAlignSchema,
  V2ImagePreserveAspectRatioSchema,
  V2ImageRenderingSchema,
  V2ImageLayerSchema,
  type V2ImageAlign,
  type V2ImagePreserveAspectRatio,
  type V2ImageRendering,
  type V2ImageLayer,
} from "./image";
export {
  V2ShapeLayerSchema,
  type V2ShapeLayer,
} from "./shape";
export {
  V2TextFontSchema,
  V2TextDecorationStyleSchema,
  V2TextLayoutSchema,
  V2TextSpanSchema,
  V2TextPathSchema,
  V2TextChunkSchema,
  V2TextSourceSchema,
  V2TextRangeSelectorSchema,
  V2TextLayerSchema,
  type V2TextRange,
  type V2TextFont,
  type V2TextDecorationStyle,
  type V2TextLayout,
  type V2TextSpan,
  type V2TextPath,
  type V2TextChunk,
  type V2TextSource,
  type V2TextRangeSelector,
  type V2TextLayer,
} from "./text";
export {
  V2PathContourSchema,
  V2PathPointSchema,
  V2PathSegmentSchema,
  V2PathLayerSchema,
  type V2PathLayer,
} from "./path";
export { V2VideoFitSchema, V2VideoFramePolicySchema, V2VideoLayerSchema, type V2VideoFit, type V2VideoFramePolicy, type V2VideoLayer } from "./video";
export {
  V2BackfaceVisibilitySchema,
  V2PerspectiveContextSchema,
  V2Render3DSchema,
  V2TransformStyleSchema,
  type V2BackfaceVisibility,
  type V2PerspectiveContext,
  type V2Render3D,
  type V2TransformStyle,
} from "../render3d";

export type V2Layer = V2GroupLayer | V2ImageLayer | V2VideoLayer | V2ShapeLayer | V2PathLayer | V2TextLayer;

export const V2LayerSchema: z.ZodType<V2Layer, z.ZodTypeDef, unknown> = z.discriminatedUnion("type", [
  V2GroupLayerSchema,
  V2ImageLayerSchema,
  V2ShapeLayerSchema,
  V2TextLayerSchema,
  V2PathLayerSchema,
  V2VideoLayerSchema,
]);

export const V2LayerListSchema: z.ZodType<V2Layer[], z.ZodTypeDef, unknown> = z.array(V2LayerSchema);
