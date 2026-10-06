import { z } from "zod";
import { V2CompositionSchema } from "./composition";
import { V2IdSchema } from "./common";
import { V2AssetListSchema } from "./assets";
import { V2AudioDomainSchema } from "./audio";
import { V2LayerListSchema } from "./layers";
import { V2MarkerListSchema } from "./markers";
import { V2ClipPathListSchema } from "./clip";
import { V2MaskListSchema, type V2Mask } from "./mask";
import { V2FilterListSchema, type V2Filter } from "./filter";
import { V2PaintServerListSchema, type V2Paint, type V2PaintServerDefinition, type V2PatternContent } from "./paint";
import { resolveV2KeyframeTime } from "./animation";
import type { MotionProtocolV2 } from "./types";

const COMMON_NUMBER_PATHS = new Set([
  "opacity",
  "frame.width",
  "frame.height",
  "transform.translate.x",
  "transform.translate.y",
  "transform.translate.z",
  "transform.scale.x",
  "transform.scale.y",
  "transform.scale.z",
  "transform.rotate.x",
  "transform.rotate.y",
  "transform.rotate.z",
  "transform.skew.x",
  "transform.skew.y",
  "transform.anchor.x",
  "transform.anchor.y",
  "transform.anchor.z",
  "motion.offsetDistance",
  "motion.offsetRotate.angle",
  "motion.offsetAnchor.x",
  "motion.offsetAnchor.y",
]);

const COMMON_ENUM_PATHS = new Set([
  "composite.blendMode",
  "composite.isolation",
  "visibility",
]);

const COMMON_BOOLEAN_PATHS = new Set(["enabled"]);

const GRADIENT_TYPES = new Set(["linear-gradient", "radial-gradient", "conic-gradient"]);

/**
 * Resolves an animatable field inside a gradient paint object (a linear,
 * radial or conic gradient — see `V2GradientFillSchema`). Reused for both a
 * layer's `style.fill`/`style.stroke` and a project paint-server's `paint`,
 * since both hold the exact same gradient shape. Gradient stops have no id
 * (see `V2GradientStopSchema`), so they are addressed by array index; the
 * generic `assignPath` writer in the compiler's sampler already resolves a
 * numeric segment after an array, so no sampler changes are needed here.
 */
function gradientFieldKind(paint: unknown, field: string): Set<string> | null {
  if (typeof paint !== "object" || paint === null) return null;
  const record = paint as Record<string, unknown>;
  if (typeof record.type !== "string" || !GRADIENT_TYPES.has(record.type)) return null;

  const stopMatch = /^stops\.(\d+)\.(color|offset|stopOpacity)$/.exec(field);
  if (stopMatch) {
    const stops = record.stops;
    const index = Number(stopMatch[1]);
    const stopField = stopMatch[2]!;
    if (!Array.isArray(stops) || !stops[index] || typeof stops[index] !== "object" || !(stopField in stops[index])) return null;
    return stopField === "color" ? new Set(["color"]) : new Set(["number"]);
  }
  // Every other animatable gradient field (angle/x1/y1/x2/y2, cx/cy/radius/
  // radiusX/radiusY/fx/fy/fr, from) is a plain finite number already present
  // on the currently-authored gradient object; a field the current gradient
  // type does not declare (e.g. `radius` on a conic gradient) is simply
  // absent here rather than needing a per-type allowlist.
  return field in record && typeof record[field] === "number" ? new Set(["number"]) : null;
}

function trackValueKinds(path: string, layer: MotionProtocolV2["layers"][number]): Set<string> | null {
  if (COMMON_NUMBER_PATHS.has(path)) return new Set(["number"]);
  if (COMMON_ENUM_PATHS.has(path)) return new Set(["enum"]);
  if (COMMON_BOOLEAN_PATHS.has(path)) return new Set(["boolean"]);
  if (layer.type === "group" && layer.render3d?.perspective !== undefined) {
    if (path === "render3d.perspective.distance") return new Set(["number"]);
    if (path === "render3d.perspective.origin") return new Set(["vec2"]);
  }

  const layerPaths: Record<string, Set<string>> = {
    shape: new Set(["payload.cornerRadius", "style.fillOpacity", "style.strokeWidth", "style.strokeOpacity", "style.strokeDash.offset"]),
    path: new Set(["style.fillOpacity", "style.strokeWidth", "style.strokeOpacity", "style.strokeDash.offset", "payload.morph.progress"]),
    text: new Set(),
    image: new Set(["payload.x", "payload.y", "payload.width", "payload.height"]),
    // `playbackRate` is a video-only speed multiplier (see layers/video.ts);
    // animating it enables speed ramps the same way trim already does.
    video: new Set(["payload.trimStart", "payload.trimEnd", "payload.playbackRate"]),
    group: new Set(),
  };
  if (layerPaths[layer.type]?.has(path)) return new Set(["number"]);

  if (layer.type === "text") {
    const segments = path.split(".");
    // Spans are addressed by id across every chunk (span ids are unique for
    // the whole layer) so authoring never needs to know a span's chunk index.
    if (segments[0] === "payload" && segments[1] === "chunks" && segments[2] === "spans" && segments.length >= 4) {
      const span = layer.payload.chunks.flatMap((chunk) => chunk.spans).find((candidate) => candidate.id === segments[3]);
      if (!span) return null;
      const field = segments.slice(4).join(".");
      const spanNumberFields = ["letterSpacing", "wordSpacing", "strokeWidth", "strokeOpacity", "textLength", "fillOpacity"];
      if (spanNumberFields.includes(field)) return new Set(["number"]);
      if (field === "fill" || field === "stroke") return new Set(["color"]);
      if (field === "font.size") return new Set(["number"]);
      return null;
    }
    // Chunks are addressed by id directly (not nested under a literal
    // "spans" segment); a chunk id equal to the literal "spans" is not
    // representable this way and must use a different id.
    if (segments[0] === "payload" && segments[1] === "chunks" && segments[2] !== undefined && segments[2] !== "spans" && segments.length >= 4) {
      const chunk = layer.payload.chunks.find((candidate) => candidate.id === segments[2]);
      if (!chunk) return null;
      const field = segments.slice(3).join(".");
      if (field === "textPath.startOffset") return new Set(["number"]);
      return null;
    }
  }

  const colorPaths = layer.type === "shape"
    ? new Set(["style.fill", "style.stroke"])
    : layer.type === "path"
      ? new Set(["style.fill", "style.stroke"])
      : new Set<string>();
  if (colorPaths.has(path)) return new Set(["color"]);

  if ((layer.type === "shape" || layer.type === "path") && (path.startsWith("style.fill.") || path.startsWith("style.stroke."))) {
    const paintProperty = path.startsWith("style.fill.") ? "fill" : "stroke";
    const field = path.slice(`style.${paintProperty}.`.length);
    const kind = gradientFieldKind(layer.style[paintProperty], field);
    if (kind) return kind;
  }

  const enumPaths = layer.type === "image"
      ? new Set(["payload.fit", "payload.preserveAspectRatio.align", "payload.preserveAspectRatio.meetOrSlice", "payload.imageRendering"])
      : layer.type === "video"
        ? new Set(["payload.fit"])
      : new Set<string>();
  if (enumPaths.has(path)) return new Set(["enum"]);

  return null;
}

/**
 * Animatable fields for a project-level SVG filter definition (`V2Filter`).
 * A filter has no `timing.start`; its tracks are sampled at absolute
 * composition time by `sampleMotionProjectDefsAtTime`, not this schema.
 */
function filterTrackValueKinds(filter: V2Filter, path: string): Set<string> | null {
  const segments = path.split(".");
  if (segments[0] !== "primitives" || segments.length < 3) return null;
  const primitive = filter.primitives.find((candidate) => candidate.id === segments[1]);
  if (!primitive) return null;
  const field = segments.slice(2).join(".");
  const numberFieldsByType: Record<string, readonly string[]> = {
    feGaussianBlur: ["stdDeviation.x", "stdDeviation.y"],
    feDropShadow: ["dx", "dy", "stdDeviation.x", "stdDeviation.y", "floodOpacity"],
    feFlood: ["opacity"],
    feOffset: ["dx", "dy"],
    feColorMatrix: (primitive.type === "feColorMatrix" ? (primitive.values ?? []).map((_, i) => `values.${i}`) : []),
  };
  if (numberFieldsByType[primitive.type]?.includes(field)) return new Set(["number"]);
  if (primitive.type === "feDropShadow" && field === "floodColor") return new Set(["color"]);
  if (primitive.type === "feFlood" && field === "color") return new Set(["color"]);
  return null;
}

/** Animatable fields for a project-level mask definition (`V2Mask`). */
function maskTrackValueKinds(mask: V2Mask, path: string): Set<string> | null {
  const numberPaths = new Set(["x", "y", "width", "height", "image.x", "image.y", "image.width", "image.height", "image.opacity"]);
  if (!numberPaths.has(path)) return null;
  // `x`/`y`/`width`/`height` accept a plain number or an explicit
  // `{ value, unit: "percent" }` object (V2MaskLengthSchema); only the plain
  // number form is animatable through the generic path writer today.
  const value = path.split(".").reduce<unknown>((current, segment) => (
    current && typeof current === "object" ? (current as Record<string, unknown>)[segment] : undefined
  ), mask);
  return typeof value === "number" ? new Set(["number"]) : null;
}

/** Animatable fields for a project-level paint-server definition, reusing the gradient sub-property rules from a layer's `style.fill`. */
function paintServerTrackValueKinds(definition: V2PaintServerDefinition, path: string): Set<string> | null {
  if (!path.startsWith("paint.")) return null;
  return gradientFieldKind(definition.paint, path.slice("paint.".length));
}

/** Validates every def collection's `tracks` (filters/masks/paintServers) against its own field allowlist, reporting under the given JSON path prefix. */
function validateDefTracks<T extends { id: string; tracks?: readonly { id: string; path: string; keyframes: readonly { time: number; value: { type: string } }[] }[] }>(
  definitions: readonly T[] | undefined,
  collectionPath: string,
  valueKinds: (definition: T, path: string) => Set<string> | null,
  ctx: z.RefinementCtx,
): void {
  (definitions ?? []).forEach((definition, definitionIndex) => {
    (definition.tracks ?? []).forEach((track, trackIndex) => {
      const allowedKinds = valueKinds(definition, track.path);
      const path = [collectionPath, definitionIndex, "tracks", trackIndex, "path"];
      if (!allowedKinds) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Track path does not identify an animatable property on ${collectionPath}[${definitionIndex}] (${definition.id}): ${track.path}`, path });
        return;
      }
      if (track.keyframes.some((keyframe) => !allowedKinds.has(keyframe.value.type))) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Track value type does not match property path: ${track.path}`, path: [collectionPath, definitionIndex, "tracks", trackIndex, "keyframes"] });
      }
    });
  });
}

export const MotionProtocolV2Schema = z
  .object({
    format: z.literal("motion-protocol"),
    formatVersion: z.literal(2),
    id: V2IdSchema,
    composition: V2CompositionSchema,
    assets: V2AssetListSchema,
    markers: V2MarkerListSchema.optional(),
    clipPaths: V2ClipPathListSchema.optional(),
    masks: V2MaskListSchema.optional(),
    filters: V2FilterListSchema.optional(),
    /** SVG paint-server definitions referenced by fill/stroke paint values. */
    paintServers: V2PaintServerListSchema.optional(),
    layers: V2LayerListSchema,
    audio: V2AudioDomainSchema,
  })
  .strict()
  .superRefine((project, ctx) => {
    const markerIds = new Set((project.markers ?? []).map((marker) => marker.id));
    const clipPathIds = new Set((project.clipPaths ?? []).map((clipPath) => clipPath.id));
    const maskIds = new Set((project.masks ?? []).map((mask) => mask.id));
    const filterIds = new Set((project.filters ?? []).map((filter) => filter.id));
    const paintServerIds = new Set((project.paintServers ?? []).map((paintServer) => paintServer.id));
    const ids = new Set<string>();
    const ordersByParent = new Map<string | null, Set<number>>();
    const assetIds = new Set<string>();
    const assetById = new Map<string, MotionProtocolV2["assets"][number]>();
    const layerById = new Map(project.layers.map((layer) => [layer.id, layer]));
    for (const [index, layer] of project.layers.entries()) {
      if (layer.type === "text" && layer.payload.layout?.textOverflow === "ellipsis" && layer.clipPath === undefined) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "Text ellipsis requires a deterministic clipPath",
          path: ["layers", index, "payload", "layout", "textOverflow"],
        });
      }
    }

    const checkPaintReferences = (paint: V2Paint | undefined, path: (string | number)[], seen = new Set<string>()): void => {
      if (!paint || typeof paint === "string") return;
      if (paint.type === "reference") {
        if (!paintServerIds.has(paint.id)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown paint server reference: ${paint.id}`, path: [...path, "id"] });
        } else if (seen.has(paint.id)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Paint server reference cycle: ${paint.id}`, path: [...path, "id"] });
        }
        return;
      }
      if ((paint.type === "linear-gradient" || paint.type === "radial-gradient" || paint.type === "conic-gradient" || paint.type === "pattern") && paint.href) {
        if (!paintServerIds.has(paint.href)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown paint server href: ${paint.href}`, path: [...path, "href"] });
        }
      }
      if (paint.type === "pattern") {
        paint.content?.forEach((node: V2PatternContent, index: number) => checkPatternNode(node, [...path, "content", index], seen));
      }
    };
    const checkPatternNode = (node: V2PatternContent, path: (string | number)[], seen: Set<string>): void => {
      if (node.type === "group") {
        node.children.forEach((child: V2PatternContent, index: number) => checkPatternNode(child, [...path, "children", index], seen));
        return;
      }
      checkPaintReferences(node.fill, [...path, "fill"], seen);
      checkPaintReferences(node.stroke, [...path, "stroke"], seen);
    };
    (project.paintServers ?? []).forEach((definition, index) => checkPaintReferences(definition.paint, ["paintServers", index, "paint"]));
    for (const [index, asset] of project.assets.entries()) {
      if (assetIds.has(asset.id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Duplicate asset id: ${asset.id}`,
          path: ["assets", index, "id"],
        });
      }
      assetIds.add(asset.id);
      assetById.set(asset.id, asset);
    }
    for (const [layerIndex, layer] of project.layers.entries()) {
      if (layer.type !== "text") continue;
      for (const [chunkIndex, chunk] of layer.payload.chunks.entries()) {
        for (const [spanIndex, span] of chunk.spans.entries()) {
          for (const [assetIndex, assetId] of (span.resolvedFontAssetIds ?? []).entries()) {
            const asset = assetById.get(assetId);
            const path = ["layers", layerIndex, "payload", "chunks", chunkIndex, "spans", spanIndex, "resolvedFontAssetIds", assetIndex] as (string | number)[];
            if (!asset) {
              ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown resolved font asset: ${assetId}`, path });
            } else if (asset.kind !== "font") {
              ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Resolved text asset must be a font: ${assetId}`, path });
            }
          }
        }
      }
    }
    const trackIds = new Set<string>();
    const audioClipIds = new Set<string>();
    for (const [trackIndex, track] of project.audio.tracks.entries()) {
      if (trackIds.has(track.id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Duplicate audio track id: ${track.id}`,
          path: ["audio", "tracks", trackIndex, "id"],
        });
      }
      trackIds.add(track.id);
      for (const [clipIndex, clip] of track.clips.entries()) {
        if (audioClipIds.has(clip.id)) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `Duplicate audio clip id: ${clip.id}`,
            path: ["audio", "tracks", trackIndex, "clips", clipIndex, "id"],
          });
        }
        audioClipIds.add(clip.id);
        const source = project.assets.find((asset) => asset.id === clip.assetId);
        if (!source) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `Unknown audio asset: ${clip.assetId}`,
            path: ["audio", "tracks", trackIndex, "clips", clipIndex, "assetId"],
          });
        } else if (source.kind !== "audio" && source.kind !== "video") {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `Audio clip must reference an audio or video asset: ${clip.assetId}`,
            path: ["audio", "tracks", trackIndex, "clips", clipIndex, "assetId"],
          });
        }
      }
    }
    for (const [index, layer] of project.layers.entries()) {
      if (ids.has(layer.id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Duplicate layer id: ${layer.id}`,
          path: ["layers", index, "id"],
        });
      }
      ids.add(layer.id);
      if (layer.type === "shape" || layer.type === "path") {
        checkPaintReferences(layer.style.fill, ["layers", index, "style", "fill"]);
        checkPaintReferences(layer.style.stroke, ["layers", index, "style", "stroke"]);
        for (const field of ["markerStart", "markerMid", "markerEnd"] as const) {
          const markerId = layer.style[field];
          if (markerId !== undefined && !markerIds.has(markerId)) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: `Unknown marker reference: ${markerId}`,
              path: ["layers", index, "style", field],
            });
          }
        }
      }
      if (layer.clipPath !== undefined && !clipPathIds.has(layer.clipPath)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown clipPath reference: ${layer.clipPath}`, path: ["layers", index, "clipPath"] });
      }
      if (layer.mask !== undefined && !maskIds.has(layer.mask)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown mask reference: ${layer.mask}`, path: ["layers", index, "mask"] });
      }
      for (const [maskLayerIndex, maskLayer] of (layer.maskLayers ?? []).entries()) {
        for (const [maskIdIndex, maskId] of maskLayer.maskIds.entries()) {
          if (!maskIds.has(maskId)) {
            ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown mask reference: ${maskId}`, path: ["layers", index, "maskLayers", maskLayerIndex, "maskIds", maskIdIndex] });
          }
        }
      }
      for (const [maskIndex, mask] of (project.masks ?? []).entries()) {
        if (mask.image && !assetIds.has(mask.image.assetId)) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown mask image asset: ${mask.image.assetId}`, path: ["masks", maskIndex, "image", "assetId"] });
        }
      }
      if (layer.filter !== undefined && !filterIds.has(layer.filter)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown filter reference: ${layer.filter}`, path: ["layers", index, "filter"] });
      }
      if (layer.parentLayerId !== null) {
        const parent = layerById.get(layer.parentLayerId);
        if (!parent) {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Unknown parent layer: ${layer.parentLayerId}`, path: ["layers", index, "parentLayerId"] });
        } else if (parent.type !== "group") {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Only group layers can parent child layers", path: ["layers", index, "parentLayerId"] });
        }
        const ancestry = new Set<string>();
        let current: string | null = layer.parentLayerId;
        while (current !== null) {
          if (ancestry.has(current) || current === layer.id) {
            ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Layer parent hierarchy contains a cycle", path: ["layers", index, "parentLayerId"] });
            break;
          }
          ancestry.add(current);
          current = layerById.get(current)?.parentLayerId ?? null;
        }
      }
      const siblingOrders = ordersByParent.get(layer.parentLayerId) ?? new Set<number>();
      if (siblingOrders.has(layer.order)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Duplicate order in sibling scope: ${layer.order}`,
          path: ["layers", index, "order"],
        });
      }
      siblingOrders.add(layer.order);
      ordersByParent.set(layer.parentLayerId, siblingOrders);
      for (const [trackIndex, track] of (layer.tracks ?? []).entries()) {
        const allowedKinds = trackValueKinds(track.path, layer);
        if (!allowedKinds) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `Track path does not identify an animatable property on layer ${layer.id}: ${track.path}`,
            path: ["layers", index, "tracks", trackIndex, "path"],
          });
        } else if (track.keyframes.some((keyframe) => !allowedKinds.has(keyframe.value.type))) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `Track value type does not match property path: ${track.path}`,
            path: ["layers", index, "tracks", trackIndex, "keyframes"],
          });
        }
        // A looping track's keyframes describe one cycle, bounded by
        // animation.durationMs rather than the layer's own duration — the
        // compiler repeats/clips that cycle across layer.timing.duration
        // per `animation.iterations`/`direction`/`fillMode`. An ordinary
        // track stays bounded by layer.timing.duration, as before. Ordering
        // and bounds are both checked here (rather than inside V2TrackSchema
        // itself) because resolving an `anchor: "end"` keyframe time
        // requires this bound.
        const boundMs = track.animation?.durationMs ?? layer.timing.duration;
        let previousResolvedTime = -Infinity;
        for (const [keyframeIndex, keyframe] of track.keyframes.entries()) {
          const resolvedTime = resolveV2KeyframeTime(keyframe.time, boundMs);
          if (resolvedTime <= previousResolvedTime) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: `Track keyframe times must be strictly increasing: ${track.path}`,
              path: ["layers", index, "tracks", trackIndex, "keyframes", keyframeIndex, "time"],
            });
          }
          previousResolvedTime = resolvedTime;
          if (resolvedTime < 0 || resolvedTime > boundMs) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: track.animation
                ? `Track keyframe time cannot exceed animation.durationMs: ${track.path}`
                : `Track keyframe time cannot exceed layer duration: ${track.path}`,
              path: ["layers", index, "tracks", trackIndex, "keyframes", keyframeIndex, "time"],
            });
          }
        }
      }
      if (layer.type === "image") {
        const source = project.assets.find((asset) => asset.id === layer.payload.assetId);
        if (source && source.kind !== "image") {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `Image layer must reference an image asset: ${layer.payload.assetId}`,
            path: ["layers", index, "payload", "assetId"],
          });
        }
      }
      if (layer.type === "video" && layer.payload.audio) {
        for (const [field, fade] of [["fadeIn", layer.payload.audio.fadeIn], ["fadeOut", layer.payload.audio.fadeOut]] as const) {
          if (fade && fade.duration > layer.timing.duration) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: `Video embedded audio ${field} duration cannot exceed video duration`,
              path: ["layers", index, "payload", "audio", field, "duration"],
            });
          }
        }
      }
      if (layer.type === "video") {
        const source = project.assets.find((asset) => asset.id === layer.payload.assetId);
        if (source?.kind === "video" && source.duration !== undefined) {
          const trimStart = layer.payload.trimStart ?? 0;
          const trimEnd = Math.min(layer.payload.trimEnd ?? source.duration, source.duration);
          const availableDuration = trimEnd - trimStart;
          if (availableDuration > 0 && layer.timing.duration > availableDuration) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: `Video timing duration cannot exceed the selected source range (${availableDuration}ms)`,
              path: ["layers", index, "timing", "duration"],
            });
          }
          if (layer.payload.trimStart !== undefined && layer.payload.trimStart >= source.duration) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
            message: `Video trimStart cannot reach or exceed source duration (${source.duration}ms)`,
              path: ["layers", index, "payload", "trimStart"],
            });
          }
          if (layer.payload.trimEnd !== undefined && layer.payload.trimEnd > source.duration) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
            message: `Video trimEnd cannot exceed source duration (${source.duration}ms)`,
              path: ["layers", index, "payload", "trimEnd"],
            });
          }
        }
      }
    }
    validateDefTracks(project.filters, "filters", filterTrackValueKinds, ctx);
    validateDefTracks(project.masks, "masks", maskTrackValueKinds, ctx);
    validateDefTracks(project.paintServers, "paintServers", paintServerTrackValueKinds, ctx);
  }) as z.ZodType<MotionProtocolV2>;

export type { MotionProtocolV2 } from "./types";
