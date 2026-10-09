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
  curve in closed form (k≈2.0/s), retuned **by the user's feel on the device**: gain 3.5,
  friction ×0.7. No benchmark exists for these two numbers — don't "correct" them
  toward native. Unmeasured: the lift "kick" from gain, and video keeping up at that speed.
- **Timeline zoom**: pinch (`MagnifyGesture`, simultaneous with the scrub drag), playhead
  pinned to the panel centre. Limits set by the user: zoomed out ruler ticks 5 s apart,
  zoomed in 1 frame apart (`TimelineZoom`, 0.0096…1.44 px/ms at 30 fps). Ruler and
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
- **Layer transform**: exactly `translate/scale/rotate/skew/anchor/perspective`; no
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
  intensity field — partial strength = `feComposite` arithmetic) and `feVignette`
  (`CIVignette`). End users never see "LUT" (the tool is "Bộ lọc").
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
- **Tools** (`EditorTool`, panel = `ToolOptionsPanel`): Aspect ratio/Background (edit
  `composition`; layers are not re-anchored), Edit (select, split, delete, trim,
  "Extract audio"), Adjust, Curves, Text, Audio (+ sound effects, record). Selection
  is `EditorShellView.selectedLayerId` / `selectedAudioClipId`. Deferred: Bộ lọc picker +
  `.cube` import, Chú thích (needs AI), Lớp phủ/Nhãn dán (extra image layer + sticker
  library). Roadmap plan: `~/.claude/plans/twinkly-noodling-hearth.md`.
- **Adjust (Tuỳ chỉnh)**: `AdjustValues` (17 fields) → `SetAdjustCommand` compiles only
  the groups that moved off neutral into `EffectPresetKind` primitive chains under a stable
  filter id `adjust-<layerId>` (cleared when neutral). Session-only `adjustIntents`
  cache — reopening shows neutral sliders although the persisted filter is correct.
  `FilterRenderer` (Core Image) implements `feColorMatrix`, `feComponentTransfer`
  (identity/linear/5-point table), `feGaussianBlur`, `feComposite arithmetic` (k1 = 0),
  3×3 `feConvolveMatrix`, `feTurbulence` (white noise approximation), `feMerge`,
  `feVignette`. Clarity = blur + arithmetic composite. **Curves**: 5 draggable points at
  fixed x (`CurveGraphView`, `CurveEditorSheet`); `curvePoints` map 1:1 to `CIToneCurve`.
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

## Rendering notes

- `PreviewCanvas` scales `composition.width/height` to its box (`GeometryReader` +
  `scaleEffect`); the editor Stage is a fixed square (`min(width, stageHeight)`) with the
  video at 90 %, so no aspect ratio affects the layout. Add `.allowsHitTesting(false)` to
  `PreviewCanvas` wherever it's embedded — it swallowed taps meant for the buttons above.
- Never decode media inline from a `body`: stills go through `BundledImageCache` /
  async `.task`; filmstrip tiles are one batched `AVAssetImageGenerator` call per clip
  (progressive `AsyncStream`), capped at 320×320.
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
  `EditorNavigationUITests` still use the old Vietnamese "Huỷ" label (stale).
  Unit tests: `xcodebuild … test -only-testing:NeonixEditorTests` (105 passing).
- No Node/pnpm in this sandbox: TS (`packages/motion-protocol`) can't be verified here.

## Key files

- `ARCHITECTURE.md` — architecture writeup and mobile-first roadmap.
- `PLAYBACK_PIPELINE.md` — playback measurement design, results and decisions.
- `packages/motion-protocol/README.md` — canonical Protocol V2 field reference.
- `ios-editor/Sources/AppModule` — `Protocol/`, `Runtime/`, `Playback/`, `EditorDocument/`,
  `UI/` (Editor, Home, Projects, Account); `ContentView` (fixture picker) is reachable
  only from Account › Developer.
