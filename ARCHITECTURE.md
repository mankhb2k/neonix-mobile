# Neonix architecture and Protocol V2 JSON

This document describes the architecture implemented in this repository and the JSON shape represented by `V2Project`. The schema reference follows the Swift `Codable` models under `ios-editor/Sources/AppModule/Protocol/`; where the models explicitly identify an addition as Swift-only, that distinction is called out below.

## 1. Current architecture

The iOS app is the current product. Most SwiftUI editor commands change a `V2Project`; playback and export consume a render-ready project. Transition choices are editor authoring intent: they are stored as `EditorTransitionIntent` values associated with adjacent clip IDs, then compiled into temporary V2 groups/tracks only for preview and export. They are not part of Protocol V2 JSON. The protocol is renderer-oriented: a project contains composition settings, assets, ordered layers, animation tracks, and reusable definitions such as filters, masks, clip paths, markers, and paint servers.

`V2Project` still serves as the main editable value for most features. The active editor keeps transition intents alongside that value and removes legacy transition wrappers when opening a project; playback/export compile those intents into a temporary render projection. Template `EditorDocument` JSON also stores transitions directly. The repository does not yet have a complete persistent Editor Project + command log + compiler pipeline for every editor feature. The Swift protocol models are hand-maintained `Codable` models; comments in those files refer to a TypeScript/Zod source package, but no `packages/motion-protocol` directory or generated JSON Schema is present in this checkout.

```text
SwiftUI editor commands ──> V2Project ───────────────┐
Editor transition intent ────────────────────────────┴──> render compiler ──> preview / export
```

This protocol is a semantic document format, not an instruction to use a particular rendering framework. The current renderer is iOS-native. Cross-platform rendering and real-time collaboration are not implemented.

## 2. JSON conventions

- Field names below are JSON keys. Swift optionals normally mean that the key can be omitted; they are not necessarily serialized as `null`.
- `required` means the current decoder expects the key. `optional` means it may be omitted.
- Time values are milliseconds unless explicitly described otherwise. Asset dimensions and geometry are in their respective image/composition or user-space units.
- A number-or-object field is a tagged/unwrapped union: examples include a bare number or `{ "value": 12, "unit": "px" }` for SVG lengths.
- Tagged unions use a discriminator such as `kind`, `type`, or `shape`. Only the fields for that case are meaningful.
- Some Swift optionals stand in for schema defaults. A missing field can therefore have an effective runtime default documented in its row; decode does not always materialize that default.
- A default used by a Swift initializer is not necessarily a JSON decoding default. Unless a custom `init(from:)` handles omission, a non-optional stored property remains required when decoding JSON.
- `Codable` enforces JSON shape and known enum/discriminator cases. It does not reproduce all semantic validation (for example, ID uniqueness, reference existence, ranges, or consistency between linked values). Producers must maintain those invariants.

## 3. Root document

The root is `V2Project` (`Protocol/V2Types.swift`).

| JSON field | Type | Requirement | Meaning |
|---|---|---|---|
| `format` | string | required when decoding; initializer default `motion-protocol` | Format identifier. |
| `formatVersion` | integer | required when decoding; initializer default `2` | Protocol version. |
| `id` | string | required when decoding; initializer default `untitled` | Project identifier. |
| `composition` | `V2Composition` | required | Canvas dimensions, frame rate, background, and optional camera. |
| `assets` | `V2Asset[]` | required | Imported media/font/LUT resources referenced elsewhere by ID. |
| `markers` | `V2Marker[]` | optional | Reusable SVG-style marker definitions. |
| `clipPaths` | `V2ClipPath[]` | optional | Reusable clipping geometry definitions. |
| `masks` | `V2Mask[]` | optional | Reusable alpha/luminance/image/segmentation mask definitions. |
| `filters` | `V2Filter[]` | optional | Reusable ordered filter graphs. |
| `paintServers` | `V2PaintServerDefinition[]` | optional | Reusable gradient/pattern paint definitions. |
| `layers` | `V2Layer[]` | required | Composition's visual layer tree and timeline objects. |
| `audio` | `V2AudioDomain` | required when decoding; initializer default `{sampleRate:48000, tracks:[]}` | Audio tracks and clips. |

### Composition and common values

| Object | Fields |
|---|---|
| `V2Composition` | `width` number, required; `height` number, required; `fps` number, required; `background` color string, required; `colorSpace` string, optional (effective default `srgb`); `view` `V2View`, optional. |
| `V2Frame` | `width` number, required; `height` number, required. Frame is the layer's local box. |
| `V2Timing` | `start` number, required; `duration` number, required. Both are timeline milliseconds. |
| `V2Vec2` / `V2Vec3` | `{x,y}` / `{x,y,z}`, all numeric and required. |
| `V2Color` | String, conventionally `#RRGGBB` or `#RRGGBBAA`. The Swift alias does not validate the color syntax. |
| `V2SvgLength` | Either a number or `{value:number, unit:string}`. Units: `number`, `px`, `pt`, `pc`, `mm`, `cm`, `in`, `em`, `percent`. |

`V2View` is a composition camera, separate from each layer's transform:

| Object | Fields |
|---|---|
| `view` | `projection` required; `transform` required. |
| `projection` orthographic case | `{kind:"orthographic", zoom:number, near:number, far:number}`. |
| `projection` perspective case | `{kind:"perspective", fov:number, near:number, far:number}`. |
| `view.transform` | `translate:V2Vec3`, `rotate:V2Vec3`, both required. |

## 4. Assets

Every asset has `id` and `uri`; `kind` selects the shape. `mimeType` and `integrity` are optional except where noted.

| `kind` | Fields in addition to `id`, `kind`, `uri`, `mimeType?`, `integrity?` |
|---|---|
| `image` | `width:number`, `height:number` required. |
| `video` | `width:number`, `height:number`, `duration:number` required; `fps:number?`; `audio:V2VideoAudioDerivative?`. `duration` is milliseconds. |
| `audio` | `duration:number` required; `mimeType:string` required; `sampleRate:number?`; `channels:integer?`. Duration is milliseconds. |
| `font` | `weight:integer` required; `integrity:string` required. |
| `lut` | `dimension:integer` required; `mimeType?`, `integrity?`. The URI identifies a 3D `.cube` LUT resource. |

`V2VideoAudioDerivative` fields: `uri:string` required; `mimeType?`; `duration:number?` (ms); `sampleRate:number?`; `channels:integer?`; `integrity?`. It identifies an audio-only derivative of a video asset.

## 5. Layers and payloads

All layers share the fields below. The layer `type` discriminator is required in JSON; the Swift enum derives it from `payload` while encoding.

| JSON field | Type | Requirement | Meaning |
|---|---|---|---|
| `id` | string | required | Stable layer identity. |
| `parentLayerId` | string | optional | Parent group layer ID; absent means root. |
| `order` | integer | required | Sibling stacking order. |
| `frame` | `V2Frame` | required | Local width and height. |
| `transform` | `V2Transform` | required | Explicit 2D/3D component transform. |
| `opacity` | number | optional; default 1 | Layer opacity. |
| `color` | color string | optional | Layer-level color value when relevant. |
| `enabled` | boolean | optional | Enable/disable layer. |
| `visibility` | enum | optional | `visible`, `hidden`, or `collapse`. |
| `backfaceVisibility` | enum | optional | `visible` or `hidden`. |
| `clipPath` | string | optional | ID reference to root `clipPaths[]`. |
| `mask` | string | optional | ID reference to root `masks[]`. |
| `maskLayers` | `V2MaskLayer[]` | optional | Stack of mask definitions and compositing modes. |
| `filter` | string | optional | ID reference to a filter applied to this layer's own source. |
| `backdropFilter` | string | optional | ID reference to a filter applied to already-painted content behind this layer. |
| `motion` | `V2MotionPath` | optional | Offset-path motion configuration. |
| `composite` | `V2Composite` | optional | Blend and isolation settings. |
| `timing` | `V2Timing` | required | Timeline start/duration. |
| `tracks` | `V2Track[]` | optional | Animated property tracks. |
| `type` | discriminator | required | `group`, `shape`, `path`, `image`, `video`, or `text`. |
| `payload` | object | conditional | Type-specific data for shape/path/image/video/text. |
| `style` | object | shape/path only | Draw style for shape or path. |
| `render3d` | `V2Render3D` | group only | Group's 3D transform behavior. |

`V2Transform` has required `translate:V2Vec3`, `scale:V2Vec3`, `rotate:V2Vec3`, `skew:V2Vec2`, `anchor:V2Vec3`, and optional `perspective:number`. It deliberately uses a single explicit component form; there is no layer `operations[]` field. Translation/anchor are in local units, scale is multiplicative, and rotation is in degrees. `perspective` is relevant to X/Y 3D tilt.

### Layer type payloads

| `type` | Payload fields |
|---|---|
| `group` | No `payload` object; optional sibling `render3d`. Child layers point to the group through `parentLayerId`. |
| `shape` | `payload.shape` discriminates `rectangle`, `circle`, `ellipse`, `line`, `polyline`, `polygon`; sibling `style` is required. `pathLength:number?` is common. Rectangle: `cornerRadius:V2SvgLength?`, `rx?`, `ry?`; line: `start` and `end` points; polyline/polygon: `points:V2ShapePoint[]`. |
| `path` | `payload.contours:V2PathContour[]` required; `fillRule:string?` (default `nonzero`); `pathLength:number?`; `morph:V2PathMorph?`. Sibling `style` required. `morph` has `targetContours[]` and `progress:number`. |
| `image` | `assetId:string` required; `fit:string?`; `x,y,width,height:number?`; `preserveAspectRatio?`; `imageRendering:string?`; `crop:V2Crop?`. |
| `video` | `assetId:string` required; `fit:string?`; `trimStart:number?`, `trimEnd:number?`; `playbackRate:number?`; `speedCurve:V2SpeedPoint[]?`; `audio:V2EmbeddedVideoAudio?`; `framePolicy:string?`; `crop:V2Crop?`. Times are ms. A present speed curve supersedes constant `playbackRate`. |
| `text` | `payload.source` required; `payload.chunks` required; `payload.layout?`; `payload.rangeSelectors?`. See Text schema below. |

Shared `V2DrawStyle` fields for shape/path: `fill:V2Paint?`, `fillOpacity:number?`, `stroke:V2Paint?`, `strokeWidth:V2SvgLength?`, `strokeOpacity:number?`, `strokeMiterLimit:number?`, `strokeJoin:string?`, `strokeCap:string?`, `strokeDash:V2StrokeDash?`, `paintOrder:V2PaintOrder?`, `vectorEffect:"none"|"non-scaling-stroke"?`, `markerStart:string?`, `markerMid:string?`, `markerEnd:string?`. `strokeDash` has `array:"none"|V2SvgLength[]` and `offset:V2SvgLength?`. `paintOrder` is a list of `fill`, `stroke`, `markers`.

`V2Crop` fields: `x`, `y`, `width`, `height` required fractions of the source image/video (0–1); `rotation:number?` degrees; `flipped:boolean?`. Crop is applied to image/video sources; absent means full source.

`V2SpeedPoint` fields: `sourceMs:number` required, `rate:number` required, `slope:number?`. The optional slope preserves the speed curve derivative across edits. `V2EmbeddedVideoAudio`: `enabled:boolean` required; `gainDb:number?` (default 0); `pan:number?` (default 0); `fadeIn:V2AudioFade?`; `fadeOut:V2AudioFade?`.

`V2Render3D`: `transformStyle:"flat"|"preserve-3d"?` (default `flat`); `perspective:V2PerspectiveContext?`. Perspective context has `distance:number`, `origin:V2Vec2`.

## 6. Animation tracks

`V2Track` has required `id:string`, `path:string`, `keyframes:V2Keyframe[]`, and optional `animation:V2AnimationPlayback`. A path identifies the property being animated, using a protocol-defined property path.

| Object | JSON shape / fields |
|---|---|
| Keyframe | `time` required; `value` required; `easing?`. |
| Keyframe time | Absolute milliseconds as a number, or `{anchor:"start"|"end", offsetMs:number}`. End-anchored times keep outgoing animation positioned relative to clip end. |
| Animatable value | `{type:"number",value:number}`; `vec2`/`vec3`/`vec4`/`color` use numeric arrays of length 2/3/4/4; `boolean`, `string`, `enum` use a matching scalar value. Color array is RGBA 0–1. |
| Easing | `{type:"linear"}`; `{type:"step",count?:integer,position?:string}` (defaults 1, `jump-end`); `{type:"cubicBezier",x1,y1,x2,y2}`; `{type:"spring",mass,stiffness,damping,velocity?}`. |
| Animation playback | `durationMs:number`, `delayMs:number`, `iterations:number|"infinite"`, `direction:"normal"|"reverse"|"alternate"|"alternate-reverse"`, `fillMode:string`, `playState:"running"|"paused"`. |

The model can decode/encode all value/easing shapes, but renderer support can be narrower than the wire format. For example, `KeyframeSampler.swift` currently samples numeric tracks; inspect the runtime implementation before assuming every union is rendered/interpolated.

## 7. Audio domain

| Object | Fields |
|---|---|
| `V2AudioDomain` | `sampleRate:number` required; `tracks:V2AudioTrack[]` required. |
| `V2AudioTrack` | `id:string` required; `gainDb:number?` (default 0); `pan:number` required; `muted:boolean` required; `clips:V2AudioClip[]` required. |
| `V2AudioClip` | `id:string`, `assetId:string`, `timing:V2AudioClipTiming`, `trim:V2AudioClipTrim`, `playbackRate:number` required; `enabled:boolean?` (default true); `gainDb:number?` (default 0); `pan:number?` (default 0); `fadeIn?`, `fadeOut?`. |
| `V2AudioClipTiming` | `start:number`, `duration:number`, in timeline ms. |
| `V2AudioClipTrim` | `start:number`, `end:number?`, source trim in ms. |
| `V2AudioFade` | `duration:number` ms; `curve:"linear"|"equal-power"`. |

## 8. Paint and reusable definitions

`V2Paint` can be a bare color string, a bare keyword (`none`, `currentColor`, `context-fill`, `context-stroke`), or an object with `type`:

| `type` | Fields |
|---|---|
| `none` | `type` only. |
| `solid` | `color:string` required; `opacity:number?`. |
| `linear-gradient` | `x1,y1,x2,y2:V2SvgLength?`; shared gradient fields below. |
| `radial-gradient` | `cx,cy,radius,radiusX,radiusY,fx,fy,fr:V2SvgLength?`; shared gradient fields below. |
| `conic-gradient` | `from,cx,cy:number?`; shared gradient fields below. |
| `pattern` | `x,y,width,height:V2SvgLength?`; `patternUnits`, `patternContentUnits` (`objectBoundingBox` or `userSpaceOnUse`)?; `patternTransform:V2PaintTransform?`; `href:string?`; `viewBox:V2PatternViewBox?`; `content:V2PatternContent[]?`. |
| `reference` | `id:string` required; `fallback:color?`. |

Gradient common fields: `stops:V2GradientStop[]?`, `spreadMethod:"pad"|"reflect"|"repeat"?`, `gradientUnits:"objectBoundingBox"|"userSpaceOnUse"?`, `gradientTransform:V2PaintTransform?`, `href:string?`. A gradient stop has `offset:number`, `color:string`, `stopOpacity:number?`. `V2PaintTransform` is an SVG matrix `{a,b,c,d,e,f}`. A pattern viewBox has `x,y,width,height:number`, `align?` (SVG preserveAspectRatio alignment), `meetOrSlice?`.

Pattern content is a recursive node list, each node has `type` plus the geometry for its node: `rect(x,y,width,height,rx?,ry?)`; `circle(cx,cy,radius)`; `ellipse(cx,cy,rx,ry)`; `line(x1,y1,x2,y2)`; `polyline(points)`; `polygon(points)`; `path(contours,fillRule?)`; or `group(transform?,opacity?,children)`. Non-group nodes can carry `fill?`, `fillOpacity?`, `stroke?`, `strokeWidth?`, `strokeOpacity?`.

`V2PaintServerDefinition`: `id:string`, `paint:V2Paint`, `tracks:V2Track[]?`. `V2ClipPath`: `id:string`, `clipPathUnits:string?` (default `userSpaceOnUse`), `transform:V2SvgTransformOperation[]?`, `children:V2SvgDefinitionNode[]`.

SVG definition nodes are tagged with `type`: `path(contours,fillRule?)`; `rect(x,y,width,height,rx?,ry?)`; `circle(cx,cy,r)`; `ellipse(cx,cy,rx,ry)`; `line(x1,y1,x2,y2)`; `polyline(points)`; `polygon(points)`; `group(children,opacity?)`. Each node can also carry `transform?`, `clipPath?`, `fill?`, `fillOpacity?`, `stroke?`, `strokeWidth?`, `strokeOpacity?`.

SVG definition `transform` operations are 2D and ordered: `translate(x,y)`, `scale(x,y)`, `rotate(angle,center?)`, `skewX(angle)`, `skewY(angle)`, `matrix(values:number[6])`.

## 9. Geometry, markers, masks, and motion paths

| Type | Fields |
|---|---|
| `V2PathPoint` | `x:number`, `y:number`. |
| `V2PathContour` | `id:string`, `start:V2PathPoint`, `segments:V2PathSegment[]`, `closed:boolean`. |
| Path segment `line` | `{kind:"line",to}`. |
| Path segment `quadratic` | `{kind:"quadratic",control,to}`. |
| Path segment `cubic` | `{kind:"cubic",control1,control2,to}`. |
| Path segment `arc` | `{kind:"arc",radii:V2PathPoint,rotation:number,largeArc:boolean,sweep:boolean,to}`. |
| `V2Marker` | `id`; `markerUnits?` (default `strokeWidth`); `refX?`, `refY?` (default 0); `markerWidth?`, `markerHeight?` (default 3); `orient?` (`auto`, `auto-start-reverse`, or angle; default 0); `viewBox?`; `content` required. |
| Marker `viewBox` | `x,y,width,height:number`. |
| Marker `content` | `contours:V2PathContour[]` required; `fill?`, `fillOpacity?`, `stroke?`, `strokeWidth?`, `strokeOpacity?`, `paintOrder?`. |
| `V2Mask` | `id`; `maskUnits?`, `maskContentUnits?`, `maskType?`; `x,y,width,height:V2SvgLength?`; `transform:V2SvgTransformOperation[]?`; `children:V2SvgDefinitionNode[]?`; `image:V2MaskImageSource?`; `tracks:V2Track[]?`; Swift-only: `feather:number?`, `invert:boolean?`, `segmentation:V2MaskSegmentation?`. Exactly one source form should be selected (`children`, `image`, or `segmentation`). |
| Mask image source | `assetId:string`, `x,y,width,height:number` required; `opacity?`; `fit?` (default `fill`); `preserveAspectRatio?`. |
| `V2MaskLayer` | `maskIds:string[]`, `mode:string?`, `composite:string?` (default `add`). |
| Segmentation source (Swift-only) | `type:"segmentation"`; `mode?:string` (`auto`, `point`, `people`); `at?:V2Vec2` normalized source-image point; `atMs?:number` source time for video. |
| `V2MotionPath` | `offsetPath` required; `offsetDistance:number?` (default 0); `offsetRotate:V2OffsetRotate?` (default `{mode:"auto",angle:0}`); `offsetAnchor:V2OffsetAnchor?` (default `{x:0,y:0}`). |
| Offset path | `type:"path"`; `contours:V2PathContour[]`; `coordinateSpace?` (default `parent-local`); `referenceBox?` (default `border-box`); `pathLength?`; `sampling?`. |
| Sampling | `method:string` (default `adaptive-flatness`); `tolerance:number`; `maxSegments:integer`. |
| Offset rotate | `mode:string` (`auto`, `auto-reverse`, `fixed`); `angle:number`. |
| Offset anchor | `x:number`, `y:number`. |

`V2MaskImagePreserveAspectRatio` and `V2ImagePreserveAspectRatio` both contain `defer:boolean?`, `align:string?`, and `meetOrSlice:string?`.

## 10. Filters

`V2Filter` fields: `id:string` required; `x,y,width,height:V2SvgLength?`; `filterUnits?`, `primitiveUnits?` (`objectBoundingBox` or `userSpaceOnUse`); `colorInterpolationFilters?` (`sRGB` or `linearRGB`); `primitives:V2FilterPrimitive[]` required; `tracks:V2Track[]?`.

Every primitive has shared fields `id:string` required, `in:string?`, `result:string?`, `region:V2FilterRegion?` (`x,y,width,height:V2SvgLength?`), `colorInterpolationFilters:"sRGB"|"linearRGB"?`, plus a `type` discriminator. Fields after the type are:

| `type` | Type-specific fields |
|---|---|
| `feBlend` | `in2:string`; `mode:V2BlendMode?`. |
| `feColorLUT` (Neonix extension) | `assetId:string` referencing a LUT asset. |
| `feVignette` (Neonix extension) | `radius:number`, `intensity:number`. |
| `feVibrance` (Neonix extension) | `amount:number`. |
| `feHighlightShadow` (Neonix extension) | `highlights:number`, `shadows:number`. |
| `feTemperatureTint` (Neonix extension) | `temperature:number`, `tint:number`. |
| `feUnsharpMask` (Neonix extension) | `radius:number`, `intensity:number`. |
| `feChromaKey` (Neonix extension) | `keyColor:string`, `similarity:number`, `smoothness:number`, `shadow:number`, `edgeCleanup:number`. |
| `feColorMatrix` | `kind:string`, `values:number[]?`. |
| `feComponentTransfer` | `functions:V2ComponentTransferFunctions`; optional `r`, `g`, `b`, `a` transfer objects, each tagged `identity`, `table(values)`, `discrete(values)`, `linear(slope,intercept)`, or `gamma(amplitude,exponent,offset)`. |
| `feComposite` | `in2:string`, `operator:string?`, `k1,k2,k3,k4:number?`. |
| `feConvolveMatrix` | `order:V2XYInt`, `kernelMatrix:number[]`, `divisor?`, `bias?`, `target:V2XYInt?`, `edgeMode?`, `preserveAlpha:boolean?`. |
| `feDisplacementMap` | `in2:string`, `scale:number`, `xChannelSelector:string?`, `yChannelSelector:string?`. |
| `feDropShadow` | `dx:number`, `dy:number`, `stdDeviation:V2FilterStdDeviation`, `floodColor:string`, `floodOpacity:number?`. |
| `feFlood` | `color:string`, `opacity:number?`. |
| `feGaussianBlur` | `stdDeviation:V2FilterStdDeviation`. |
| `feImage` | `href:string`. |
| `feMerge` | `nodes:{in:string}[]` on the wire. |
| `feMorphology` | `operator:string?`, `radius:V2XY`. |
| `feOffset` | `dx:number`, `dy:number`. |
| `feTile` | No extra fields. |
| `feTurbulence` | `baseFrequency:V2XY`, `numOctaves:integer?`, `seed:number?`, `stitchTiles:boolean?`, `noiseType:string?`. |
| `feDiffuseLighting` | `surfaceScale:number`, `diffuseConstant:number`, `kernelUnitLength:V2XY?`, `lightingColor:string?`, `light:V2FilterLight`. |
| `feSpecularLighting` | `surfaceScale:number`, `specularConstant:number`, `specularExponent:number`, `kernelUnitLength:V2XY?`, `lightingColor:string?`, `light:V2FilterLight`. |

`V2FilterStdDeviation` and `V2XY` each have `x:number`, `y:number`; `V2XYInt` uses integer `x`, `y`. `V2FilterLight` cases: `feDistantLight(azimuth,elevation)`; `fePointLight(x,y,z)`; `feSpotLight(x,y,z,pointsAtX,pointsAtY,pointsAtZ,specularExponent?,limitingConeAngle?)`.

`V2BlendMode` values: `normal`, `darken`, `multiply`, `color-burn`, `lighten`, `screen`, `color-dodge`, `overlay`, `soft-light`, `hard-light`, `difference`, `exclusion`, `hue`, `saturation`, `color`, `luminosity`. `V2Composite` contains `blendMode?` (default `normal`) and `isolation?:"auto"|"isolate"`.

## 11. Text payload

Text is represented as source text plus shaped/layout-resolved chunks and spans. Layout intent (such as wrapping strategy) belongs in the editor; V2 carries the concrete geometry needed by renderers.

| Object | Fields |
|---|---|
| `V2TextSource` | `text:string` required; `language?`, `direction?`, `writingMode?`, `whiteSpace?`, `textRendering?`. |
| `V2TextLayout` | `lineHeight:number` required; `contentWidth?`, `contentHeight?`, `contentOffsetX?`, `contentOffsetY?`; `background:V2TextBackground?`. |
| `V2TextBackground` | `contours:V2PathContour[]`, `fill:V2Paint`, required. |
| `V2TextChunk` | `id:string`, `sourceRange:V2TextRange`, `spans:V2TextSpan[]` required; `x,y,dx,dy:V2SvgLength[]?`; `rotate:number[]?`; `textAnchor?`; `textPath:V2TextPath?`. |
| `V2TextRange` | `start:integer`, `end:integer` source-text indices. |
| `V2TextPath` | `pathId:string`; `startOffset:V2SvgLength?`; `method?`; `spacing?`. |
| `V2TextSpan` | `id`, `sourceRange`, `font` required; `resolvedFontAssetIds:string[]?`; `fill?`, `fillOpacity?`, `stroke?`, `strokeWidth?`, `strokeOpacity?`, `paintOrder?`; `letterSpacing?`, `wordSpacing?`; `dominantBaseline?`, `alignmentBaseline?`, `baselineShift?`; `textLength?`, `lengthAdjust?`; `textDecoration?`; `kerning?`, `opticalSizing?`, `smallCaps:boolean?`; `shadows:V2TextShadow[]?`; `textTransform?`. |
| `V2TextFont` | `families:string[]`, `size:V2SvgLength` required; `weight:integer?`, `style?`, `stretch?`, `variations:{[axis:string]:number}?`. |
| `V2TextDecoration` | `underline?`, `overline?`, `lineThrough?`, each a style with `fill?`, `stroke?`, `strokeWidth?`, `style?`. |
| `V2TextShadow` | `color:string`, `offsetX:number`, `offsetY:number`, `blur:number`. |
| `V2TextRangeSelector` | `id:string`, `unit:string` (`character` or `word`), `range:"all"|V2TextRange`, `stagger`, `track:V2Track`. |
| Stagger | `perUnitDelayMs:number`; `direction:string?` (default `forward`). |

`letterSpacing` and `wordSpacing` accept `"normal"` or an SVG length. `baselineShift` accepts a keyword (`baseline`, `subscript`, `superscript`) or SVG length. `V2TextRangeSelector` keeps a compact stagger instruction; its template track path is relative to the per-unit span.

## 12. Known boundaries and validation

- Protocol definitions are spread across `ios-editor/Sources/AppModule/Protocol/V2*.swift`; the table above is a human-readable companion, not generated schema output. Keep it aligned with those Codable models when changing the wire format.
- Swift decoding rejects unknown discriminator cases, but it does not check all numeric constraints or cross-references. Examples of invariants to preserve: unique IDs; referenced asset/filter/mask/clip-path/paint-server IDs exist; layer order and hierarchy are valid; keyframe paths and values fit the property; filter primitive references and kernel dimensions are consistent.
- The comments in the protocol models identify several app additions that are not present in the referenced TypeScript package: crop fields on image/video, segmentation/feather/invert mask fields, and Neonix filter primitives including LUT, vignette, vibrance, highlight/shadow, temperature/tint, unsharp mask, and chroma key. Treat these as current app wire-format extensions until there is a shared schema definition.
- Protocol shape support and renderer support are different questions. A model can round-trip a paint, filter, animation value, or geometry shape even if a particular iOS preview/export path does not yet render it fully. Consult the relevant runtime implementation before relying on a feature in output.
