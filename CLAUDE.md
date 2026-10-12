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
- **All in-app UI text is English** (conversation stays Vietnamese). Chrome uses system
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
  (`CITemperatureAndTint`) and `feUnsharpMask` (`CIUnsharpMask`) - all Swift-only like `feVignette`. **Rule: V2 stays
  atomic, Editor names are high level, and the runtime calls the matching CIFilter; a formula is hand-written only where
  Core Image has no filter.** End users never see "LUT" (the tool is "Bộ lọc").
- Unimplemented in the renderer (silent no-op, no diagnostic): `composite.blendMode`/
  `isolation`, `enabled`, per-type animatable paths (shape `cornerRadius`, path
  `morph`, image crop, video `trimStart/trimEnd/playbackRate`).

## Editor

- **Timeline lanes**: `V2Layer.order` identifies a *lane*, not a clip; position inside
  a lane comes from `timing.start`. Lanes are homogeneous by type; clips of one type
  that don't overlap in time may share a lane, else a new `order` (greedy interval
  packing, as `AddTextLayerCommand`/`AddAudioClipCommand` do). Audio has its own domain
  (`V2AudioDomain.tracks[].clips[]`), not `layers[]`.
  The main lane (first lane with a video clip) is **pinned under the ruler**; every other
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
- **Text tool**: add/edit goes through the real `compile(_:)` text pipeline
  (`AddTextLayerCommand`, `SetTextContentCommand`), never hand-built chunks. Fixed
  defaults (Helvetica 32, white, centred, no wrap, 3 s); no font/colour picker or
  repositioning yet.
- **Audio**: `AudioMixEngine` (`AVAudioEngine` + one node per active clip) plays only
  during Play, resyncs on every `play(atMs:)`, no sample-accurate master clock. **Never
  call `engine.start()` without a source** (it hung the test runner for 600 s). Import:
  `MediaImportService` (copies into `Documents/ImportedMedia`, mints `V2AudioAsset`;
  `bundledURL(filename:)` falls back to that folder). Sound effects are synthesized
  placeholders with stable ids (`sfx-*`); Extract exports the whole asset audio once to
  `extracted-<name>.m4a` and trims per clip; Record = `AVAudioRecorder` → same import
  path (needs `NSMicrophoneUsageDescription`, shows a hint when permission is denied).
  Original video audio isn't muted after Extract (inert today: samples have none).

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
- **Core Image**: `.workingColorSpace: NSNull()` on the shared `CIContext` (otherwise
  matrices run in linear space and drift ~70/255), but pass an explicit
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
