# CLAUDE.md

Short, load-bearing rules for Claude Code sessions in this repo. Keep it that way:
add only new facts or notes that are truly important, and delete what stops being
true (history lives in git; long investigations go in `PLAYBACK_PIPELINE.md` /
`ARCHITECTURE.md`). Source comments point at section names below — keep the names.

## Standing rules

- **No third-party rendering/media engines** (no Skia, FFmpeg, C++ engine). iOS is
  native only: SwiftUI, Core Animation/Graphics/Image, AVFoundation, Metal.
- **Two-tier model.** Editor Document (intent: media + named presets) compiles to
  Protocol V2 (atomic, renderer-neutral). Protocol V2 is never the only persisted doc.
- **Command pattern** for edit/undo (`EditorCommand`), not JSON Patch or CRDT. Undo =
  whole-document snapshots (`EditorHistory`); a drag collapses into one step
  (`beginTrim/updateTrim/endTrim`). No diff engine until size/collab needs it.
- **Valid by construction.** The Swift mirror of Protocol V2 (`Protocol/`) is a full
  *shape* port but has no cross-field validator (dup ids, dangling refs, track-path
  matching): commands must make invalid states unconstructable; no-ops fail closed.
  The TS validator stays canonical.
- **No SVG-import alias fields** (e.g. `V2LinearGradient.angle`) in anything authored.
- Hand-written Swift Codable types are a stand-in for types generated from `schema/v2.json`.
- **In-app UI text is English by default** (conversation stays Vietnamese). Vietnamese is selectable in Account › Language (`AppLanguage`, `Resources/Localizable.xcstrings`, English text is the key; `Text("literal")` translates via the root `\.locale`, a `String` needs `AppLanguage.string`). Translated so far: the Account tab only; new UI text goes in the catalog. Chrome uses system
  dynamic colors (`Color(.systemBackground)`…), never hardcoded black/white.
- Code comments short; non-obvious decisions get a pointer to a section here.

## Playback — read `PLAYBACK_PIPELINE.md` first

- **Measure first.** No playback change without a number pointing at the stage being
  changed. `PLAYBACK_PIPELINE.md` has the stage diagram, metric catalogue, test matrix,
  symptom→stage table, results log (§9) and decision log (§10). Append to it after each
  run. Measurement layer: `Playback/PlaybackMetrics.swift` + HUD (Account › Developer);
  `scripts/playback_report.py`, `scripts/compare_runs.py` summarise CSVs. Baselines are
  taken on a **real iPhone with real iPhone footage** (`public/preview/video/iphone-footage.MOV`,
  190 MB, not committed/bundled; lives in app `Documents/ImportedMedia/`). The simulator
  and the stock clip misled earlier conclusions (stock clip keyframes every 6–8 s).
- **Architecture.** `EditorPlaybackEngine` (`idle/scrubbing/coasting/playing`) is the
  only writer of `currentTimeMs`, driven by `DisplayLinkClock`. Video = one `AVPlayer`
  per layer (`StagePlayerSession`) on the **original file — no proxy, no frame server**;
  `PlayerSeekCoordinator` keeps one seek in flight, newest pending wins (Apple QA1820).
  Raw video renders through `AVPlayerLayer`; filtered video through
  `AVPlayerItemVideoOutput` → Core Image → Metal. Scrub tolerance is a fixed 0.2 s
  (`ScrubTolerancePolicy`), exact at rest. Audio is `AudioMixEngine`, Play only.
  Scrubbing pauses and never resumes implicitly. `EditorPlaybackEngine.init` is cheap;
  players are created in `prepare()`.
- **Momentum** (`MomentumDecay`, `CoastTuning`): `UIScrollView.DecelerationRate.normal`
  curve in closed form (k≈2.0/s), retuned **by the user's feel on the device**: gain 3.3,
  friction ×0.7. No benchmark exists for these numbers — don't "correct" them toward
  native. A touch on a gliding timeline **brakes** it (`engine.brake()`, friction ×20 on
  top, stops in ~0.1–0.25 s); a release only glides if finger speed ≥ 120 pt/s and the finger
  wasn't still > 100 ms (`ReleaseGate`; debug log `Documents/release_log.csv`); the touch-down is a `LongPressGesture(minimumDuration: 0)` —
  a `DragGesture(minimumDistance: 0)` there swallowed the clips' tap-to-select. Unmeasured:
  the lift "kick" from gain, and video keeping up at that speed.
- **Timeline zoom**: pinch (`MagnifyGesture`, simultaneous with the scrub drag), continuous,
  playhead pinned to the panel centre; default 0.096 px/ms (0.5 s per 48 pt). Limits set by
  the user: 5 s per dot zoomed out, 1 frame zoomed in (`TimelineZoom`, 0.0096…1.44 px/ms
  at 30 fps). Ruler = dots on round times (dense ladder 1/2/3/5 frames, 0.25/0.5/1/2/5 s so
  dots stay 48–120 pt apart), with a label on **every second dot** — exactly one dot between
  two labels at every zoom (`mm:ss`, or `Nf` below a second; the ladder is chosen so each
  label time is round). Filmstrip tiles are 48 pt and source-anchored — they do **not** have to line up
  with dots (user decision; a stepped zoom that forced it was tried and dropped). Ruler and
  filmstrip build only a window around the playhead.
- **Latency target**: judge by `visual_lag_ms` (display error ÷ playhead speed, ms of
  time), not `seek_landing_error_ms` (content ms). First real run: ≤ 25 ms only above
  ~3 s/s playhead speed; 40–670 ms when slow (fixed 0.2 s tolerance). §13 has the A/B plan.
- **Device workflow**: build with `-derivedDataPath <scratch>/dd-device -allowProvisioningUpdates`,
  `xcrun devicectl device install app` / `process launch --terminate-existing
  --environment-variables {...}` (Debug env: `PLAYBACK_METRICS_SCENARIO/_LEADIN/_SECONDS/_TAG`,
  `PLAYBACK_SCRUB_TOLERANCE`), pull CSVs with `devicectl device copy from --domain-type
  appDataContainer --domain-identifier com.neonix.editor`. The phone must be unlocked.
  Don't press HUD Start by hand (mislabels runs).
- Footage keyframe spacing decides seek cost; sparse-keyframe imports are undetected
  and 4K/HDR is untested.

## Protocol V2 stays atomic — names are Editor-tier

- Protocol V2 holds only atomic primitives (raw tracks, paint, geometry, SVG filter
  graphs). Anything with a name (fade in, glow, sepia) lives in the Editor Document and
  compiles down (`PresetCompiler`, `EffectPresets`). `V2Effect`/`effects` are deleted
  from both Swift and TS (breaking change to `formatVersion: 2`, no migration). TS side
  still needs `pnpm typecheck/test/generate:schema` run locally (no Node here).
- **Layer transform**: Editor tier = `EditorLayer.transform` (`EditorTransform`: `x`/`y` px from the canvas centre, `scale`/`scaleX`/`scaleY`,
  `rotation` degrees clockwise; every key optional) + `opacity`; `PresetCompiler` lowers it to the object's own `V2Transform` (anchor 0,
  never on the preset's group wrapper, so a preset animates around the resting place). Protocol V2: exactly `translate/scale/rotate/skew/anchor/perspective`; no
  `operations[]` (two representations can disagree). Clip/mask/pattern definitions keep
  their own `V2SvgTransformOperation`. **Anchor** `(0,0,0)` = pivot at the layer's own
  centre; non-zero = pixel offset from it. `scale.z` has no visual effect on flat layers;
  `translate.z` is an apparent-scale approximation.
- **Group layers compose by real nesting.** A track-producing preset (in/out, future
  shake) always wraps the object in an invisible parent `"group"` layer holding the
  preset's tracks; the object keeps its own. Static presets (effects → `filter` id)
  don't wrap. `PreviewCanvas` renders the `parentLayerId` tree as nested SwiftUI views.
- **Text layout stays atomic.** `V2TextLayout` holds only resolved output; intent
  (`textAlign`, `wrap`, …) lives in `EditorTextLayoutIntent`. `TextLayoutCompiler` (Core
  Text) produces one `V2TextChunk` per wrapped line with required `x`/`y`. Per-character
  `dx/dy/rotate` (wave, text-on-path via `TextPathResolver`) are baked at compile time.
  `V2TextSpan.font` stays per-span. Gaps: ellipsis/`maxLines`, `hardBreaks`, text isn't
  track-animatable, letter/word spacing, decoration, baselines.
- **`rangeSelectors`** (stagger/typewriter) stays compact in Protocol V2 — a measured
  exception (~170 B/char expanded). `KeyframeSampler.resolveTextRuns` interprets it;
  `.step` easing is implemented; `.spring` still falls back to linear.
- **Motion path** (`layer.motion`) is resolved per frame at Runtime
  (`MotionPathResolver`, shared `PathFlattening`, SVG arcs supported); no Editor-tier
  authoring yet. Named easing (`easeIn/Out/InOut`) resolves to literal cubic-bezier in
  `PresetCompiler`.
- **Deliberate non-SVG exceptions**: `feColorLUT` (+ `.lut` asset, `.cube` file, no
  intensity field — partial strength = `feComposite` arithmetic), `feVignette`
  (`CIVignette`), `feVibrance` (`CIVibrance`), `feHighlightShadow` (`CIHighlightShadowAdjust`), `feTemperatureTint`
  (`CITemperatureAndTint`), `feUnsharpMask` (`CIUnsharpMask`) and `feChromaKey` (color-cube alpha matte) - all Swift-only like `feVignette`. **Rule: V2 stays
  atomic, Editor names are high level, and the runtime calls the matching CIFilter; a formula is hand-written only where
  Core Image has no filter.** End users never see "LUT" (the tool is "Bộ lọc").
- Unimplemented in the renderer (silent no-op, no diagnostic): `maskLayers` (only `layer.mask` is drawn: shape `children` by the Mask tool, `segmentation` on a photo or, through the matte store, a video by Remove BG), image masks, `composite.blendMode`/
  `isolation`, `enabled`, per-type animatable paths (shape `cornerRadius`, path
  `morph`, video `trimStart/trimEnd/playbackRate`; the Crop *region* is not animatable either).

## Editor

- **Timeline lanes**: `V2Layer.order` identifies a *lane*, not a clip; position inside
  a lane comes from `timing.start`. Lanes are homogeneous by type; clips of one type
  that don't overlap in time may share a lane, else a new `order` (greedy interval
  packing, as `AddTextLayerCommand`/`AddAudioClipCommand` do). Audio has its own domain
  (`V2AudioDomain.tracks[].clips[]`), not `layers[]`.
  **Lane height**: a lane with a video or photo clip (overlays and photo lanes too, `isMediaClip`; not stickers) shows pictures (main lane 48 pt, other video/photo lanes e.g. overlays 38 pt) - a video its filmstrip, a photo one square
  picture tiled over the clip (`PhotoThumbnailCache`, ImageIO, `Image(...resizingMode: .tile)`); text/sticker lanes and audio rows are 30 pt; lane gap 6 pt. **Runway** (`LaneRunway`, CapCut's band): every lane and audio row gets a `secondarySystemBackground` band from 0 to `engine.maxDurationMs` (the end of the longest clip on any lane or audio track), so empty lanes read as one even block. **Trim handle touch area** = the 10 pt of the 14 pt handle next to the clip (was 28).
  The main lane (lowest lane with a video or photo clip of the main track, see Replace / Overlay below) is **pinned under the ruler**; every other
  lane and the audio tracks sit in a **native vertical `ScrollView`** (system momentum and
  bounce — deliberately no custom physics). It scrolls only when the lanes overflow the
  viewport (`.basedOnSize`), and at rest the last lane sits flush with the bottom — blank
  space shows only while overscrolling.
  The horizontal slide is applied *inside* that ScrollView so its bounds stay one screen
  wide; the timeline's scrub drag is a `simultaneousGesture` (a plain `.gesture` blocked
  the scroll) that locks its axis after 4 pt and ignores vertical drags (`LaneScroll`).
  Lanes with a lower `order` than the main one therefore render below it.
  `EDITOR_EXTRA_LANES=N` (Debug) seeds extra lanes for `TimelineLaneScrollUITests`.
- **Trim**: video/image lanes are push lanes (never a gap; the change cascades through
  every later clip, `reflowLane`, tested in `LaneReflowTests`); text/overlay lanes stop at
  the neighbour. Extend may reveal source footage up to the asset duration
  (`AssetDurationCache`). Source time is always `VideoTimeMapping`
  (`trimStart + elapsed × rate`); split shifts the 2nd half's `trimStart` (ms, not s).
  Editing commands still assume `playbackRate == 1`.
  **Main-lane magnet** (`PackMainLaneCommand`, 2026-10-12): the main lane (lowest `order` with a video) never has a hole - after a trim
  drag ends (`endTrim`, same undo step, 0.2 s animation) and after deleting a main-lane clip its clips are laid end to end from 0.
  While a trim is dragged the main lane may go to **negative** times (left edge past t0, clips in front pushed past t0: `reflowLane(floorAtZero: false)`,
  `FilmstripClipView.allowsNegativeStart`); the release packs it back to 0. Edge auto-scroll stops when the playhead reaches 0.
  Text/overlay lanes and audio are not touched. Snap-to-edges is not built yet.
  **After any trim (every lane) the playhead glides (0.2 s) to the dragged edge**: left handle -> the clip's start, right handle ->
  its end, after packing (`EditorPlaybackEngine.glide`). A main-lane left trim lowers `engine.timeFloorMs` so the playhead may follow
  the edge before t0 (edge auto-scroll too); the glide's completion restores the floor to 0.
  **Edge auto-scroll** (`TrimAutoScroll`): a trim handle held within 64 pt of a screen edge keeps going (slow 120 pt/s, within 24 pt
  fast 480 pt/s, on-screen speed so zoom doesn't matter); the playhead runs with it and everything stops together at a limit.
- **Bottom bar = always ONE row** (CapCut style, `EditorBottomBar.swift`, `EditorShellView.bottomMode`): main tools
  (`EditorToolbarView`) -> select a clip/photo/text/audio clip (tap it, or the Edit tool selects what is under the
  playhead) and the row becomes that item's tools (`SelectionToolbarView`) with a "«" back that deselects on
  the left and **Delete pinned on the right**; the tools between scroll. Which tools show and their order is
  `ClipTool.tools(for:hasAudio:)` (the order of each kind is written out there, user list 2026-10-12). Video: Split, Volume*, Speed, Animation,
  Adjust, Filter, Transform, Opacity, Crop, Replace, Duplicate, Overlay, Remove BG, Unlink* (*only with a sound track, probed per selection).
  Text clip: Edit text, Split, Style, Animation, Duplicate, Transform. No Extract Audio any more (the service
  `MediaImportService.extractAudio` stays). The **Text** main tool is a list first: Add text (-> text field) and Auto captions.
  Built: Split, Transform, Adjust, Opacity (opens Transform on its Opacity ruler), Edit text, Delete, audio-clip Volume; every
  other button only shows "<tool> is coming soon" until it is built -> a tool that needs a control (Text field, Audio
  volume, Aspect ratio, Background) replaces the row with `ToolOptionsPanel` and its own "«". Never stack a second row.
  Edit is not a panel any more (its actions are the selection row). UI tests: `EditorBottomBarUITests`.
  **Picking a clip on the timeline closes an open tool panel** (2026-10-17, `EditorShellView.timelineSelection`): `bottomMode` ranks a tool panel above a selection, so tapping a clip with the Audio labels (or the Text list) open
  used to select it but keep the panel; now the tap clears `selectedTool` and the row becomes the clip's tools (`AudioLabelsUITests`).
- **Effects is hidden from the main row** (2026-10-16, `EditorTool.navigationTools`); the case and its sound-effect panel stay for when the feature is built.
- **Tools** (`EditorTool`, panel = `ToolOptionsPanel`): Aspect ratio/Background (edit
  `composition`; layers are not re-anchored), Edit (select, split, delete, trim,
  "Extract audio"), Adjust, Curves, Text, Audio (+ sound effects, record). Selection
  is `EditorShellView.selectedLayerId` / `selectedAudioClipId`. Deferred: Bộ lọc picker +
  `.cube` import, Chú thích (needs AI), Lớp phủ/Nhãn dán (extra image layer + sticker
  library). Roadmap plan: `~/.claude/plans/twinkly-noodling-hearth.md`.
- **Adjust / Transform sheets** (`AdjustSheet`, `TransformSheet`; `.sheet` with a `.height(300)` detent and background
  interaction on, so the stage stays live): `RulerDial` + a scrolling row of round buttons (Scroll variant of the Design Lab;
  Adjust's last button is Curves). `AdjustControl`/`TransformControl` hold per-control keyPath, mapping, neutral. Transform
  writes through `SetTransformCommand` (keeps z/skew/anchor/perspective/tilt) with one undo step per ruler/stage gesture;
  `TransformGestureOverlay` on the stage = drag/pinch/twist. Tests: `TransformCommandTests`, `EditorBottomBarUITests`.
- **Adjust (Tuỳ chỉnh)** (list + order set by the user 2026-10-12): Exposure, Brilliance, Highlights, Shadows, Contrast,
  Brightness, Black point | Saturation, Vibrance, Temperature, Hue, Tint | Vignette, Sharpen, Clarity, Noise, + Curves.
  No Lightness, no Blur (Blur goes to the Effects tool; `EffectPresetKind.blur` stays). `AdjustValues` -> `SetAdjustCommand`
  compiles only the groups that moved off neutral into `EffectPresetKind` primitive chains under a stable filter id
  `adjust-<layerId>` (cleared when neutral): `toneAdjust` (linear exposure+black point, `feHighlightShadow`
  for Highlights/Shadows/**Brilliance** - Brilliance has no CIFilter, it is folded into the other two with
  `adjustBrillianceShadows/Highlights`; linear contrast; **gamma brightness** - the old additive brightness clipped to
  white at +100), `colorGrade` (hueRotate, saturate, `feVibrance`), `whiteBalance` (`feTemperatureTint`), `toneCurve`,
  `sharpen`/`clarity` (`feUnsharpMask`, radius 2.5 / 20 px, negative clarity softens), `vignette`, `noise`. Hand-written
  in the runtime: highlights > 0 (CI only recovers) and negative unsharp. `colorAdjust` stays for documents that already
  use it. Session-only `adjustIntents` cache - reopening
  shows neutral sliders although the persisted filter is correct. `FilterRenderer` (Core Image) implements `feColorMatrix`,
  `feComponentTransfer` (identity/linear/gamma/5-point table), `feGaussianBlur`, `feComposite arithmetic` (k1 = 0), 3×3
  `feConvolveMatrix`, `feTurbulence` (white noise approximation), `feMerge`, `feVignette`, `feVibrance`, `feHighlightShadow`, `feTemperatureTint`, `feUnsharpMask`. **Curves**: 5
  draggable points at fixed x (`CurveGraphView`, `CurveEditorSheet`); `curvePoints` map 1:1 to `CIToneCurve`.
- **Filter (Bộ lọc)** (`UI/Editor/FilterSheet`, built 2026-10-12 from the "A Grid + slider" lab variant): a filter is a **named bundle of
  Adjust values** (`FilterCatalog`, 16 presets in Basic/Film/B&W/Vintage, values judged by eye - tune freely), scaled by Intensity
  (`AdjustValues.scaled`) and compiled by `SetAdjustCommand(layerId:values:filter:)` **before** the Adjust sliders into the one
  `adjust-<layerId>` filter, so sliders keep working on top of the look. No LUT/`.cube` yet (`feColorLUT` is declared but the
  renderer doesn't draw it); bundles can't do per-hue shifts. `FilterSheet`: 340 pt sheet, chips, 4-column grid (None first)
  of thumbnails = the clip's own frame at the playhead through each preset's real chain (`FilterThumbnails`), tap = apply (one
  undo step), Intensity slider only once a filter is picked. Opens from the clip row's Filter and the main Filter tool (like Adjust).
  Session-only `filterIntents` (like `adjustIntents`): reopening a project shows no picked filter although the chain is persisted.
  **Thumbnail cost, measured on an iPhone 13** (`FilterThumbnailBench`, Debug; `FILTER_BENCH=1`, optional `FILTER_BENCH_VIDEO`, result in
  `Documents/filter_bench.txt`, pull with `devicectl ... copy from`; interleaved pipelines, 12 frames, 89 s 1080x1920 footage): the first
  version (fresh `AVAssetImageGenerator` frame at 300 px + 16 renders at 300 px) took ~33-50 ms wall / ~12-15 ms in-process CPU per grid; the
  current one (nearest `VideoFrameCache.baseThumbs` filmstrip thumbnail shrunk to 160 px, rows rendered first, per-(frame, preset) cache)
  ~11-15 ms wall / ~9-10 ms CPU, and **0 on reopening**. The video decode shows ~1 ms CPU in our process (hardware decoder) but ~19 ms wall.
  The first grid of a process also pays ~140 ms wall / ~60 ms CPU of cold Core Image. A fixed illustration instead would save only the
  remaining ~10 ms, so it was not worth it. The simulator's numbers differ a lot (software decode): measure on the phone.
- **Templates** (`Network/`, `Templates/`, `UI/Home`, `UI/UseTemplate`, `Export/`; server: `api/`, spec
  `api/docs/template-package.md`, starter templates + `build.py`/`publish.py` in `templates/`): a template is a zip of
  `manifest.json` + `document.json` (an `EditorDocument`, incl. an `audio` domain for the music) + `assets/`, generated
  by `TemplateFixturesTests` (edit the builders there, never the JSON). Media slots (`kind: "media"`) take a photo or a
  video: video shorter than the slot is refused, longer is cropped to a window of exactly `durationMs` (`trimStart`);
  `TemplateFiller` swaps media in, `TemplateProjectBuilder` compiles and gives text layers their own lanes (`EditorDocument`
  has no lanes). Package `assets/` are copied into `ImportedMedia` and their URIs rewritten (the flat resolver
  `bundledURL` stays). Home = poster cards only (nothing plays there); the preview video plays when a template is opened in the viewer.
  Slot picker is a PhotoKit grid, not `PhotosPicker`. After the picker the template flow does **not** open the full
  editor: `TemplateEditView` is the result screen (preview, slot strip with replace/crop, Audio = music on/off, Text =
  the template's texts, Export), driven by `TemplateEditModel`, which rebuilds the project from the creator's document
  on every change (`TemplateBuild`; nothing is patched in place). The full `EditorShellView` stays for projects (Folder). **A template is bought once, by its first Export** (`ExportGate` → `POST /v1/exports`: spends the
  price, owned for good, later exports of it are free; `owned` flag in the catalogue); the download is free. Pro add-ons
  (later) are separate purchases, not a per-export fee. **There is no video renderer yet** (`UnavailableExporter`):
  Debug builds charge anyway so the flow can be tried, Release refuses without charging. Debug talks to the API with the
  `X-Dev-User` header (server `DEV_AUTH_BYPASS=true`); Release uses the Keychain bearer token (sign-in not built).
- **Stickers** (`UI/Editor/StickerSheet`): main-nav tool, "B Grid+" sheet (340 pt + large, category chips, 4-col grid). Catalogue =
  `GET /v1/stickers` (manifest + PNGs in R2 `neonix-system-assets/stickers/`, 50 Fluent Emoji 3D, MIT notice stored there;
  `scripts/publish_stickers.mjs`). Bucket is private -> API hands out 1 h presigned URLs (set `R2_SYSTEM_ASSETS_URL` once public).
  `StickerStore` caches images by id on disk; a pick copies the PNG into `ImportedMedia` and `AddStickerCommand` adds an image
  layer (id `sticker-*`, 3 s, 35 % of the short side). `sticker-*` layers are free overlays (stop lanes, `isPushLane`).
  A sticker is its own **kind** in the editor (`ClipKind.sticker`, told by the id prefix; still an image layer in Protocol V2): timeline clip
  colour #F5B52E, tools Split, Animation*, Duplicate (`DuplicateOverlayCommand`), Mirror (`MirrorLayerCommand`, negative `scale.x`;
  Transform keeps the sign), Transform, Delete pinned (*coming soon).
- **Keyframes** (Transform only; `UI/Editor/Keyframes/TransformKeyframes.swift`, 2026-10-13): one Protocol V2 track per property
  (`transform.translate.x/y`, `scale.x/y`, `rotate.z`, `opacity`; ids `kf-<path>`), keyframe times are **clip-local ms** (V2's own
  convention), and the six tracks always share the same times - one ◆ = one time on all of them. A graph (easing) lives on the keyframe
  where its segment starts (`SetKeyframeEasingCommand`; "Original" = no easing). Keyframe icon next to fullscreen = `AddKeyframeCommand` /
  `RemoveKeyframeCommand` (one undo step each; removing the last bakes its values into the static transform); Graph tool is live only
  between two keyframes. On a keyframed layer a Transform edit becomes a keyframe at the playhead (`SetTransformCommand(atMs:)`, auto-
  keyframe) and the sheet shows the sampled values; Mirror negates the `scale.x` keyframes. **Split** (CapCut's way, confirmed by the user): each half keeps only its own
  keyframes (the second re-timed) and, when the cut is inside the animated range, gets a keyframe at the cut (end of the first, start of
  the second) holding the interpolated value; a bezier graph on the cut segment is divided exactly (`splitEasing`, de Casteljau). **Left trim** shifts the keyframes' local times so they stay with the
  picture (may go negative). Adjust/Filter are not keyframed. The graph picker still uses the Design Lab's `LabEasing` (style not final).
- **Speed** (`UI/Editor/SpeedSheet`, 2026-10-15): the clip row's Speed (video only) opens a sheet laid out like Adjust/Transform - Reset (back to 1x) / title / Done, a **ruler** (`RulerDial` with `RulerMapping.speed`),
  and two round buttons, **Normal** (built) and **Curve** (placeholder). Range **0.1x - 9x** (`SpeedScale`): on an iPhone 13 with 1080p60 HEVC the system plays full frames up to 9.5x but only key frames (10 fps) from 10x
  (`PLAYBACK_PIPELINE.md` §9, 2026-10-15), so 9x is the cap; the ruler is **linear, one tick = 0.1x**, opening on 1x (left reads 0.9x ... 0.1x, right 1.1x ... 9x), a major tick at each whole number. Normal shows "Duration: 3.9s -> 3.2s". `SetClipSpeedCommand`: the clip keeps its footage
  (`trimStart` unchanged, `playbackRate` = the rate, absent at 1x), `timing.duration = source span / rate` (never under one frame), its keyframes scale with the length, the clips after it in the lane follow (`reflowLane`),
  animation wrappers follow via `normalized`. **Split and the trim handles are rate-aware** (the source moves `rate` ms per timeline ms; the second half's `trimStart` += cut x rate). The sheet works live and the whole
  session is one undo step: the shell keeps the project before the first change (`speedSessionOriginal`, taken *lazily at the first tick* - taking it when the sheet opens came back nil inside the sheet's closure) and records it on dismiss.
  **Curve** (built 2026-10-15, after CapCut's "Custom"): a speed that changes along the clip. Model: `V2VideoPayload.speedCurve: [V2SpeedPoint]` (`sourceMs` into the clip's source stretch, `rate`, optional `slope`), replacing
  `playbackRate`; `SpeedCurve` (Runtime) is the maths - `ln(rate)` is a monotone cubic through the points (smooth, never overshoots, always inside 0.1x-9x), a 640-cell table of the integral of 1/rate gives both
  directions of the time map (source <-> output) and the clip's length; `VideoTimeMapping` goes through it (`rate` = the average, used by the filmstrip; `rate(atTimelineMs:)` = the speed now). The x axis of the graph is the **source
  footage** (so it does not move while you edit); the clip's length is what the curve takes. `SetClipSpeedCurveCommand` (shares `retimedClip` with `SetClipSpeedCommand`: keyframes scale, the lane follows); a curve that is 1x
  everywhere is no curve; the Normal ruler replaces a curve with a constant rate. **Split** cuts the curve where the source is at the cut, **trim** removes/extends the matching piece at each edge (an extension is flat); the cut
  pieces carry explicit `slope`s so they are exactly the same function as the original. UI (`SpeedCurveEditor`): three lines - 9x top, 1x middle (solid), 0.1x bottom - each half logarithmic (`SpeedGraphAxis`), five beats at 1x to start,
  drag a beat vertically (inner ones also sideways), a black line = the playhead, **draggable** (round handle on top or the line; scrubs the clip through the engine, a beat under the finger wins over the line), **one + / - icon** (+ adds a beat at the playhead; on a beat, or a picked one, it is a - and removes it), Reset (the toolbar) flattens, the sheet is
  taller (440) on Curve. **Playback**: the engine's tick sets each playing curved clip's player rate to the curve's speed at its own source position (`StagePlayerSession.follow(rate:)`, only when > 3 % off); the playhead follows the
  player's clock. **Not measured on the iPhone yet**: how closely the footage keeps to the curve while playing (`SpeedBench` with `SPEED_BENCH_CURVE=1`, the device was unavailable). Not built: audio-clip speed, "Change audio pitch"
  (the video's own sound is played by `AudioMixEngine` since 2026-10-18, at normal speed only - see Volume below; the stage players stay muted), the preset curves (Montage, Hero, Bullet...), "Smooth slow-mo". A speed change while playing takes ~150-300 ms to show in the clock and may step it
  back one tick.
- **Replace / Overlay / Duplicate / Style** (2026-10-15; `UI/Editor/Commands/MediaCommands.swift`, `UI/Editor/MediaPicker`): **Replace** (video, photo) swaps a clip's footage through the library picker (`EditorMediaPickerView`, the template flow's
  `PhotoLibrary`/`AssetCell`/`PhotoImporter`; a video shorter than the clip's footage is dimmed) with `ReplaceClipCommand` - place, length, transform, keyframes, filter, animations and (video -> video) the speed stay; the new footage starts
  from its beginning; video <-> photo drops what only one kind has. **Overlay** (video, photo) = `CopyToOverlayCommand` (user 2026-10-16: it does **not** ask for media): the selected clip is copied into an overlay layer (id `overlay-*`, `overlayLayerIdPrefix`) - same footage, speed, place and
  length on the timeline, half the canvas size in the middle, on top of everything, no keyframes/animations, the clip's opacity and filter kept - and the copy is selected. It goes in an overlay lane that is free for that time else a new lane above
  everything; like stickers it is a **free clip** (`isPushLane` is false, gaps allowed) and never the main lane. **Main lane** (`primaryVideoLaneOrder`, shared by the timeline and the commands): the lowest `order` holding a video **or photo**
  clip of the main track (stickers and overlays never count) - so a main lane whose video was replaced by a photo is still the main lane (it used to lose its cover cell and shrink to a thin row). **Duplicate** (video, photo, text, sticker; not audio yet) = `DuplicateClipCommand`: a clip of a push lane gets its copy right after it and the lane's later clips move later by its length; free clips
  (text, sticker, overlay) go through `DuplicateOverlayCommand`; the copy keeps speed, keyframes, animations (wrappers of its own) and a text clip's `TextIntentCache` entry. **Style** (text) opens the Text sheet on its Style tab. After new footage
  lands the shell calls `engine.refreshFrames()` (a new player has never been positioned). Not verified end to end in the Simulator: picking a real library item (PhotoKit) and an overlay *video* on the timeline. Still "coming soon":
  Unlink, audio Speed / Duplicate.
- **Remove BG - photo (Phase 1) and video Auto (Phase 2) built** (2026-10-18; research numbers in `PLAYBACK_PIPELINE.md` section 9, bench `RemoveBackgroundBench`, `REMOVEBG_BENCH=1`, device only): Vision's `VNGenerateForegroundInstanceMaskRequest` costs ~16 ms/frame on an iPhone 13 whatever the input size, picks the "salient object" itself; `VNGeneratePersonSegmentationRequest` is cleaner on people
  but keeps everyone in a crowd - **the default is the foreground instance** (`SegmentationService.matte` also has a "people" mode, no UI). **The simulator has no Neural Engine: Vision finds nothing there, so a photo stays whole and the pipeline test (`SegmentationServiceTests`) skips - judge the cut-out on the iPhone. Verified on an iPhone 13 (2026-10-18): the unit test passes (subject kept, corner clear, Invert flips) and `RemoveBackgroundUITests` shows the cut-out on the stage and in the picker; the cost of the first cut-out was not timed.**
  **Model**: a third mask source, `V2Mask.segmentation: V2MaskSegmentation {type: "segmentation", mode: "auto" | "point", at?: V2Vec2 (fractions of the picture, top-left), atMs?}` next to `children` / `image` (exactly one); the matte is in **picture space** (applied before crop), `maskType` alpha, unknown mode / missing `at` = no-op; it reuses `V2Mask.feather` / `invert` (Swift-only, the TS package must copy all of it).
  For a photo the matte is **derived data, never stored**: `SegmentationStore` (in-memory matte + cut-out caches, in-flight dedupe, `isWorking` drives the spinners) runs Vision + Core Image off the main thread (`SegmentationService.cutout`: `CIBlendWithMask`, explicit DeviceRGB `createCGImage`) and recomputes after a relaunch. **Render**: the image branch of `LayerContentView` is `SegmentedImageView` - the original shows until the cut-out is ready, then the cut-out (the filter runs on whichever shows); `MaskEffect` ignores masks without `children`; the mask's `feather` is px of the layer's box, converted to picture px.
  **Tool** (photo and photo overlays; video is below): the clip row's Remove BG -> `RemoveBackgroundToolRow` (None, Auto removal, Choose subject; ids `removeBg-*`), a tap on the picked tile opens `RemoveBackgroundSheet` (Feather slider + Invert; Choose subject adds `SubjectPicker`: the whole picture on a checkerboard, original faded + cut-out, **tap = the subject** `at`, 480 pt vs 250 pt). `SetLayerSegmentationCommand` / `RemoveBackgroundDraft` (the mode is told by the mask id `removebg-<layer>~<mode>`); `MaskBook` is shared with the Mask tool, so **a layer has either a shape mask or Remove BG** (the last one picked wins), copies keep their own mask. Live edit, one undo step (`maskSessionOriginal` is shared). Debug: `EDITOR_SELECT=<layer id>` preselects a clip and puts the playhead on it. Tests: `RemoveBackgroundTests` (7), `RemoveBackgroundUITests` (the flow; run it on the iPhone to see a cut-out).
  **Video (Phase 2, built and measured on the iPhone 2026-10-18; Auto only - Choose subject would need the subject followed between frames)**: the clip row's Remove BG on a video offers None / Auto removal. Auto starts `VideoMatteJob` (`SegmentationJobs`, one per layer, started by the shell's `.task(id: removeBgJobsSignature)` so it follows apply, trim, reopen): the file is read once with `AVAssetReader`, forward, twice at most (from the playhead to the end, then the start up to the playhead),
  each frame on a **30 fps grid of the source time** gets Vision's foreground-instance mask (every instance, no tracking), stored as **512 x 512 8-bit LZFSE** per frame in `Caches/SegmentationMattes/<file>-<size>-auto4/<index>.m` (`MatteSet`, `VideoMatteStore`; derived data, a cancelled job keeps its frames, the next one only fills the gaps; the folder suffix is the matte format version). Measured on an iPhone 13: **~47 frames/s, a 21 s clip in ~13 s** (`PLAYBACK_PIPELINE.md` section 9).
  **The progress card** (`RemoveBackgroundProgressCard` over the stage: a ring that fills with the percentage in the middle, "Removing background", **Cancel**; the tile in the row shows a small spinner) lasts while the job runs; **Cancel takes Remove BG off the clip** (one undo step, `cancelRemoveBg`) and keeps the frames done. Frames near the playhead are cut first, and the stage shows the cut as soon as a frame has its matte (frames without one show whole).
  **Render**: `FilteredPlayerMetalView` takes the matte of the frame's source time (`MatteSet.matte(atSourceSeconds:)`, a neighbour frame at most), stretches it over the picture, applies the mask's feather / invert and `CIBlendWithMask`; with a matte the Metal layer is **not opaque** and writes every pixel, and the raw `AVPlayerLayer` under it is hidden once it has drawn (it would show the background through the cut). If Vision returns an all-zero matte, it is stored as a full-foreground matte so a missed detection preserves that video frame instead of turning it transparent black. `FilteredPlayerView.filter` is optional now (a cut without a filter).
  **Lessons**: (1) a long loop that decodes and runs Vision needs an `autoreleasepool` per frame - without it memory grew ~8 MB/frame and iOS killed the app at ~250 frames, silently; (2) `preferredTransform` must go through `VideoOrientation` (EXIF orientation), never be applied to a `CIImage` directly - it turned portrait iPhone clips upside down on the filter/Metal path (existing bug, fixed); (3) the Metal view's own `CIContext` lacked `.workingColorSpace: NSNull()`, so every filtered / cut video came out washed out (RGB 58 -> 127 and 167 -> 210 = gamma applied twice; after the fix the cut frame equals the raw one, 58/57/55 and 167/126/112 on the iPhone); (4) **the matte is looked up by the time of the frame the player really handed over** (`copyPixelBuffer(forItemTime:itemTimeForDisplay:)`), never by the playhead: while scrubbing the player lands up to 0.2 s (median 191 ms measured) from the requested time, and the cut sat a few pixels off the person; the job also feeds each 30 fps grid index from the source frame nearest to it (not the first one, 1/60 s early on a 60 fps clip) - the matte can still be up to one source frame (16.7 ms) off on a 60 fps clip; (5) **a second video on the main lane draws over the first from t = 0** (`LayerNodeView.isOutsideItsTime` leaves video layers always drawn, a playback decision) - so the two test projects hold one clip each. Not changed.
  Test projects (Debug, Projects list): **Selfie (Remove BG test)** and **Crowd (Remove BG test)** = `demo-nguoi1.MOV` / `demo-nguoi2.MOV` from `public/preview/video` (copy them into the app's `Documents/ImportedMedia`; already on the iPhone). Tests: `VideoMatteTests` (store, codec, job, cancel + restart, memory, orientation), `RemoveBackgroundVideoUITests` (ring, Cancel, finish, popup - iPhone, `REMOVEBG_CLEAR_MATTES=1` empties the cache; `TEST_RUNNER_RBV_SIMULATOR=1` runs the flow on the simulator with empty cuts), `RemoveBackgroundPlaybackUITests` (measurement runs: `EDITOR_AUTO_REMOVEBG`, `EDITOR_AUTOPLAY_AFTER/FOR`).
  Not built: Choose subject on video, rendering the cut in the timeline thumbnails, the export (no renderer), a matte at a finer grid than 30 fps or higher than 512 px (edges are soft where the matte is stretched), refreshing when the clip's footage is extended past the cached range (the new frames get a job again).
  **Chroma key (Phase 3, built)**: see the Design Lab comparison and production `feChromaKey` entry below. It appears in this same Remove BG option row; Chroma key and segmentation Remove BG replace each other, while a shape mask can remain alongside the chroma filter. The transparent-background issue of the filtered video path is already handled for the Vision cut.
- **Mask** (2026-10-18, `UI/Editor/MaskSheet` + `Commands/MaskCommand.swift`; the lab's layouts, then the user's flow): the clip row's **Mask** (video, photo, overlays - same kinds) replaces the bottom row with `MaskToolRow` (None, Horizontal, Mirror, Circle, Rectangle; "«" back to the
  clip row). A tap on a shape applies it (`SetLayerMaskCommand`, one undo step) and puts its yellow outline and round handles on the live stage (`MaskGestureOverlay`, placed like `TransformGestureOverlay`'s outline: the layer's box turned / scaled / moved by its static transform; drag inside = move,
  right handle = width, top = height, chevron under = feather, top-left on a rectangle = corner roundness, two-finger twist = rotate); the picked shape shows an adjust icon and **a tap on it opens the popup** (`MaskSheet`, 300 pt, the lab's "controls on top, round buttons below": the ruler or slider of the chosen
  parameter, then round buttons Position / Rotate / Size / Feather / Round (rectangle) / Invert; Position and Rotate (two ways from 0) on Transform's `RulerDial` with an X/Y switch, Size / Feather / Round on sliders; Reset and Done on top). Handles and popup edit live (`setMaskLive`, no history); a whole edit is one undo step
  (`maskSessionOriginal`, closed when the popup or the row closes, or another shape is picked). **Model**: Protocol V2 already had masks (`project.masks[]`: `V2Mask` with one source - `children` shapes or `image` - named by `layer.mask`); this tool writes a `V2Mask` with `children` **in the layer's own pixels** (the default
  `maskContentUnits`, so a rotation stays a rotation on a non-square box) and the new Swift-only, source-independent fields **`feather`** (Gaussian blur of the finished matte, in the mask's user-space px; absent = hard) and **`invert`** (absent = false) - the TS package must copy them. The mask's **id carries the shape**
  (`mask-<layerId>~<shape>`), so `MaskDraft(layer:masks:)` reads the intent back after a reload; editing a layer whose mask a split half / copy still names gives that other layer a copy first; masks no layer names are pruned. **Render**: `MaskEffect` in `PreviewCanvas`, after `CropEffect`, draws the matte with `MaskMatteView`
  (rect / circle / ellipse / polygon / group, `transform`, `fillOpacity`; path / line / polyline not yet) as a SwiftUI `.mask`. Outside the mask the stage shows the composition background. **Not measured**: what `.mask` costs on a playing video on the iPhone (it may be drawn off-screen). Not done: mask keyframes (`V2Mask.tracks`), Heart / Stars shapes,
  mask on text / stickers, the `type` discriminator on `V2MaskImageSource` (the TS schema has `type: "image"`), Remove BG is the third source (above). `MaskStage` / `MaskHandlesLayer` (the picture version and the handles) are shared with the Mask lab. Tests: `MaskTests` (16), `MaskUITests`.
- **Crop** (2026-10-18, `UI/Editor/CropSheet`: `CropSheet`, `CropStage`, `CropDraft`; the Crop lab's layout B, then the user asked for a **full-length popup like Stickers**): the clip row's Crop (video, photo) opens a popup as tall as the screen:
  Reset (back-arrow icon) and Done pinned in the title bar, the picture with its frame (`CropStage`, **no card behind it**) on top, a **play button + time bar for a video only** (`CropPlayback`: a real muted `AVPlayer` on the file drawn by an `AVPlayerLayer` (`CropPlayerLayerView`) over the still, the bar is the clip's fraction mapped onto its source stretch; one seek in flight while dragging, exact on release; **a photo has none**; measured on an iPhone 13: ~57 frames/s vs 6.7 with a still every 150 ms, `PLAYBACK_PIPELINE.md` section 9),
  then Aspect tiles / Rotate ruler (-20...20 deg) and the round buttons Aspect / Rotate / Flip. Drag a corner to resize (the opposite corner stays), drag inside to move, an aspect (Custom, 9:16, 16:9, 1:1, 4:3, 3:4, 2:1) locks the ratio.
  The frame is a draft; closing the popup (Done or swipe) stores it with one `SetClipCropCommand` (one undo step; a crop that changes nothing is stored as none, a region under 2 % or outside the picture is refused).
  **Model**: `V2Crop` (Swift-only; the TS package has none) on the image and video payloads - region as 0...1 fractions of the picture + `rotation` + `flipped`. **Render**: `CropLayout` (pure) + `CropEffect` in `PreviewCanvas` turn the picture
  about the frame's centre (flip, straighten, a zoom that keeps its corners out), blow the region up as large as it fits the frame and mask to it - **the layer's frame, transform and keyframes are untouched**, so selection outlines and Transform
  still use the full frame. Replace drops the crop. Not done: crop in the timeline thumbnails, the export (no renderer yet), animating the region, "AI expand", a stored aspect lock (reopening starts on Custom), a photo test of the popup.
  The popup is opened with `.sheet(item: $cropSession)` (`CropSession` carries the `CropVideo`): reading `cropLayerId` back from the shell's `@State` inside the sheet's content closure returned nil. Tests: `CropTests`, `CropUITests` (also run on the iPhone: the bar's progress keeps real time). The corner brackets have a dark underlay (plain white vanishes on a light picture).
- **Animation** (`UI/Editor/AnimationSheet`, `EditorDocument/Animation{Catalog,Wrappers}.swift`, 2026-10-14): the clip row's Animation tool (video, photo, text, sticker) opens a sheet after CapCut - tabs **In / Out / Combo**, group chips,
  a 4-column grid (None first), a Duration slider for In/Out. 13 entrance/exit presets (Fade, Zoom In/Out, Slide x4, Rotate, Spin, Bounce, Pop, Swing, Drop) and 6 loops (Pulse, Heartbeat, Shake, Sway, Float, Blink); Glitch/Mask/Light-style
  looks need their own effects and are not built. A preset is a few channels of normalised keyframes lowered into atomic V2 tracks: In = absolute from the clip's start, **Out = the same motion mirrored and end-anchored** (trim-safe), Combo = one
  cycle with `animation.iterations: infinite`. **Each animation is its own invisible parent group layer around the clip** (clip -> In -> Out -> Combo, in the clip's place in the layer array), so the clip's own keyframes never collide; the wrapper's **id
  carries the pick** (`<clip>~anim~<slot>~<preset>~<ms>`), so the sheet reads it back and undo/redo need no second state. `AnimationWrappers.normalized` (run by the shell's `setProject`) makes each wrapper mirror its clip's timing/frame/lane and drops
  those whose clip is gone; **Split** keeps In on the first half, moves Out to the second and loops a Combo on both; **Duplicate** gives the copy wrappers of its own. Picking a preset plays it on the stage (`previewAnimation`: glide to the clip's
  start / just before its end, play, pause). `SetAnimationCommand` is one undo step; the Duration slider commits on release. The tiles are **live previews** (2026-10-17, `AnimationPreviewTile` / `AnimationPreview`): each plays its preset in a loop on `preview-animation.png` (a hot-air balloon; the original is in `public/preview/image/`, a 800 px copy in `Resources/Media/`), reading the same channels as the V2 tracks (easing is a stand-in for the real beziers); None keeps its icon.
- **Text tool** (`UI/Editor/TextSheet`, 2026-10-13, layout B of the Design Lab's *Text picker*): "Add text" (Text tool list) puts a clip with
  the default words "Hello" at the playhead (selected on the first tap of the field, so typing replaces them) and opens the **Text sheet** on it; "Edit text" in a text clip's row opens the same sheet. Two tabs,
  **Font** (22 iOS system fonts, `EditorFont`, each name drawn in its font) and **Style** (a scrolling row of badges on top, each with its own content below, after CapCut): **Text** = a row of ready-made "Aa" looks (`TextPreset`: text colour + label) + Size; **Colors**; **Stroke** (colour + Width); **Glow** (colour + Intensity + Blur); **Background** (none / hug = story style / box tiles, colour, Opacity, Corner radius, Height, Width); **Shadow** (colour + Opacity, Blur, Distance, Angle); **Curve** (one slider -100...100, `TextCurve`: an arch or a bowl, per line, baked into per-character dx/dy/rotate); **Spacing** (alignment + Character + Line); **Case** (Bold, Italic, Underline, TT / tt / Tt - the user merged Bold italic into Case). Code: `TextStyleSections.swift` (one section per badge, every control writes `TextStyleValues`, live to the clip). Effects in `TextStyleValues` are **fractions of the font size** (outline, glow, shadow, spacing). **Protocol V2 additions** (Swift only; the TS package is not here to follow): `V2TextSpan.shadows: [V2TextShadow]` (colour with alpha, offset, blur - a glow is a zero-offset shadow, two layers) and `textTransform`; the rest already existed (`stroke`/`strokeWidth`/`paintOrder`, `letterSpacing`, `font.weight`/`style`, `textDecoration`). `V2TextBackground` carries only the resolved path and the fill (alpha = Opacity). **Case** keeps the typed words in `source.text`; the layout compiler measures the transformed words and the renderer draws them. **Renderer** (`UI/TextRunView.swift`): a run without outline is plain SwiftUI `Text` (face resolved through `TextLayoutCompiler.resolveFont(..., bold:italic:)`, tracking, underline); a run with an outline is drawn from its glyph outlines (`GlyphOutline`, cached; stroke under the fill, round joins); shadows/glows are blurred copies behind. **Text layers are not clipped to their frame any more** (an outline or glow reaches past the text block). **Read-back**: V2 gives back words, font, colours, outline, glow/shadow, spacing, case, bold/italic/underline, label colour+opacity; what V2 keeps only as geometry (label padding / radius / style, curve) comes from `TextIntentCache` while the clip's text payload is exactly what it compiled to (undo/redo or any other rewrite makes the entry stale -> defaults). **Colours** (`UI/Editor/ColorPicker`, shared by every badge): `ColorSwatchGrid` = the rainbow button (+ a "none" dot where the colour is optional) and 40 swatches (`ColorPalette`: 2 neutral columns + 18 hues in 20° steps, vivid over soft tint) in a two-row grid scrolling sideways; the rainbow opens `ColorPickerPanel` (saturation/brightness square + hue bar, ✕ restores, ✓ keeps) **in place of the whole sheet content**, live on the stage; kept custom colours are remembered first in the grid (4, `UserDefaults`). The eyedropper (needs a stage pixel read; AVPlayerLayer video may not be capturable) is deferred. The sheet rests at 320 pt, **520 pt on Background and 460 pt on Shadow** (four sliders each, `restingHeight`), the text field
  heading the sheet (CapCut's layout; ✓ closes). **While the field is edited the content is hidden and the sheet shrinks to the field + tabs
  (measured head height, ~90 pt; `KeyboardBench`, iPhone 13: keyboard 335 pt incl. the 34 pt home area, a fixed 130 left 62 pt blank)**, because the system lifts a sheet by the keyboard's height and a full sheet would cover the stage; a tab tap ends the editing and
  brings the content back. Every change is live (`SetTextCommand`, bypassing `apply`) and the whole session is **one undo step**;
  closing with empty words discards it (a new clip disappears, an old one keeps its words). `TextStyleValues` reads the look back from
  the clip's first span; sizes are canvas-relative (default 8.9 % of the width = the old 32 on 360). Everything goes through the real
  `compile(_:)` text pipeline (`AddTextLayerCommand(style:)`, `SetTextCommand`, `SetTextContentCommand` keeps the look), never
  hand-built chunks. **Multi-line** (Return = new line, the check mark closes) with **alignment** (left/centre/right; V2 keeps only each
  line's resolved x, so `TextStyleValues` reads it back by asking which alignment reproduces those x's). **Background label** (Facebook /
  Instagram story style, user's reference 2026-10-14): one rounded shape hugging every line - convex corners outside, concave fillets where
  lines of different length meet. Intent = `EditorTextBackground {color}`; `TextBackgroundGeometry` resolves it at compile time into
  `V2TextLayout.background` = `{contours: [V2PathContour] (lines + arcs), fill}` (atomic, layer-local coordinates, the same space as the chunks'
  x/y; padding 0.32 / 0.10 and radius 0.30 of the font size). The lines are laid out in a box narrowed by the padding and shifted in, and the
  clip's frame is exactly the text block (+ padding), so a text clip is centred where it was added (it used to be top-anchored in a fixed
  80 pt frame). **The TS side (`packages/motion-protocol`) has not got `layout.background`, `span.shadows` or `span.textTransform` yet** (the user removed that folder from the working
  tree on 2026-10-14 to focus on Swift; the deletion is not committed - restore it from git when the protocol is worked on again). Not built yet: wrap, repositioning on the stage, templates/animations for text. Unverified: the keyboard's effect on the 320 pt sheet on a small iPhone.
- **Audio**: `AudioMixEngine` (`AVAudioEngine` + one node per active clip) plays only
  during Play, resyncs on every `play(atMs:)`, no sample-accurate master clock. **Never
  call `engine.start()` without a source** (it hung the test runner for 600 s). Import:
  `MediaImportService` (copies into `Documents/ImportedMedia`, mints `V2AudioAsset`;
  `bundledURL(filename:)` falls back to that folder). Sound effects are synthesized
  placeholders with stable ids (`sfx-*`); Extract exports the whole asset audio once to
  `extracted-<name>.m4a` and trims per clip; Record = `AVAudioRecorder` → same import
  path (needs `NSMicrophoneUsageDescription`, shows a hint when permission is denied).
  **A video's own sound and its Volume** (2026-10-18): `AudioMixEngine.update` makes a source for every video layer unless `payload.audio.enabled == false`, reading the sound straight from the video file (or its audio derivative; `AVAudioFile` opens
  the audio of an mp4/mov with picture), at `payload.audio.gainDb` (absent = 0 dB) from `trimStart`. **Only at normal speed**: a clip with `playbackRate != 1` or a `speedCurve` stays silent (the engine never retimes). A file with no sound track is
  tried once (`unreadable` cache), not on every tick. **This made every video with sound audible on Play** (it was silent before). The overlay copy (`CopyToOverlayCommand`) is silent (`enabled: false`) so the same sound does not play twice.
  **Volume for video**: the clip row's Volume (enabled only when the file has a sound track, probed per selection) opens the same `VolumeSheet` with **Volume only - no Fade** (`showsFade: false`; the sheet is as tall as the audio one, 270 pt, and under the slider two round icons, sound on / muted, that only
  show the state - not buttons - the muted one lights up at 0); `SetVideoClipVolumeCommand` writes `payload.audio.gainDb`, the whole session is one undo step (`finishVolumeSession` compares audio-clip and video gains). Not done: the timeline's mute button on the main lane is still a placeholder,
  sound for sped-up clips, fades and waveform for a video's own sound, Unlink. Not verified by ear (the simulator has no sample with sound): `VideoVolumeTests` cover the command and the source list, `EDITOR_VIDEO_HAS_SOUND=1` (Debug) lets
  `VideoVolumeUITests` open the popup on a silent sample.
  **Never put a SwiftUI `LongPressGesture` (or a sequenced one) on anything inside the lanes' `ScrollView`** (2026-10-17): it made the scroll refuse swipes that began on that
  clip (simulator, `TimelineLaneScrollStabilityUITests`: 6 of 20 swipes did nothing; the app's logs showed the touch arriving and no state stuck). Lifting a free clip is
  a UIKit `UILongPressGestureRecognizer` on the screen's root view (`ClipPressDetector`, 0.3 s, fails on 10 pt of movement, runs alongside the scroll pan); a hit test
  against the lane frames says whether the touch began on a free clip. The lifted clip follows that recognizer, not the scrub drag.
  **Moving an audio clip** (2026-10-17; the same long press, `PressedClip.layer/.audio`; `UI/Editor/Commands/AudioMoveCommand`): audio moves only among audio tracks, never into picture lanes - the blue line between the
  audio section and the overlays is a wall. The track under the float wins if the clip fits there (`AudioMove.fits`); over an occupied track, a gap between tracks, above the first track or below the last it becomes a **new
  track** inserted there (`AudioMove.resolve` -> `MoveAudioClipCommand`; a track left empty is dropped). The float shows the waveform; the float is anchored by where it was grabbed (`grabMidY`), for picture clips too.
  **One scroll for the whole timeline while dragging** (`LaneAutoScroll`, `LaneScrollFinder` finds the lanes' `UIScrollView`): the finger within the edge zone of the lanes viewport scrolls them vertically
  (speed by `LaneAutoScrollTuning.targetSpeed`); lanes' scrolling is disabled during a move. Tests: `AudioMoveTests`, `AudioClipRowUITests` (move to a new track, auto-scroll measured by the audio row's y, since the dropped clip changes lanes).
  **Drop runway** (`audioDropRunwayHeight`): while an audio clip is lifted the lanes get one empty row at the end, so even when every lane fits there is room to scroll into and the insert line
  for "a new last track" is on screen (it used to sit under the toolbar). It exists only during the move; the drop removes it. No label on the line (user's choice).
  Horizontal auto-scroll while moving is not built. Feel on the iPhone not measured.
  **Audio clips trim and no empty lanes** (2026-10-17): a selected audio clip has the same frame and two trim handles as the others (`AudioClipView`;
  `AudioTrim` is the arithmetic, `TrimAudioClipCommand` the edit): the left handle moves the clip's start *and* the head of its footage (`trim.start`), the
  right one reveals more of the file up to its end (`V2AudioAsset.duration`); both stop at the neighbours on the track, snap and auto-scroll like the
  others; the waveform shows only the slice of the file the clip plays. A track with no clip left is removed (`DeleteAudioClipCommand`) and the timeline
  draws only tracks that have clips. Audio plays at normal speed (`AudioMixEngine` ignores `playbackRate`), so footage moves 1 ms per timeline ms.
  **Volume and Fade are one popup** (2026-10-17, `UI/Editor/VolumeSheet/VolumeSheet`, built like the Speed sheet: Reset / title / Done, sliders on top, two round buttons Volume / Fade under them to switch in place; opened by `VolumeSheet.Request` so the
  Volume tool opens the Volume side and the Fade tool the Fade side): **Volume** = one slider shown as a **multiplier**: **0 (silence) ... 1 (as recorded, the mark in the middle where the thumb opens) ... 10** - steps of 0.01 below 1 (0.91, 0.92 ...) and 0.1 from 1 up (1.1, 1.2 ... 10); the clip stores dB (`VolumeScale`: dB = 20 log10(multiplier), 10x = +20 dB, 0 stored as -60 dB = silence, `gainDb` absent = 0); **Fade** = Fade in and Fade out
  sliders, each 0.1 s steps up to **10 s and never longer than the clip** (`AudioFadeLimit`, `SetAudioClipFadeCommand`, equal-power curve). Live while it is open (the stage keeps playing); the whole session is one undo step. The engine plays a boost above 0 dB with an
  `AVAudioUnitEQ` (no bands, `globalGain`) after each player node, because a node's own volume stops at 1. Not done: the clip's waveform does not follow the gain or the fades; a boost can clip a loud file (no limiter, no cap by file peak).
  **Split on an audio clip** (2026-10-17, `SplitAudioClipCommand`): live only with the playhead strictly inside the selected clip; the second half is a new clip right after the first in the same track, playing on from where the first stops
  (`trim.start` += the first half's length), gain/pan kept on both, **Fade in stays on the first half and Fade out goes to the second** (each shortened to its new clip, `AudioFadeLimit`); the selection is cleared afterwards, like a picture clip's split.
  **Audio clip look** (2026-10-17, chosen in the Audio fade lab: "C Scaled + shade", two-tone, no badge): the body is a 10 % cyan wash over the whole clip with a 45 % area for what is still audible (`AudioFadeBodyShape`:
  the whole clip with no fade, curving down at the ends that fade), and the waveform is scaled column by column by the fade's gain; no outline, no volume badge. The gain is `AudioFadeEnvelope` - the same function the engine
  multiplies its volume by - so the picture is the loudness you hear.
  **Audio clips draw a peak waveform** (2026-10-17, `AudioPeakWaveform`, from the Design Lab): mirrored hairlines, one per point, cyan, the row's full height, gain 0.90. Data is `PeakWaveformCache` (about 200 loudness peaks per
  second of audio, mono 44.1 kHz, raw fractions of full scale; streamed decode, in memory + `Caches/PeakWaveformCache/*.peaks2`); height = `(peak / the file's loudest peak) ^ 0.6` x 0.90 - a percentile
  reference cut the loudest 0.5 % of a real iPhone recording to one height (2.7 % of its sounding columns were flat squares), the max alone left the wave tiny, so the curve lifts quiet parts (measured, `AudioPeakWaveform`); the old `WaveformCache` (600 values) now only feeds the strip of a video's embedded audio.
  Only the on-screen part of a clip is drawn (the range is widened to multiples of 256 pt so a scroll does not redraw it each frame); the picture follows `trim.start`, so a trim moves it with the footage.
  **Audio tool labels** (2026-10-16): with nothing selected the Audio row is four labels, `Extract · Music · Sound FX · Record`
  (`ToolOptionsPanel.AudioOptionsRow`, ids `audio-*`): Music = the file picker, Record = the recorder (the label turns red with the
  elapsed time), **Extract** (built 2026-10-16) opens the video picker (`EditorMediaPickerView`, `MediaPickerPurpose.extractAudio`, videos only); the picked video is read straight from the library
  (`PhotoLibrary.avAsset`, no copy), its audio is exported once to `extracted-<library id>.m4a` (`MediaImportService.extractAudio(from:cacheKey:)`, reused on repeat) and
  `AddAudioClipCommand` puts it on the audio lane at the playhead, the video's whole length (one undo step); a video with no sound track says "That video has no sound".
  `ExtractAudioUITests` needs videos in the simulator's library (`simctl addmedia`) and Photos access granted. **Record is a popup** (2026-10-18, `UI/Editor/RecorderSheet`: `RecorderSheet`, `RecorderWaveform`; the Recorder lab's design, then shrunk by the user: sheet 250 pt, record / play button 48 pt, Delete / Add 38 pt, no captions;
  the old inline record-and-turn-red label is gone): Record opens it; ready (red dot) -> recording (red square, running time with hundredths, red waveform scrolling in from the right, real levels from `AVAudioRecorder` metering,
  `AudioRecorderService.levels` 15/s, -50 dB = flat) -> stop = review (whole waveform, play head, Delete / Play / Add). Add hands the temp `.m4a` to the shell (`addRecording`: `MediaImportService.importAudio`, `AddAudioClipCommand`
  at the playhead, then the temp file is deleted); closing an unsaved take drops it; swiping down is blocked while recording; no mic access shows an Open Settings note (checked on open via `AVAudioApplication`). The take number
  ("Recording 3") is an `@AppStorage` counter only. **The simulator has no mic input: its waveform stays flat (levels at the floor)** - judge the moving wave on the iPhone. Tests: `RecorderUITests` (needs
  `xcrun simctl privacy booted grant microphone com.neonix.editor`; the denied note runs with `TEST_RUNNER_RECORDER_DENIED=1` after a `revoke`). Not done: record while the video plays (voice-over), rename, pausing a take.
  **Sound FX is built** (2026-10-18, `UI/Editor/SoundSheet`: `SoundSheet`, `SoundStore`, `SoundPreviewPlayer`; layout "B Waveform" of the Sound FX lab, **system look like the other popups** (accent colour for chips, ring, played wave and the +; the user tried black/white/grey first and asked to go back to the default 2026-10-18); the old
  placeholder list still lives under the hidden Effects tool): the Stickers' sheet (340 pt + large, category chips), a row per sound = round play button with a progress ring, the name over a mini waveform that
  fills while it plays (**real `peaks` from the manifest**, 48 bars, so the shape shows before the file is downloaded), the length and a round black **+** at the end (a check for ~1 s after; user 2026-10-18: nothing else in the row, so no category text and no cloud badge). Playing a sound downloads it into Caches (`SoundStore.localURL`); + copies it into `ImportedMedia` as `library-<api id>.m4a` (asset id `library-<id>`, `soundAssetIdPrefix`) and `AddAudioClipCommand` puts it on the audio lane at the playhead (a second
  track when it overlaps), the sheet stays open. (Lesson from the monochrome try: a filled shape in `Color.primary` renders see-through on a sheet's glass; use a plain colour such as `accentColor`.) `SoundStore.init` must stay
  cheap (the shell creates it as a `@State` default on every re-init); the disk work is in `bootstrap()`. Debug/UI tests: `SOUNDS_FIXTURE_DIR=<repo>/public/preview/sounds` makes the app read catalogue + files from that folder (no server;
  `SoundFXUITests`). Unit tests `SoundStoreTests`. The manifest carries `peaks` (`generate_sfx.py` -> `publish_sounds.mjs` -> `GET /v1/sounds`). Not built: search, favourites, recents, offline-only mode.
  **Starter sound library** (2026-10-17, not wired into the app yet): 20 synthesized effects in `public/preview/sounds/<category>/<id>.m4a` + `sounds.json` (transitions, ui, impacts, fun, game), made by
  `scripts/generate_sfx.py` (stdlib only, RMS -13 dB each, peak <= -1 dBFS; rerun to regenerate). Same flow as stickers: **published** to R2 `neonix-system-assets/soudeffects/` (the folder's spelling, `scripts/publish_sounds.mjs`:
  `manifest.json` + `<category>/<id>.m4a`) and served by `GET /v1/sounds` (`api/src/sounds`, categories + sounds with a 1 h presigned `url`, `durationMs`, `mimeType`). Not built yet: the app's Sound FX sheet (list, listen, "Use" = download + `AddAudioClipCommand`).
  With an audio clip selected the row is Volume + Delete as before.

## Design Lab

Account › Developer › **Design Lab** (`UI/DesignLab`) is a sandbox for trying UI on fake data before it goes into the
editor; each experiment is a self-contained screen. Both experiments use one pattern, chosen by the user: **round buttons
that pick the parameter + a Curves-style system sheet** (`.sheet`, title + Done, the ruler and the same round buttons
inside, stage stays live via `presentationBackgroundInteraction`; height set in the lab menu, `LabSheetHeight`):
*Transform controls* (`TransformLabView`: X, Y, Scale, Rotate, Opacity; drag/pinch/twist on the stage too) and *Adjust
controls* (`AdjustLabView`: 16 scalar controls, live photo, hold to compare; **Scroll** = one scrolling row vs **Groups** =
Light/Color/Detail tabs - still undecided). Inline panels and plain sliders were tried and dropped. A third experiment, *Filter picker* (`FilterLabView`, 16 fake filters, SwiftUI look
stand-ins, `LabFilter`), compares a 4-column grid sheet (A), the same with a pull-up detent (B) and one row of thumbnails (C), with the Intensity
as a ruler or a slider, shown only once a filter is picked: the ruler (~120 pt with its readout) leaves only one clipped grid row in a 340 pt sheet, the slider leaves a full row + a peeking one.
A fourth, *Keyframes & graphs* (`KeyframeLabView`, `LabEasing`; 2026-10-13, style not chosen yet), shows 3 keyframes on a moving layer with one graph (cubic-bezier) per segment and compares A Row of curve tiles (CapCut), B Grid+ (family chips + grid, pull-up detent) and C Big live curve (family + In/Out/In Out); all open the same full-screen two-handle `GraphEditorView`. Fake data only; no keyframe model in the editor yet. The *Text picker* (`TextLabView`) has a third layout, **C Docked** (2026-10-14): a panel that is not a `.sheet`. Measured on an iPhone 13 (`KeyboardBench`, head's y per frame, Debug): the system sheet's head dips 316 pt toward the screen bottom for ~0.4 s before the keyboard lifts it (and jumps 290 pt up on the way back); a panel that folds its content while the keyboard lifts it does the same (folding is instant, the lift is not); a panel that **ignores the keyboard** (set on its parent, not on itself) with content exactly as tall as the area the keyboard covers (`keyboardHeight - home inset`) keeps the head at the same y (418 pt) through focus and blur. Not in production yet.
An *Audio fade* lab (`AudioFadeLabView`, `LabFadeClip`; 2026-10-17, fake data) tries how a clip shows its fades: the equal-power envelope line (A), the waveform scaled along the fade (B), or both plus the faded part darkened (C), on a dark, light or **two-tone** clip body (two-tone, user 2026-10-17: the whole clip a 10 % cyan wash, a 45 % cyan area under the fade envelope so the body itself curves down at the faded ends), with a volume badge (CapCut's "1.1x"-style: "0.5x", "3x", "Mute", only when not 1x). Not in the editor yet - the user picks first.
A *Sound FX picker* lab (`SoundLabView`, `LabSound`; 2026-10-17, fake data, pretend playback and download, user picks first) compares A List (round play button with a progress ring + Use), B Waveform (same rows with a mini waveform that
fills while it plays) and C Grid (3-column tiles + a Use bar for the picked one) in the Stickers' sheet (340 pt + large, category chips); Use downloads once (cloud badge until then) and puts a clip at the playhead. Not in the editor yet.
A *Crop* lab (`CropLabView`, `LabCrop`, `LabCropAspect`; 2026-10-18, fake data, after CapCut's Resize screen, user picks first): one working frame (`CropStage`: drag a corner to resize with the opposite corner fixed, drag inside to move, an aspect locks the ratio,
Rotate straightens the picture -20...20 degrees with an auto-zoom so its corners never show, Flip mirrors) stored in the picture's own 0...1 space, in three layouts: A Full screen (CapCut: x / check, picture, scrubber, `RulerDial`, aspect tiles, Reset), B Sheet (the Transform / Adjust pattern: 300 pt sheet,
round buttons Aspect / Rotate / Flip, the picture re-fits above the sheet), C Photos (ruler under the picture, one Aspect menu + Flip). Aspects: Custom, 9:16, 16:9, 1:1, 4:3, 3:4, 2:1. The corner brackets have a dark underlay: plain white vanishes on the light stage. Not in the editor yet.
A *Mask* lab (`MaskLabView`; 2026-10-18, fake data, after CapCut's Mask, user picks first): four shapes - Horizontal (what is above a line), Mirror (a band), Circle, Rectangle - plus None and Invert, on a live photo (`MaskStage`: yellow outline, round handles to move / size (right = width,
top = height) / feather (the chevron under the shape, pulled out = softer) / round a rectangle's corners, a two-finger twist turns it; the picture is masked live through `MaskDraft.v2Mask` -> `MaskMatteView`, i.e. the real V2 path). Three layouts, all a sheet with the stage live above it: **A Icons below** (user 2026-10-18, replaced the CapCut-flow variant: like the Volume popup - parameter chips, then the ruler or slider on top, the round shape icons None / Horizontal / Mirror / Circle / Rectangle and Invert below),
B round buttons Shape / Position / Rotate / Size / Feather / Invert, C tiles on top with chips and a ruler or slider under them. In A and C the **two-way parameters (Position, Rotate) use Transform's ruler, the one-way ones (Size, Feather, Round) plain sliders**; B uses rulers throughout. **One ruler at a time**, a small switch picks the axis (X/Y, Width/Height): two rulers did not fit a sheet.
Not in the editor yet.
The *Chroma key* lab (`ChromaKeyLabView`, `LabChromaProcessor`; 2026-10-19) compares the existing-V2 single `feColorMatrix`, a composed V2 graph (`feColorMatrix` + `feComponentTransfer`), and a Core Image `CIColorCube` matte on a generated green-screen picture or imported video/image; staged videos in `Documents/ImportedMedia` are listed automatically. Device tests on iPhone 13 with `GreenScreen Raw footage.mp4` (1920x1080, 43 s, uneven lighting, shadows, subject) showed the Color Cube retained more subject detail than the V2 graph. Production uses atomic `feChromaKey` (`keyColor`, `similarity`, `smoothness`, `shadow`, `edgeCleanup`) as an option in the selected clip's Remove BG row; choosing it activates the default green key and opens its controls. The sheet follows the editor's light system controls and has a draggable stage loupe that samples the source at the playhead, a native color control, and Intensity / Shadow / Feather edge / Clean up edge sliders. The native renderer generates/caches a 32³ color cube, builds an alpha matte and composites the unchanged source over transparency. Design Lab's Color Cube candidate routes through this same primitive. Photo and video preview use the existing `FilterRenderer` path. The Swift Codable mirror and iOS runtime are updated here; the canonical TypeScript/schema package is not present in this checkout and needs the matching primitive definition before other runtimes can consume it. The 27 protocol/render/command/tool tests pass on iPhone 17 Simulator. The production UI test is added but Xcode's UI test session stalled before launching its runner; general timeline video export is not implemented in this app yet.
A *Recorder popup* lab (`RecorderLabView`; 2026-10-18, fake data, user's reference = iPhone Voice Memos, user picks first): a 340 pt sheet - name ("Recording N") and running time with hundredths, a red waveform scrolling in from the right
while it records (dots while idle), one big round button (red dot -> red square); stop turns the same sheet into a review (whole waveform red up to a play head, grey after; Delete, Play, Add), Add puts the take at the playhead and closes;
swiping the sheet away drops an unsaved take and is blocked while recording; a no-mic-access state with Open Settings. The real recorder (`AudioRecorderService`, `AVAudioRecorder`) has metering available for the live levels. Not in the editor yet.
An *Audio waveform* lab (`AudioWaveLabView`, `LabWaveform`; 2026-10-17, fake data) compares the timeline's old smooth curve (A), the sound-library **peak waveform** - one hairline per pixel column, as tall as the loudest
sample under it - as the upper half only (B) and mirrored (C). The user chose **C**, cyan, full row, 1 pt lines, 0 gap, gain 0.90: that is what standalone audio clips draw now (`AudioPeakWaveform`).
`UI/Components/RulerDial` is the real, reusable ruler (`RulerMapping.linear/logarithmic`, `ScrollView` momentum; ticks stand on a
baseline in three kinds of line - minor tick, major tick, centre mark (no fixed marker: the tick in the middle *becomes* the
centre mark, accent colour and a little taller than a major tick); all three are 1.5 pt wide (minor grey, major dark); a dot marks the neutral value; soft
rate-limited haptics via `RulerHaptics`; VoiceOver adjustable; editing ends once it settles). It is meant for the editor's
Transform and Adjust sheets in production.

## Rendering notes

- `PreviewCanvas` scales `composition.width/height` to its box (`GeometryReader` +
  `scaleEffect`); the editor Stage is a fixed square (`min(width, stageHeight)`) with the
  video at 90 %, so no aspect ratio affects the layout. Add `.allowsHitTesting(false)` to
  `PreviewCanvas` wherever it's embedded — it swallowed taps meant for the buttons above.
- Never decode media inline from a `body`: stills go through `BundledImageCache` /
  async `.task`. **Filmstrip belongs to the source video, not the clip**
  (`FilmstripGrid`, `VideoFrameCache`): tiles are 48 pt and anchored to *source* time 0, a
  clip is just a window (`trimStart` shifts the strip), so trim never slides, regenerates or
  blanks it. Base grid = one thumbnail/s for the whole video, generated once and shared by
  every clip of the asset (`baseThumbs`, ≤ 240, step grows for long videos); window-only
  detail (base step halved up to 5×) only when zoomed past it; a tile falls back to the
  nearest base frame, never blank. One generator per tier, capped at 288×288.
- **Core Image**: `.workingColorSpace: NSNull()` on **every** `CIContext` - the shared one and the Metal video view's own (otherwise
  matrices run in linear space and drift ~70/255; on video the untagged numbers were encoded to sRGB twice, a washed-out "veil": a dark sweater 58 -> 127 of 255, found 2026-10-18 when Remove BG hid the raw layer), but pass an explicit
  `CGColorSpaceCreateDeviceRGB()` to `createCGImage` — a colorspace-less `CGImage`
  silently won't draw, and raw-pixel unit tests can't see that; only a simulator
  screenshot with real content does.
- Glass buttons (`.glass`/`.glassProminent`) are iOS 26 only, behind `#available`;
  deployment target stays 17.0.

## Build, test, tooling

- **`NeonixEditor.xcodeproj` is generated by XcodeGen from `project.yml`** (repo root;
  never hand-edit the project). After adding/removing/renaming files under
  `ios-editor/Sources` or `Tests`, run `xcodegen generate --spec project.yml`
  (`brew install xcodegen`, or the release zip). `Package.swift` was deleted on purpose
  (Xcode GUI refuses a sibling `.iOSApplication` package); don't reintroduce `#if SWIFT_PACKAGE`.
- `project.yml` must keep `DEVELOPMENT_TEAM: 5BZL4WMZ53` + `CODE_SIGN_STYLE: Automatic`
  (regenerating otherwise wipes the team picked in Xcode) and `GENERATE_INFOPLIST_FILE:
  "YES"` on the main target (without it every `INFOPLIST_KEY_*`, incl. `UILaunchScreen`,
  is ignored — the simulator tolerates that, a real device letterboxes). When a symptom
  is device-only, `PlistBuddy -c Print` the built Info.plist instead of trusting the YAML.
- **Simulator pitfalls**: the Debug build keeps app code in `NeonixEditor.debug.dylib`
  (grep that, not the stub). `simctl terminate` + `launch` can reuse a warm process, so
  to verify a forced `@State` default do `simctl shutdown` + `boot` first. Install the
  newest build by mtime and check for duplicate `NeonixEditor-*` DerivedData folders.
- **`simctl` can't tap or drag.** `ios-editor/UITests` (XCUITest) is the only way to
  synthesize touches (`TimelineZoomUITests` does real pinches); `print` from the app
  under test doesn't reach `xcodebuild` — use `NSLog` + `simctl spawn … log show`.
  Unit tests: `xcodebuild … test -only-testing:NeonixEditorTests` (231 passing).
- No Node/pnpm in this sandbox: TS (`packages/motion-protocol`) can't be verified here.

## Key files

- `ARCHITECTURE.md` — architecture writeup and mobile-first roadmap.
- `PLAYBACK_PIPELINE.md` — playback measurement design, results and decisions.
- `packages/motion-protocol/README.md` — canonical Protocol V2 field reference.
- `ios-editor/Sources/AppModule` — `Protocol/`, `Runtime/`, `Playback/`, `EditorDocument/`,
  `UI/` (Editor - one folder per part: `Shell`, `BottomBar`, `Timeline`, `AdjustSheet`, `TransformSheet`, `Commands`, `Debug`; Home, Projects, Account); `ContentView` (fixture picker) is reachable
  only from Account › Developer.
