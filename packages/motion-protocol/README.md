# `@motionvideo/motion-protocol`

Protocol V2 is Neonix's strict, renderer-neutral authoring JSON. It preserves
the supported SVG semantics as data: geometry, presentation properties,
transform lists, paint servers, references, timing, and media metadata remain
readable before the Compiler lowers them to Runtime V3.

The canonical contract is the Zod schema in `src/v2`. The generated JSON
Schema is `schema/v2.json`. Unknown properties are rejected at every strict
object boundary.

This package owns authoring data only. It does not expose Runtime IR, Matrix4
buffers, decoded media, GPU resources, preview state, or export commands.

## Public API

```ts
import {
  MotionProtocolV2Schema,
  parseMotionProtocol,
  serializeMotionProtocol,
  type MotionProtocolV2,
} from "@motionvideo/motion-protocol";

// Strict current-schema validation.
const project: MotionProtocolV2 = MotionProtocolV2Schema.parse(input);

// Public parser for persisted input. It applies the small additive V2
// migration first, then validates the result with MotionProtocolV2Schema.
const parsed = parseMotionProtocol(input);
const json = serializeMotionProtocol(parsed);
```

The explicit V2 entrypoint is also available:

```ts
import { MotionProtocolV2Schema } from "@motionvideo/motion-protocol/v2";
```

There is no V1 or `./runtime` schema entrypoint in this package.

## SVG semantic map

Protocol V2 is a normalized JSON representation of the supported SVG model;
it is not an XML serializer and does not claim to implement every SVG element.
The mapping is intentionally one-to-one at the semantic boundary:

| SVG semantic | Protocol V2 representation |
| --- | --- |
| `<svg>` viewport and root coordinate system | `composition` and `composition.view` |
| `<g>` | A `type: "group"` layer; descendants use `parentLayerId` |
| `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>` | A `type: "shape"` layer with `payload.shape` |
| `<path>` | A `type: "path"` layer with explicit contours and segments |
| `<image>` | A `type: "image"` layer referencing an `image` asset |
| `<video>` | A `type: "video"` layer referencing a `video` asset |
| `<text>` / `<tspan>` | A `type: "text"` layer with `source`, `chunks`, and `spans` |
| SVG presentation attributes | `style`, `opacity`, `visibility`, or `composite` |
| `transform="..."` | The layer's explicit `translate`/`scale`/`rotate`/`skew`/`anchor` component fields |
| `<defs>` paint/clip/mask/filter/marker definitions | Optional root `paintServers`, `clipPaths`, `masks`, `filters`, `markers` |
| `url(#id)` | `{ "type": "reference", "id": "id" }` |
| `fill`, `stroke`, gradients, patterns | `style.fill`, `style.stroke`, and `V2Paint` values |
| `marker-start/mid/end` | `style.markerStart`, `markerMid`, `markerEnd` |
| `clip-path`, `mask`, `filter` | Layer `clipPath`, `mask`, and `filter` references |
| `<audio>` or a video audio stream | Root `audio.tracks[].clips[]` or `video.payload.audio` |

The protocol keeps source semantics in JSON. Compiler decisions such as CSS
cascade resolution, percentage resolution, font fallback, shaping, and media
decoding happen after validation.

## Root document

The required root fields are:

```text
MotionProtocolV2
├── format: "motion-protocol"
├── formatVersion: 2
├── id
├── composition
├── assets[]
├── layers[]
└── audio
```

The following definition collections are optional and are referenced by ID:
`markers[]`, `clipPaths[]`, `masks[]`, `filters[]`, and `paintServers[]`.

Minimal valid project:

```json
{
  "format": "motion-protocol",
  "formatVersion": 2,
  "id": "project-001",
  "composition": {
    "width": 1080,
    "height": 1920,
    "fps": 30,
    "background": "#000000",
    "colorSpace": "srgb",
    "view": {
      "projection": {
        "kind": "orthographic",
        "zoom": 1,
        "near": 0.1,
        "far": 1000
      },
      "transform": {
        "translate": { "x": 0, "y": 0, "z": 0 },
        "rotate": { "x": 0, "y": 0, "z": 0 }
      }
    }
  },
  "assets": [],
  "layers": [],
  "audio": {
    "sampleRate": 48000,
    "tracks": []
  }
}
```

### Scalar and unit rules

- IDs are non-empty strings with a maximum length of 200.
- JSON numbers must be finite. Positive and non-negative constraints are
  enforced by the schema.
- Colors are `#RRGGBB` or `#RRGGBBAA` strings.
- SVG lengths are either a bare number or `{ "value": number, "unit": ... }`.
  Units are `number`, `px`, `pt`, `pc`, `mm`, `cm`, `in`, `em`, and
  `percent`.
- All composition, layer, video, and audio timing values are milliseconds.
  `fps` and `sampleRate` are rates per second.

## Composition and view

`composition` contains positive `width`, `height`, and `fps`, a hex
`background`, the current `colorSpace: "srgb"`, and a required `view`.

`view.projection` is one of:

- `{ "kind": "orthographic", "zoom", "near", "far" }`
- `{ "kind": "perspective", "fov", "near", "far" }`

In both forms, `far` must be greater than `near`. `view.transform` contains
required `translate` and `rotate` Vec3 values. It is the composition camera
view, not a layer transform.

## Assets

`assets[]` contains portable metadata and references. It never contains a
decoded image, video element, PCM buffer, font object, GPU handle, or runtime
resource cache.

| `kind` | Fields |
| --- | --- |
| `image` | `id`, `uri`; optional `mimeType`, `width`, `height`, `integrity` |
| `video` | Image metadata plus optional `duration`, `fps`, `audio` derivative |
| `audio` | `id`, `uri`, required `mimeType`; optional `duration`, `sampleRate`, `channels`, `integrity` |
| `font` | `id`, `uri`, CSS selection `weight`, SHA-256 `integrity` |

Video audio is metadata on the video asset:

```json
{
  "kind": "video",
  "id": "video-001",
  "uri": "/preview/video/demo-video.mp4",
  "duration": 4000,
  "fps": 30,
  "audio": {
    "uri": "/preview/audio/demo-video.mp3",
    "mimeType": "audio/mpeg",
    "duration": 4000,
    "sampleRate": 48000,
    "channels": 2
  }
}
```

## Layer model

`layers[]` is a flat array representing a tree. Layer IDs are globally unique;
only a group may be a parent. Sibling `order` values are unique and higher
values paint later.

Every layer has these required fields:

```json
{
  "id": "layer-001",
  "parentLayerId": null,
  "order": 0,
  "frame": { "width": 320, "height": 180 },
  "transform": {
    "translate": { "x": 0, "y": 0, "z": 0 },
    "scale": { "x": 1, "y": 1, "z": 1 },
    "rotate": { "x": 0, "y": 0, "z": 0 },
    "skew": { "x": 0, "y": 0 },
    "anchor": { "x": 0, "y": 0, "z": 0 }
  },
  "timing": { "start": 0, "duration": 3000 },
  "type": "shape",
  "payload": { "shape": "rectangle" },
  "style": { "fill": "#14B8A6" }
}
```

Common optional fields:

| Field | SVG meaning |
| --- | --- |
| `opacity` | Source alpha; omitted means `1` |
| `color` | Inherited SVG `color`, used by `currentColor` |
| `enabled` | Editor/runtime enable state; omitted means enabled |
| `visibility` | `visible`, `hidden`, or `collapse`; omitted means visible |
| `backfaceVisibility` | `visible` or `hidden` after accumulated 3D transforms |
| `clipPath` | ID in root `clipPaths[]` |
| `mask` | ID in root `masks[]` |
| `filter` | ID in root `filters[]` |
| `backdropFilter` | ID in root `filters[]`, sampling the already-painted backdrop |
| `motion` | Layer-owned CSS motion-path source and resolved offset values |
| `composite` | SVG/CSS blend and isolation state |
| `tracks` | Typed local-time property animation |

`filter` and `backdropFilter` are both references to a project-root `V2Filter`
— an SVG filter-primitive graph (see [Filters](#filters)), the only
representation of a layer effect in Protocol V2. There is no named/convenience
effect shortcut (glow, blur, sepia, ...) at this layer: a named effect is an
Editor-tier concept that compiles down into a `V2Filter` primitive chain
before anything becomes Protocol V2 JSON — the same relationship an animation
preset ("fade in") has to its compiled keyframe tracks. See CLAUDE.md's
"Protocol V2 must stay atomic" rule. `filter` transforms the layer's own
source surface; `backdropFilter` is the separate CSS `backdrop-filter`
contract — it samples the backdrop inside an isolated offscreen boundary
before the layer is composited. The two must never be conflated because their
input surfaces and compositing scope differ.

### Transforms

A layer transform is authored through exactly these fields, and nothing
else — there is deliberately no second, ordered `operations[]`/`extensions`
representation alongside them (see CLAUDE.md's "Layer transform: one
explicit component form, no `operations[]`" section for the full history: an
earlier design kept both forms with an undocumented "`operations[]` wins when
present" tie-break that no real consumer fully implemented):

| Field | Type | Covers |
| --- | --- | --- |
| `translate` | `Vec3` | 2D via `.x`/`.y`; depth via `.z` |
| `scale` | `Vec3` | 2D via `.x`/`.y`; depth via `.z` |
| `rotate` | `Vec3` | **2D**: `.z` is a pure in-plane spin, SVG `rotate(angle)`. **3D**: `.x`/`.y` tilt the layer out of the screen plane |
| `skew` | `Vec2` | 2D skew, SVG `skewX`/`skewY` |
| `anchor` | `Vec3` | Local-unit pivot (`.z` for a 3D pivot depth) |
| `perspective` | `number` (optional, positive) | CSS-style perspective distance; only meaningful once `rotate.x` or `rotate.y` is non-zero |

```json
{
  "translate": { "x": 0, "y": 0, "z": 0 },
  "scale": { "x": 1, "y": 1, "z": 1 },
  "rotate": { "x": 0, "y": -90, "z": 0 },
  "skew": { "x": 0, "y": 0 },
  "anchor": { "x": 0, "y": 0, "z": 0 },
  "perspective": 600
}
```

This is a card tilted to -90° around the vertical axis (a flip "mid-turn,
edge-on"), with a perspective distance of 600 so the renderer draws it with
depth instead of a flat squeeze.

Every field here can be driven by a `transform.<path>` track — including the
3D ones, e.g. `"path": "transform.rotate.y"` for the flip above (see
[Animation and timing](#animation-and-timing) for track/keyframe shape).
There is no array-index
addressing (`operations.<i>.value`) to reason about: every animatable field
has exactly one, permanent path.

clip-path/mask/pattern-definition transforms are a different object with a
legitimately 2D-only need (they describe an SVG definition's own local
coordinate system, not a layer's). They keep an ordered SVG operation list —
`translate`/`scale`/`rotate`/`skewX`/`skewY`/`matrix`, SVG's own six-value
affine matrix (`x' = a*x + c*y + e`, `y' = b*x + d*y + f`) — documented where
`clipPath`/`mask`/pattern content is covered below. That list is not a
duplicate of the layer transform above and does not reintroduce the
dual-representation hazard described above.

### CSS motion path

Motion path is owned by the layer, matching the CSS model. It is not a visible
paint and it does not create a second layout pass. The optional `motion` object
contains a typed path plus resolved offset values:

```json
{
  "motion": {
    "offsetPath": {
      "type": "path",
      "contours": [
        {
          "id": "motion-contour-1",
          "start": { "x": 100, "y": 100 },
          "segments": [
            { "kind": "line", "to": { "x": 500, "y": 100 } }
          ],
          "closed": false
        }
      ],
      "coordinateSpace": "parent-local",
      "referenceBox": "border-box",
      "pathLength": 400,
      "sampling": {
        "method": "adaptive-flatness",
        "tolerance": 0.25,
        "maxSegments": 4096
      }
    },
    "offsetDistance": 0.5,
    "offsetRotate": { "mode": "auto", "angle": 0 },
    "offsetAnchor": { "x": 40, "y": 40 }
  }
}
```

The CSS compiler resolves `offset-path: path(...)` into the typed contour,
resolves CSS lengths and percentages, and stores `offset-distance` as a
normalized ratio where `0` is the path start and `1` is the path end.
`offset-anchor` is stored in layer-local units after resolution. `offset-rotate`
preserves tangent alignment through `auto`, adds a half-turn for
`auto-reverse`, or uses `fixed` for an explicit angle.

Motion-path animation uses ordinary layer tracks:

```json
{
  "tracks": [
    {
      "id": "motion-distance",
      "path": "motion.offsetDistance",
      "keyframes": [
        { "time": 0, "value": { "type": "number", "value": 0 } },
        { "time": 1400, "value": { "type": "number", "value": 1 } }
      ],
      "animation": {
        "durationMs": 1400,
        "delayMs": 0,
        "iterations": 1,
        "direction": "normal",
        "fillMode": "both",
        "playState": "running"
      }
    }
  ]
}
```

Runtime samples the declared path and tangent, then composes translation,
rotation, anchor, and the authored transform into the final layer matrix.
The native renderer receives that resolved matrix; it does not run a
separate CSS animation or motion-path engine. Geometric clipping, opacity,
blend, masks, and paint order remain independent layer concerns.

Current deterministic CSS lowering accepts `path()` with one contour. Empty
paths, unsupported path grammar, zero-length paths, and non-finite values must
produce diagnostics instead of being silently ignored. A project-level path
registry may be used internally for deduplication, but it is not required by
the Protocol V2 semantic contract.

### Local 3D group context

A group may define a local CSS-like 3D context:

```json
{
  "type": "group",
  "render3d": {
    "transformStyle": "preserve-3d",
    "perspective": {
      "distance": 800,
      "origin": { "x": 400, "y": 300 }
    }
  }
}
```

`transformStyle` is `flat` or `preserve-3d` and defaults to `flat` when
omitted. `perspective.distance` is positive. `origin` is in the group's local
coordinate units.

### Layer types

`layers[]` is a discriminated union by `type`:

| Type | Protocol fields | SVG semantics |
| --- | --- | --- |
| `group` | Optional `render3d` | `<g>` hierarchy and inherited state |
| `shape` | `payload`, `style` | Basic SVG geometry and presentation |
| `path` | `payload`, `style` | Explicit SVG path geometry and presentation |
| `image` | `payload` | `<image>` viewport and sampling |
| `video` | `payload` | `<video>` source range, fitting, and audio controls |
| `text` | `payload` | `<text>`/`<tspan>` source and normalized spans |

#### Shape

`payload.shape` is one of `rectangle`, `circle`, `ellipse`, `line`, `polyline`,
or `polygon`. `cornerRadius`, `rx`, and `ry` apply only to rectangles.
`line` requires `start` and `end`; `polyline` and `polygon` require at least
two `points`. `pathLength` is the optional SVG path-length calibration.

`style` supports `fill`, `fillOpacity`, `stroke`, `strokeWidth`,
`strokeOpacity`, `strokeMiterLimit`, `strokeJoin`, `strokeCap`, `strokeDash`,
`paintOrder`, `vectorEffect`, and `markerStart`/`markerMid`/`markerEnd`.

#### Path

`payload.contours` contains one or more contours, with `fillRule` of `nonzero`
or `evenodd`, optional `pathLength`, and optional `morph` data. Each contour
has `id`, `start`, `segments`, and `closed`. A segment is one of:

```json
{ "kind": "line", "to": { "x": 100, "y": 0 } }
{ "kind": "quadratic", "control": { "x": 50, "y": -20 }, "to": { "x": 100, "y": 0 } }
{ "kind": "cubic", "control1": { "x": 20, "y": -20 }, "control2": { "x": 80, "y": -20 }, "to": { "x": 100, "y": 0 } }
{ "kind": "arc", "radii": { "x": 40, "y": 40 }, "rotation": 0, "largeArc": false, "sweep": true, "to": { "x": 100, "y": 0 } }
```

Path style uses the same paint/stroke fields as shape style.

#### Image

```json
{
  "type": "image",
  "payload": {
    "assetId": "image-001",
    "x": 0,
    "y": 0,
    "width": 640,
    "height": 360,
    "preserveAspectRatio": {
      "align": "xMidYMid",
      "meetOrSlice": "meet"
    },
    "imageRendering": "auto"
  }
}
```

`width` and `height` may be omitted to use intrinsic asset dimensions.
`preserveAspectRatio.defer` optionally retains SVG's `defer` keyword semantics.
`preserveAspectRatio.align` is `none`, `xMinYMin`, `xMidYMin`, `xMaxYMin`,
`xMinYMid`, `xMidYMid`, `xMaxYMid`, `xMinYMax`, `xMidYMax`, or `xMaxYMax`.
`meetOrSlice` is `meet` or `slice`. `imageRendering` is `auto`,
`optimizeQuality`, `optimizeSpeed`, `smooth`, `high-quality`, `crisp-edges`,
or `pixelated`.

#### Video

```json
{
  "type": "video",
  "payload": {
    "assetId": "video-001",
    "fit": "contain",
    "trimStart": 1000,
    "trimEnd": 5000,
    "framePolicy": "round",
    "audio": {
      "enabled": true,
      "gainDb": -3,
      "pan": 0,
      "fadeIn": { "duration": 250, "curve": "linear" },
      "fadeOut": { "duration": 500, "curve": "equal-power" }
    }
  }
}
```

`fit` is `contain`, `cover`, `fill`, or `none`. `framePolicy` is `floor`,
`round`, or `ceil`. `trimEnd` must be greater than `trimStart` and remain
within known source duration metadata. Embedded audio keeps the video timing
and trim as its source identity; the Compiler derives the independent runtime
audio input.

#### Text

Text source is NFC-normalized and ranges use UTF-16 offsets:

```json
{
  "type": "text",
  "payload": {
    "source": {
      "text": "Hello",
      "language": "en",
      "direction": "ltr",
      "writingMode": "horizontal-tb",
      "whiteSpace": "default",
      "textRendering": "auto"
    },
    "layout": {
      "lineHeight": 48,
      "hardBreaks": [5],
      "textAlign": "center",
      "whiteSpace": "nowrap",
      "wrap": "none",
      "textOverflow": "clip"
    },
    "chunks": [
      {
        "id": "chunk-1",
        "sourceRange": { "start": 0, "end": 5 },
        "textAnchor": "middle",
        "spans": [
          {
            "id": "span-1",
            "sourceRange": { "start": 0, "end": 5 },
            "font": {
              "families": ["Noto Sans", "sans-serif"],
              "size": 40,
              "weight": 400,
              "style": "normal"
            },
            "fill": "#FFFFFF",
            "letterSpacing": "normal",
            "wordSpacing": 0
          }
        ]
      }
    ]
  }
}
```

The source supports `language`, `direction`, `writingMode`, `whiteSpace`, and
`textRendering`. The optional normalized `layout` contract supports resolved
`lineHeight`, `contentWidth`, `contentHeight`, `contentOffsetX`,
`contentOffsetY`, `textAlign`, CSS `whiteSpace`, deterministic `wrap`, and
`textOverflow`. `hardBreaks` is an optional ordered list of UTF-16 offsets
where authored hard line breaks begin; it preserves HTML `<br>` semantics even
when CSS `white-space` is `normal`. `contentWidth` is the inline content-box width used for
wrapping and alignment; the offsets locate that box inside the layer frame.
Text spans carry `letterSpacing` and `wordSpacing` as semantic lengths or
`"normal"`; runtime resolves them before line alignment and justification.
The compiler contract requires `textOverflow: "ellipsis"` to provide a layer
`clipPath`.
`textAlign` accepts `left`, `right`, `center`, `start`, `end`, `justify`,
`match-parent`, and `justify-all`.
Chunks support `x`, `y`, `dx`, `dy`, `rotate` arrays,
`textAnchor`, and an optional `textPath`. Spans support the SVG font, fill,
stroke, spacing, baseline, `textLength`, `lengthAdjust`, decoration, kerning,
optical sizing, and small-caps semantics. Span IDs cannot contain a dot and
span ranges must be ordered, non-overlapping, and contained by their chunk.
HTML/CSS lowering may add `resolvedFontAssetIds`, an ordered list of catalog
face IDs. This keeps the semantic family list readable for AI/user tooling
while making runtime glyph fallback deterministic.

## Paint and SVG definitions

`V2Paint` is a color string, one of the keywords `none`, `currentColor`,
`context-fill`, or `context-stroke`, or an object:

- `{ "type": "none" }`
- `{ "type": "solid", "color": "#RRGGBB", "opacity"? }`
- `linear-gradient`, `radial-gradient`, or `conic-gradient`
- `pattern`
- `{ "type": "reference", "id": "...", "fallback"? }`

### Gradients

All gradient fields retain their SVG names. Stops are optional because SVG
permits zero or one stop; when present, offsets must be non-decreasing.

```json
{
  "type": "linear-gradient",
  "x1": { "value": 0, "unit": "percent" },
  "y1": 0,
  "x2": { "value": 100, "unit": "percent" },
  "y2": 0,
  "gradientUnits": "objectBoundingBox",
  "spreadMethod": "pad",
  "stops": [
    { "offset": 0, "color": "#14B8A6" },
    { "offset": 1, "color": "#2563EB", "stopOpacity": 0.8 }
  ]
}
```

Linear gradients support `x1`, `y1`, `x2`, `y2`, and the compatibility
shorthand `angle`. Radial gradients support `cx`, `cy`, `radius`, `fx`, `fy`,
and `fr`. Conic gradients support `from`, `cx`, and `cy`. All gradients may
also use `spreadMethod` (`pad`, `reflect`, `repeat`), `gradientUnits`, an SVG
2D `gradientTransform` matrix, and an `href` template reference.

Patterns retain `x`, `y`, `width`, `height`, `patternUnits`,
`patternContentUnits`, `patternTransform` (and the compatibility `transform`),
`viewBox`, `href`, and recursive `content` nodes. Pattern nodes are normalized
SVG `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path`, or
`group` nodes with paint and opacity.

Named paint definitions live at the root:

```json
{
  "paintServers": [
    {
      "id": "brand-gradient",
      "paint": {
        "type": "linear-gradient",
        "angle": 90,
        "stops": [
          { "offset": 0, "color": "#14B8A6" },
          { "offset": 1, "color": "#2563EB" }
        ]
      }
    }
  ]
}
```

A layer can then use `"fill": { "type": "reference", "id": "brand-gradient" }`.
References and gradient/pattern `href` values are validated against the root
definitions. Cycles and unknown IDs are rejected.

### Paint order, strokes, and markers

`paintOrder` is an ordered, unique subset of `fill`, `stroke`, and `markers`;
unlisted components are appended using SVG's default order. Stroke fields map
to SVG `stroke-width`, `stroke-opacity`, `stroke-linejoin`, `stroke-linecap`,
`stroke-miterlimit`, and `stroke-dasharray`/`stroke-dashoffset`.

`vectorEffect` is `none` or `non-scaling-stroke`. Marker references point to
root `markers[]` definitions. A marker stores `markerUnits`, `refX`, `refY`,
`markerWidth`, `markerHeight`, `orient` (`auto`, `auto-start-reverse`, or a
number), an optional viewBox, and contour content with paint.

## Clip paths, masks, and filters

Definitions are kept at the root so a layer preserves the SVG reference model.
Definition children use the same normalized geometry vocabulary as paths and
basic SVG elements. Definition transforms use the exact ordered SVG operation
shape described above.

### Clip paths

```json
{
  "clipPaths": [
    {
      "id": "clip-1",
      "clipPathUnits": "userSpaceOnUse",
      "transform": [
        { "type": "translate", "x": 20, "y": 10 }
      ],
      "children": [
        {
          "type": "rect",
          "x": 0,
          "y": 0,
          "width": 300,
          "height": 180
        }
      ]
    }
  ]
}
```

`clipPathUnits` is `userSpaceOnUse` or `objectBoundingBox` and defaults to
`userSpaceOnUse`. Definition nodes support `path`, `rect`, `circle`, `ellipse`,
`line`, `polyline`, `polygon`, and `group`, with optional transform, clipPath,
fill, fillOpacity, stroke, strokeWidth, and strokeOpacity.

### Masks

Masks have `id`, `maskUnits`, `maskContentUnits`, `maskType`, optional `x`,
`y`, `width`, `height`, optional ordered transform, and `children`.
`maskUnits` defaults to `objectBoundingBox`, `maskContentUnits` to
`userSpaceOnUse`, and `maskType` to `luminance`. `maskType` may be `alpha` or
`luminance`; mask lengths are numbers or `{ "value": number, "unit": "percent" }`.

### Filters

`filters[]` is the normalized SVG filter graph. A filter has `id`, optional
`x`, `y`, `width`, `height`, `filterUnits`, `primitiveUnits`,
`colorInterpolationFilters`, and one to 128 ordered `primitives`.

Defaults are `filterUnits: "objectBoundingBox"`,
`primitiveUnits: "userSpaceOnUse"`, and
`colorInterpolationFilters: "linearRGB"`. Every primitive has a unique `id`
and may have `in`, `result`, `region`, and its own
`colorInterpolationFilters`. Supported primitive names are:

`feBlend`, `feColorMatrix`, `feComponentTransfer`, `feComposite`,
`feConvolveMatrix`, `feDisplacementMap`, `feDropShadow`, `feFlood`,
`feGaussianBlur`, `feImage`, `feMerge`, `feMorphology`, `feOffset`, `feTile`,
`feTurbulence`, `feDiffuseLighting`, and `feSpecularLighting`.

The primitive fields retain SVG names, including `in`, `in2`, `result`,
`mode`, `operator`, `stdDeviation`, `dx`, `dy`, `scale`, channel selectors,
transfer functions, light definitions, and filter regions. `feColorMatrix`
with `kind: "matrix"` requires 20 values; convolution kernels must match
`order.x * order.y`.

## Compositing and effects

`composite` maps SVG/CSS compositing directly:

```json
{
  "composite": {
    "blendMode": "multiply",
    "isolation": "isolate"
  }
}
```

`blendMode` is one of `normal`, `darken`, `multiply`, `color-burn`, `lighten`,
`screen`, `color-dodge`, `overlay`, `soft-light`, `hard-light`, `difference`,
`exclusion`, `hue`, `saturation`, `color`, or `luminosity`. `isolation` is
`auto` or `isolate`.

A layer's visual effect (glow, blur, sepia, drop shadow, ...) is represented
only through `filter`/`backdropFilter` — id references to a project-root
`V2Filter` (see [Filters](#filters)), an SVG filter-primitive graph. There is
no named/convenience effect field on the layer itself (no `effects[]`, no
`color-adjust`/`grayscale`/`shadow`/`outer-glow`/... atom types): the complete
standard SVG filter-primitive set (`feGaussianBlur`, `feFlood`, `feComposite`,
`feMerge`, `feColorMatrix`, etc., see Filters) can already build any of those
by composition, so a named effect is an Editor-tier preset that compiles down
into a `V2Filter` primitive chain before anything becomes Protocol V2 JSON —
the Editor Document stores the name + params, a compiler step expands it,
exactly like an animation preset ("fade in") expands into raw keyframe
tracks. See CLAUDE.md's "Protocol V2 must stay atomic" rule.

## Animation and timing

Each layer has composition-time `timing`:

```json
{ "start": 0, "duration": 3000 }
```

`tracks[]` is optional and stores typed animation against a dot-separated
property path in local layer time:

```json
{
  "tracks": [
    {
      "id": "move-x",
      "path": "transform.translate.x",
      "keyframes": [
        { "time": 0, "value": { "type": "number", "value": -120 } },
        {
          "time": 600,
          "value": { "type": "number", "value": 0 },
          "easing": {
            "type": "cubicBezier",
            "x1": 0.22,
            "y1": 1,
            "x2": 0.36,
            "y2": 1
          }
        }
      ]
    }
  ]
}
```

Keyframe times must be strictly increasing and are bounded by `boundMs` (see
"Looping and iterated animation" below for what `boundMs` is). Values are
explicitly typed as `number`, `vec2`, `vec3`, `vec4`, `color` (RGBA tuple in
`0..1`), `boolean`, `string`, or `enum`. Vector values are fixed-size tuples.
Easing is `linear`, `step`, `cubicBezier`, or `spring`. `interpolation`, when
present, is `linear` or `discrete`.

The schema also validates that a track path identifies an animatable property
on that particular layer and that its value kind matches the property.

### Keyframe time anchors

A layer-track keyframe's `time` is either a bare millisecond number (shorthand
for `{ "anchor": "start", "offsetMs": time }`) or an explicit anchor object:

```json
{ "anchor": "start", "offsetMs": 0 }
{ "anchor": "end", "offsetMs": 300 }
```

`anchor: "end"` resolves to `boundMs - offsetMs`. This lets an "out" animation
stay correctly placed when a clip is trimmed or extended, instead of forcing
every out-animation keyframe to be recomputed by hand each time
`timing.duration` changes:

```json
{
  "id": "fade-out",
  "path": "opacity",
  "keyframes": [
    { "time": { "anchor": "end", "offsetMs": 300 }, "value": { "type": "number", "value": 1 } },
    { "time": { "anchor": "end", "offsetMs": 0 }, "value": { "type": "number", "value": 0 } }
  ]
}
```

Both keyframes are end-anchored: the layer stays fully opaque until 300ms
before the end, then fades out, always finishing exactly at the clip's end,
no matter what `timing.duration` is set to. A single end-anchored keyframe
paired with an absolute `time: 0` start keyframe would instead stretch the
fade across the *entire* clip (from the start to 300ms before the end) —
both keyframes of an out-animation need to be end-anchored together so the
whole fade shifts as one unit when the clip is trimmed.

This anchor concept only applies to layer tracks. Definition-level tracks
(`filters[].tracks`, `masks[].tracks`, `paintServers[].tracks`) are sampled at
absolute composition time, not layer-local time, so there is no layer
duration to anchor "end" against; they keep plain-number-only keyframe times.

### Looping and iterated animation

A track's optional `animation` describes a repeating cycle, in the same
spirit as the CSS Web Animations model:

```json
{
  "animation": {
    "durationMs": 1000,
    "delayMs": 0,
    "iterations": "infinite",
    "direction": "normal",
    "fillMode": "none",
    "playState": "running"
  }
}
```

When `animation` is present, the track's keyframes describe **one cycle**:
`boundMs` is `animation.durationMs`, independent of `layer.timing.duration` —
a one-second decorative spin loop is valid on an 800ms clip even though one
full cycle is longer than the clip itself; the compiler clips playback at the
layer's own end. When `animation` is absent, `boundMs` is
`layer.timing.duration`, as in the plain example above.

- Cycles start at the layer-local time `animation.delayMs` and repeat every
  `animation.durationMs`, for `animation.iterations` times (a non-negative
  number or `"infinite"`), clipped to `layer.timing.duration`.
- `direction` selects which way each cycle plays: `normal` always plays
  keyframes forward; `reverse` always plays them backward; `alternate` plays
  the first cycle forward and flips on every subsequent cycle;
  `alternate-reverse` starts backward and flips the same way.
- `fillMode` controls the value outside the active cycle window, but still
  inside `layer.timing.duration`: `none` falls back to the layer's own
  non-animated value; `backwards` holds the first keyframe's value during
  `delayMs`; `forwards` holds the final reached keyframe's value after
  `iterations` complete; `both` applies both.
- `playState: "paused"` freezes local elapsed time at `0` — the track renders
  exactly as it would at the start of `delayMs`, governed by `fillMode`.
- `anchor: "end"` keyframe times are rejected when `animation` is present: a
  repeating cycle has no "end of clip" within itself to anchor against.

### Stagger templates (text)

`payload.rangeSelectors[].track` (see the Text layer section) uses the same
layer-scoped keyframe-time and `animation` semantics described above, so a
per-character stagger template may end-anchor its last keyframe to the clip's
end just like an ordinary layer track.

## Audio

Audio is a required root domain parallel to visual layers. A silent project
uses `{ "sampleRate": 48000, "tracks": [] }`.

```json
{
  "audio": {
    "sampleRate": 48000,
    "tracks": [
      {
        "id": "track-001",
        "gainDb": 0,
        "pan": 0,
        "muted": false,
        "clips": [
          {
            "id": "clip-001",
            "assetId": "audio-001",
            "timing": { "start": 0, "duration": 30000 },
            "trim": { "start": 0, "end": 30000 },
            "playbackRate": 1,
            "enabled": true,
            "gainDb": 0,
            "pan": 0,
            "fadeIn": { "duration": 250, "curve": "linear" },
            "fadeOut": { "duration": 500, "curve": "equal-power" }
          }
        ]
      }
    ]
  }
}
```

Audio clip `timing` is composition time; `trim` is source time. Clips reference
only `audio` assets or the audio derivative of a `video` asset. `playbackRate`
is positive. `gainDb` is a finite number, `pan` is normalized to `-1..1`, and
fade durations cannot exceed the clip duration. `enabled: false` preserves the
clip on the timeline while silencing its input.

Video embedded audio uses `video.payload.audio` for `enabled`, `gainDb`, `pan`,
`fadeIn`, and `fadeOut`. Its timing and trim stay on the video layer so the
visual source and original audio move together; the Compiler lowers the audio
part to Runtime audio data.

## Validation and ownership

Schema validation covers:

- exact format/version and strict object fields;
- finite numbers, positive/non-negative constraints, colors, lengths, and enums;
- unique asset, layer, definition, track, and clip IDs where applicable;
- valid group parents, no parent cycles, and unique sibling order values;
- valid image/video/audio asset-kind references;
- valid clipPath, mask, filter, marker, and paint-server references;
- track paths, value kinds, resolved keyframe-anchor ordering, and bounds
  (against `layer.timing.duration`, or `animation.durationMs` for a looping
  track);
- video trim/source-duration and audio fade bounds.

Capability support is decided by the Compiler after Protocol validation. A
schema-valid value is valid authoring data; it is not by itself a promise that
every renderer supports every optional SVG or 3D feature.

The HTML/CSS compiler resolves only the fixed-composition viewport units
`vw`, `vh`, `vmin`, and `vmax`. Dynamic/small/large viewport units, logical
viewport variants, and container-relative units (`cq*`) are outside the motion
profile and must fail with a compiler diagnostic. Advanced `calc()` functions
are evaluated before lowering, so Runtime receives finite typed values rather than
CSS expression strings. `image(url())` and supported `image()` fallbacks are
lowered to image or paint layers, while `cross-fade()` becomes ordered image
layers with opacity. `element()` remains an explicit diagnostic until V2 has a
live element-snapshot source contract. No new protocol field is needed for
this subset: existing asset, paint, layer opacity, and stable order atomics
are sufficient.

CSS mask layers remain ordered in `maskLayers[]`. Each entry has its own mode,
coverage source list, and composite operator (`add`, `subtract`, `intersect`,
or `exclude`), while image mask sources may carry an explicit coverage
multiplier.

```text
Protocol V2 JSON
      |
      v
@motionvideo/motion-compiler
      |
      v
RuntimeProjectV3 / RuntimeFrameV3
      |
      +--> platform-native renderer
      +--> export renderer
```

## Schema and tests

```bash
pnpm --filter @motionvideo/motion-protocol typecheck
pnpm --filter @motionvideo/motion-protocol test
pnpm --filter @motionvideo/motion-protocol check:schema
```

`check:schema` regenerates `schema/v2.json` from the Zod source and verifies
that the checked-in JSON Schema is current.
