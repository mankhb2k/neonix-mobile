# CLAUDE.md

Working notes for Claude Code sessions in this repo. See `ARCHITECTURE.md`
for the full picture; this file is the short, load-bearing rule list.

## Momentum glide is retuned, by feel — `CoastTuning` (gain 3.5, friction ×0.7)

Changed 2026-10-09 at the user's request after a simulator-vs-iPhone log
comparison (`PLAYBACK_PIPELINE.md` § 9): the native `UIScrollView` curve was
already in use, but a real finger lifts at ~900 pt/s (a simulator mouse
flick ~3200 pt/s), so on the phone a flick glided only ~1.2 screens.
`Playback/MomentumDecay.swift`'s `CoastTuning` multiplies the lift speed by 3.5
(2 at first, then 4, settled the same day) and the decay constant by 0.7
(≈5.8 screens for a 900 pt/s flick). **These
two numbers were chosen by the user's feel on the device, not by a benchmark**
— there is no published figure for timeline glide distance; don't "correct"
them toward the native curve without asking. Known, unmeasured side effects:
gain 3.5 makes content jump to 3.5 times the finger's speed at lift, and the
video seeks must keep up with that content speed.

## Timeline zoom — pinch with two fingers, limits defined by what the ruler shows

Added 2026-10-09 at the user's request. `TimelineView.pxPerMs` is now `@State`
(0.2 px/ms default), changed by a `MagnifyGesture` that runs *simultaneously*
with the scrub `DragGesture`. The playhead is pinned to the panel's centre and
the content slides under it, so zooming anchors on the playhead for free.
**Limits (user-specified): fully zoomed out the ruler's minor ticks are 5 s
apart; fully zoomed in they are exactly one frame apart**, both at the same
48 pt minimum tick spacing → `TimelineZoom.minPxPerMs = 0.0096`,
`maxPxPerMs(fps:) = 1.44` at 30 fps (`UI/Editor/TimelineZoom.swift`, pure and
unit-tested, as is the ruler's tick ladder: 1/2/5 frames, then 0.5 s … 5 min;
labels switch to `mm:ss:ff` below one second). At full zoom-in the 31 s sample
is ~45 000 pt wide, so the ruler (`Canvas`) and the filmstrip only build a
*window* around the playhead (`TimelineZoom.visibleWindowMs`: ±1 viewport,
snapped to viewport-wide steps so it doesn't change per scrub tick), and
filmstrip thumbnails are fetched per window with a 150 ms debounce (a pinch
changes the tile count every frame). While two fingers are down the drag's
events are ignored and re-based afterwards, so a pinch can't scrub or jump.
The timeline exposes its scale as the accessibility value of the element
identified `timeline`; `UITests/TimelineZoomUITests` drives real `pinch`
gestures against it. Zoom also feeds the seek-tolerance experiment (H10 in
`PLAYBACK_PIPELINE.md`): content speed = finger speed × ms-per-pixel.

## Playback work is measurement-driven — read `PLAYBACK_PIPELINE.md` first

Added 2026-10-09, at the user's explicit request, after a long run of
patches (clock, hysteresis, proxy, Metal) made without any number saying
whether a patch hit the real bottleneck. **No change to the playback
pipeline without a measured number pointing at the stage being changed.**
`PLAYBACK_PIPELINE.md` has the stage diagram, per-stage contracts, the metric
catalogue, the T0–T7 test matrix, the symptom → stage table and the results/
decision logs — consult it to choose the next step, and append to it after each
run. The measurement layer is `Playback/PlaybackMetrics.swift` + the HUD
(`UI/Editor/PlaybackMetricsHUD.swift`, switched on in Account > Developer);
`scripts/playback_report.py` summarises a recorded CSV. Simulator numbers only
validate the tooling — baselines are taken on a real iPhone.

## Curves — a real draggable tone-curve graph, replacing the parametrized stand-in

Added 2026-10-09, right after the rest of the Tuỳ chỉnh slider list, at the
user's explicit request ("làm tiếp curves hãy dựng UI riêng" — build Curves
with its own dedicated UI). The earlier note's Highlights/Shadows/Whites/
Blacks sliders were always labeled a stand-in until a real curve editor
existed; this replaces them rather than keeping both (keeping both would
mean 2 different UIs silently fighting over the same compiled tone curve).

- **`EffectPresetKind.toneCurve`** changed from 4 named scalars
  (`blacks`/`shadows`/`highlights`/`whites`) to `points: [Double]` — the
  graph's own 5 output values, applied verbatim (no more deriving them from
  4 formulas). `AdjustValues.curvePoints: [Double] = [0, 0.25, 0.5, 0.75,
  1]` (the identity curve) replaced the 4 scalar fields outright.
- **`UI/Editor/CurveGraphView.swift`** (new) — exactly 5 draggable points at
  **fixed** x-positions (`0, 0.25, 0.5, 0.75, 1`), matching `FilterRenderer`
  's `CIToneCurve` mapping's own hard 5-point limit exactly — nothing to
  resample, the dragged value *is* what reaches Core Image. Only y (output
  level) is draggable; x never moves, so points can never cross/reorder,
  meaning `EffectPresetKind.toneCurve` needs no clamping/validation of its
  own (same "UI proposes only valid values" split every command here
  already uses). The curve itself is a Catmull-Rom→Bezier smooth spline
  through the 5 points — same technique as `TimelineView`'s own waveform
  curve, duplicated rather than shared since that one is `private` to a
  different file.
- **`CurveEditorSheet`** (same file) — Curves gets a real **dedicated
  sheet**, not a slider squeezed into the ~64pt-tall row every other Tuỳ
  chỉnh control lives in. A 160–280pt-square graph genuinely doesn't fit
  there; a tap-to-open sheet (with Reset + Done) was the natural answer
  once "build it a real UI" was the explicit ask. `onBegin`/`onEnd` pass
  straight through to `CurveGraphView`'s own per-handle `DragGesture` — one
  undo step per individual point drag, sheet or no sheet, same bracketing
  shape as every other Tuỳ chỉnh control.

Verified: `EditorCommandTests.swift` gained a test confirming a non-identity
`curvePoints` array compiles to exactly 1 `feComponentTransfer` primitive
carrying the array through unchanged. Full 79-test suite green (no test
referenced the old 4 scalar fields directly, so removing them broke
nothing). Simulator screenshot (forced `showingCurveEditor = true` +
`selectedLayerId`, same established method) confirms the sheet renders:
grid, diagonal identity line, 5 draggable handles, Reset/Done. Actually
dragging a handle needs a real device/simulator touch — `simctl` can't
synthesize drags, same standing limitation as every other gesture in this
app.

## Văn bản — "Thêm chữ", by reusing the real text-compile pipeline, not hand-built JSON

Added 2026-10-09. `EditorTool.text` existed (bottom-nav scope decided back
on 2026-10-07) but had zero wiring — tapping it only highlighted the icon,
same as every other still-placeholder tool. This is the first real
implementation: add a new text clip at the playhead, and edit an existing
one's content, both from one `TextField` in the tool's own options panel.

**The key design question was reuse, not new design**: a text layer's
`V2TextLayerPayload` is resolved, shaped output (`chunks`/`spans` with real
per-character origins) — CLAUDE.md's own "Text layout stays atomic" note
already establishes that only real Core Text shaping (`TextLayoutCompiler`)
can produce a valid one, so hand-building that JSON shape for a typed
string was never on the table. `ProjectsView.openEditorProject`'s "Trip to
Paris" demo text lane already proved the reusable path — wrap one
`EditorLayer(kind: "text", text: EditorTextLayer(...))` in a throwaway
`EditorDocument`, call the top-level `compile(_:)` (`EditorDocument/
PresetCompiler.swift:73`), lift the one resulting `V2Layer` back out. Both
new commands (`EditorCommand.swift`) do exactly that, nothing hand-rolled:

- **`AddTextLayerCommand`** — builds the one-layer document (fixed
  defaults: Helvetica 32pt white, centered, no wrap, 3000ms duration —
  there's no font/size/color picker UI yet, so nothing else to author),
  compiles it, then places the resulting layer's `order` using the exact
  same "reuse a lane that doesn't already overlap this time range, else
  open a new one" search `AddAudioClipCommand` already does for audio
  tracks — this is the first thing to actually implement the "lanes are
  homogeneous by type, pack if non-overlapping" rule from the "Timeline
  lanes" note for a non-audio lane type.
- **`SetTextContentCommand`** — re-runs the *same* compile step (a text
  edit can't just poke `.source.text` in place; `chunks` are resolved
  output, not live text) but only overwrites the existing `V2Layer`'s
  `payload` — `id`/`order`/`frame`/`transform`/`timing` all stay exactly as
  authored, so editing content never moves or resizes the clip. No-op
  (fail closed) if the layer isn't found or isn't actually `.text`.
- **`ToolOptionsPanel`'s new `.text` case** is one `TextField` that does
  double duty off `selectedLayer` (the same selection Chỉnh sửa's
  Tách/Tách tiếng/Xoá already act on — selecting a text clip in either tool
  works): empty + "Thêm chữ" button when nothing text-ish is selected,
  pre-filled with the clip's real current text (read back via
  `payload.source.text`) + "Xong" when a text layer is. `EditorShellView`
  generates the new layer's id itself (not inside the command) so it can
  `selectedLayerId = layerId` right after adding — typing again immediately
  edits the clip just created instead of silently adding a second one.
- Deliberately not done: no font/size/color/alignment picker (fixed
  defaults only), no drag-to-reposition for text (same gap as every other
  clip type — no position-editing UI exists anywhere yet), no multi-line
  authoring (`wrap: "none"` always).

Verified: `EditorCommandTests.swift` gained 5 tests — a real compile
happens (not a placeholder: asserts `chunks` is non-empty with real `x`
origins), the lane-packing search (new lane when overlapping, shared lane
when not), content-edit-preserves-position, and the no-op guards. Full
62-test suite green. Simulator screenshots (forced `selectedTool`/
`selectedLayerId`, same established method) confirm both panel states: the
empty "Nhập nội dung…" + disabled "Thêm chữ" button, and — selecting the
"Trip to Paris" demo text lane already seeded by `ProjectsView` — the field
pre-filled with its real text and a "Xong" button, confirming the
read-back-from-compiled-payload path actually works, not just the write
path.

## Tuỳ chỉnh — the full slider list (Sharpen, Clarity, Blur, Vignette, Noise, Tone Curve, White Balance, HSL)

Added 2026-10-09, right after the Core Image bridge + first 4 sliders
shipped, extending the same architecture to the rest of the list the user
originally asked about (confirmed atomic in that earlier discussion). Two
scope calls confirmed with the user first: (1) "Đồ thị" (a real draggable
curve-graph editor) is explicitly deferred — the 4 parametrized
Highlights/Shadows/Whites/Blacks sliders are this pass's stand-in, sharing
the same `feComponentTransfer` `table` mechanism a real curve editor would
eventually also use; (2) do the whole remaining list in one pass rather
than splitting it, since every item reuses the same `FilterRenderer`/
`EffectPresetKind`/`SetAdjustCommand` architecture already proven.

**One real Protocol V2 addition this pass, flagged explicitly (not silently
contradicting the earlier "no protocol change, ever" claim)**: `feVignette`
(`Protocol/V2Filter.swift`) — a 2nd deliberate non-SVG exception alongside
`feColorLUT`. A faithful SVG vignette needs a radial-gradient paint server
rendered through `feImage` then composited back, which this app's filter
graph has never plumbed (no paint server has ever reached `FilterRenderer`);
Core Image already has a purpose-built `CIVignette` filter taking exactly
`radius`/`intensity`, so adding one small, well-justified primitive case
(mirroring `feColorLUT`'s own precedent exactly) was the honest tradeoff
over fake-plumbing paint servers through for one slider.

**`EffectPresets.swift`** gained 5 new `EffectPresetKind` cases —
`whiteBalance` (Temperature/Tint, a `feColorMatrix` channel-bias
approximation, not true chromaticity math), `toneCurve` (Highlights/
Shadows/Whites/Blacks → one shared 5-point `feComponentTransfer` table),
`sharpen` (a standard Laplacian 3×3 `feConvolveMatrix`, weights sum to 1),
`clarity` (`feGaussianBlur` + `feComposite` `arithmetic` — the textbook
unsharp-mask local-contrast technique), `vignette` (straight to the one
`feVignette` primitive) — plus `lightness` added to `colorAdjust` (folds
into the same additive offset as `brightness`, no extra primitive) and
reusing `hueRotate` for the Hue slider (it already existed, just was never
exposed in the UI). `blur`/`noise` needed **no new preset** — both already
existed from the original effects-preset system, just never had a renderer
or a command path before now.

**`Runtime/FilterRenderer.swift`** gained real implementations for
`feGaussianBlur` (`CIGaussianBlur`, `.clampedToExtent()` before +
`.cropped(to:)` after — without the clamp, the blur samples transparent
past the image edge and bleeds a dark fringe in), `feComposite`
`arithmetic` (only the `k1 == 0` shape — no true per-pixel multiplicative
term — since that's the only shape anything compiles to; implemented as 2
`CIColorMatrix` scales + `CIAdditionCompositing`, not a custom kernel),
`feConvolveMatrix` (3×3 only, via `CIConvolution3X3`), `feTurbulence`
(approximated with `CIRandomGenerator` — white noise, not true Perlin/
fractal turbulence, documented as such, "close enough for film grain" is
the actual bar here), `feMerge` (`CISourceOverCompositing` chained in
painter's-model order), `feComponentTransfer`'s `table` case (via
`CIToneCurve`'s 5 fixed control points — an exact match only when r/g/b
share an identical 5-value table, which is all this app ever compiles;
other lengths/divergent channels fall through to identity, documented
gap), and `feVignette` (`CIVignette`, direct 1:1 param mapping).

**`SetAdjustCommand`/`AdjustValues`** — `AdjustValues` grew to 17 fields
across 5 groups (basics, HSL, white balance, tone curve, detail/effects).
The command only compiles a preset for a slider **group** that actually
moved off neutral — touching only Vignette compiles a 1-primitive filter,
not an 8-preset chain padded with identity stages for everything else.

**`ToolOptionsPanel`'s `AdjustOptionsRow`** is one long horizontal scroll
with `Divider()`s between groups — no new navigation chrome for ~17
sliders, simplest thing that works.

Verified: `FilterRendererTests.swift` gained 8 new tests — flat-field
invariance checks for blur/sharpen/clarity (a uniform-color image is its
own fixed point under all 3, which exercises the clamp/crop/kernel-sum
plumbing without needing a non-uniform reference image), identity and
flat-black tone-curve cases, a vignette-at-zero-intensity identity check,
and a noise-chain smoke test (output exists, correct size — `CIRandomGenerator`
is non-deterministic by design, so exact pixel assertions aren't
meaningful there). `EditorCommandTests.swift` gained a sparse-compilation
test confirming only-the-touched-group gets compiled. Full 78-test suite
green. Simulator screenshot (`AdjustValues(vignette: 2)` forced via the
established method) confirms `feVignette` actually darkens the frame edges
on real video, not just in the unit test's synthetic solid-color image.

## All in-app UI text is now English — conversation stays Vietnamese, the app doesn't

Changed 2026-10-09, at the user's explicit request, right before the next
"Tuỳ chỉnh" slider batch: every tool title, button label, placeholder, and
hint string that actually renders on screen is English now — "Chỉnh sửa" →
"Edit", "Âm thanh" → "Audio", "Huỷ"/"Xuất" → "Cancel"/"Export", "Thêm nhạc"
→ "Add Music", "Ghi âm" → "Record", the 4 slider labels ("Độ sáng" →
"Brightness", etc.), every hint sentence, the 5 named sound effects in
`SoundEffectCatalog.swift` ("Vút qua" → "Whoosh", etc.) — the full list is
in this commit's diff across `EditorTool.swift`, `ToolOptionsPanel.swift`,
`EditorShellView.swift`'s 2 nav buttons, and `SoundEffectCatalog.swift`.
The user will Vietnamese-subtitle the shipped app themselves later; this
session's own conversation and every doc comment/CLAUDE.md note stay
Vietnamese-mixed as before — only strings a `Text`/`Button`/`TextField`
actually draws changed. Confirmed via a full-codebase string inventory
(an Explore pass) that no Vietnamese string doubles as a switch/compare key
anywhere (every real identifier — `EditorTool`'s raw values,
`SoundEffectPreset.id`, layer `type` strings — was already English); this
was a pure cosmetic find-and-replace, zero logic touched. Build clean,
full 70-test suite still green, 2 simulator screenshots (Tuỳ chỉnh panel,
Âm thanh panel) confirm the rendered text is genuinely English end to end.

## Ghi âm — the 4th and last piece of the audio roadmap (Thêm nhạc, Hiệu ứng âm thanh, Trích xuất, Ghi âm)

Added 2026-10-09. Deliberately the smallest of the 4 — records to a temp
file via `AVAudioRecorder`, then hands that file to the *exact same*
`EditorShellView.addAudio(from:)`/`MediaImportService.importAudio(from:)`
path `AudioFilePicker`'s own pick result already uses. No new command, no
new asset-minting logic: from the moment recording stops, a mic recording
and a Files-app pick are identical.

- `project.yml` gained `INFOPLIST_KEY_NSMicrophoneUsageDescription` — the
  first usage-description key this app has ever needed (confirmed
  greenfield when Thêm nhạc was scoped: no camera/mic/photo-library
  permission precedent existed anywhere in this repo before Ghi âm).
- `Runtime/AudioRecorderService.swift` (new) — `@MainActor
  ObservableObject` wrapping `AVAudioRecorder` + `AVAudioSession`
  (`.playAndRecord`) + the iOS 17-native `AVAudioApplication
  .requestRecordPermission` (available exactly at this project's 17.0
  floor, not the older `AVAudioSession`-based permission API). Records to
  `FileManager.default.temporaryDirectory`, not
  `MediaImportService.importedMediaDirectory` — recording straight into the
  sandbox would mean either skipping `importAudio`'s copy step (a second,
  parallel describe-only code path) or copying a file that's already in
  the right place (wasted I/O); recording to a true temp location instead
  means `addAudio(from:)` treats it exactly like any other external pick,
  zero special-casing.
- `ToolOptionsPanel`'s `AudioOptionsRow` (Âm thanh tool, empty state) gained
  a second button next to "Thêm nhạc": "Ghi âm" (idle) → tap starts
  recording, button becomes a red "stop" showing live elapsed `mm:ss`; tap
  again stops and immediately imports + places the clip at the playhead,
  same as picking a file. **The one piece of error UI Ghi âm adds to this
  app's otherwise-uniform "fail closed, no-op" convention**: if the user
  denies mic permission, a visible "Cần quyền micro trong Cài đặt" hint
  appears — a totally silent failure felt genuinely user-hostile here
  (tapping record and having nothing happen, with no way to know why,
  unlike every other fail-closed case in this app which has no user-facing
  action that *looks* like it should do something).

**Not attempted this pass, stated plainly**: interruption handling (a phone
call arriving mid-recording), background recording, and waveform preview
while actively recording (the clip only gets a real waveform once imported,
via the existing `WaveformCache`, same as any other audio clip) — none of
these came up as required for a first working version, and AVAudioRecorder
without a delegate handles the common case (user starts, user stops) fine.

Verified: full 70-test suite still green (nothing here was meaningfully
unit-testable without a real microphone — same "needs the user's own ears/
hands" limitation this file already states for scrub feel and the audio
mixing engine). Simulator screenshot confirms the "Ghi âm" button renders
in the Âm thanh panel next to "Thêm nhạc"; actually recording and hearing
the result needs the user's own device (no mic in the Simulator, and
`simctl` can't synthesize the tap either way).

## Tuỳ chỉnh — the Core Image render bridge, proven with Brightness/Contrast/Saturation/Exposure

Added 2026-10-09, via Plan Mode, after the user asked whether Protocol V2's
JSON is atomic enough for a full grading tool (brightness, contrast,
saturation, exposure, sharpen, clarity, HSL, curves,
highlights/shadows/whites/blacks, temperature, tint, blur, vignette, noise)
— discussed before any code. Confirmed: `Protocol/V2Filter.swift` already
ports **all 17 standard SVG filter primitives** plus `feColorLUT`; every
item on that list maps onto an existing primitive, no Protocol V2 change
needed, now or ever for this list. The real gap was the **renderer**:
nothing in this app ever read `layer.filter`, and no `CIFilter` rendering
existed anywhere except one `CIContext` in `VideoFrameServer.swift` used
only to convert a decoded pixel buffer to `CGImage`. This builds that
bridge and proves it with exactly 4 sliders (confirmed: "độ chói" =
Exposure, not Vibrance; HSL scoped to global, not Lightroom-style
per-hue-band — both would need baking into a `feColorLUT`, deferred). The
rest of the list becomes incremental additions to the same bridge, not new
architecture.

**`EffectPresets.swift`'s `EffectPresetKind.colorAdjust` already compiled
brightness/contrast/saturation into the right primitive chain** — built
during the original 8-tool scoping pass specifically because it's "atomic
today, no protocol change needed," just never wired to a command or a
renderer until now. Gained one more parameter, `exposure` (EV-stop gain,
its own `feComponentTransfer` `linear(slope: pow(2, exposure))` stage,
separate from the brightness/contrast `tone` stage so each slider's math
stays simple to read).

**`Runtime/FilterRenderer.swift` (new)** — walks a `V2Filter.primitives`
chain as a real `CIImage` pipeline (named `in`/`result` wiring, just like a
browser evaluating an SVG `<filter>`). V1 implements exactly 2 primitive
types — `feColorMatrix` (`matrix`/`saturate`/`hueRotate`, the literal W3C
Filter Effects formulas) and `feComponentTransfer` (`identity`/`linear`,
which maps exactly onto `CIColorMatrix`'s diagonal+bias, no custom kernel
needed) — everything else passes its input through unchanged rather than
crashing, written as one `switch` so `feGaussianBlur`/`feTurbulence`/
`feConvolveMatrix`/etc. are additive later, not a rewrite.

**Two real Core Image gotchas found building this, both confirmed on
device/simulator, not guessed:**
- **Color management silently breaks the W3C formulas.** Left on, Core
  Image linearizes 8-bit sRGB values before running the matrix math and
  re-encodes after — a `saturate(0)` test case came back off by ~70 of 255,
  not rounding-level drift. Fixed with `.workingColorSpace: NSNull()` on
  the shared `CIContext`, confirmed via `FilterRendererTests`' real
  rendered-pixel assertions.
- **A `CGImage` with no embedded color space won't draw.** The first fix
  also set `.outputColorSpace: NSNull()`, which made every unit test pass
  (they read raw bytes via `CGContext`, which doesn't care) but blanked the
  real Stage the instant any filter touched a video layer — confirmed by
  screenshotting with no filter applied (renders fine) vs. with one applied
  (solid background, no video at all). `Image(decorative:)` silently
  refuses to draw a colorspace-less `CGImage`; raw pixel reads don't hit
  that path, so the gap was invisible to tests alone. Fixed by keeping
  `.workingColorSpace: NSNull()` (for correct math) but passing an explicit
  `CGColorSpaceCreateDeviceRGB()` to `createCGImage(_:from:format:
  colorSpace:)` per call instead of nulling the context's own output space.
  **Lesson for next time a Core Image output "disappears" on the real
  Stage but tests stay green**: raw-byte pixel tests can't catch a
  SwiftUI-can't-draw-this-image class of bug — a real simulator screenshot
  with real decoded content is the only thing that did here.

**`PreviewCanvas.swift`** threads `filters: [V2Filter]` through
`content`→`LayerNodeView`→`LayerContentView`, resolving `node.layer.filter`
once per node. New `FilteredImageView` (used by both the `"image"` case and
`VideoFrameView`) resolves via `FilterRenderer` asynchronously (`.task(id:)`
keyed on `sourceKey` — `"<assetId>-<atSeconds>"` for video, the filename
for a static image — plus a JSON snapshot of the filter's current values;
generic, so any future filter shape needs zero changes here), caching the
last successful result and falling back to the unfiltered source meanwhile
— same "never block `body`, never show nothing" discipline as
`VideoFrameView`'s own `lastShown`. **Stated V1 limitation**: a video
layer's filter only actually applies while `refinesStills` (playhead at
rest) — a graded clip shows correctly paused/scrubbed-to-rest, not yet
during active Play. Baking it into `VideoFrameServer`'s own per-asset decode
cache would be wrong anyway (two clips could share one asset with
different grades); a fresh Core Image render every ~16ms during Play risks
never finishing before the next frame cancels it. A real, separate
follow-up, stated plainly, not silently skipped.

**`EditorCommand.swift`** gained `AdjustValues` (4 doubles, neutral at
`brightness:0, contrast:1, saturation:1, exposure:0`) and
`SetAdjustCommand` — writes a **stable** filter id (`"adjust-<layerId>"`)
so repeated slider drags replace the same `project.filters[]` entry instead
of accumulating one per tick, and clears `layer.filter` entirely when all 4
values are neutral (no dead-weight identity filter on an untouched clip).
`EditorShellView` keeps a session-only `adjustIntents: [String:
AdjustValues]` cache (never persisted to `project`) — a compiled
`V2Filter` has no cheap way to read brightness/contrast/saturation/exposure
back out of it (same two-tier intent-vs-resolved split as
`EditorTextLayoutIntent`), so without this cache, nudging only the Contrast
slider after reselecting a clip would silently discard a previously-set
Brightness value. **Known, stated limitation**: reopening the editor fresh
loses this cache, so a previously-graded clip's sliders show neutral even
though the real persisted filter (and the exported video) is still
correct — only the slider *position* misrepresents it until touched again.
`ToolOptionsPanel`'s new `.adjust` row updates live on every slider tick
(`onChange`, not commit-on-release like `AudioOptionsRow`'s volume slider —
a grading tool is useless without real-time feedback), while `Slider`'s own
`onEditingChanged` brackets exactly one undo step per drag, same shape as
`TimelineView`'s drag-to-trim handles.

Verified: `FilterRendererTests.swift` (new) — real `CIContext` renders, not
mocks, reading back actual pixels and comparing against hand-computed W3C
formula values (saturate/hueRotate/linear, plus a 2-primitive chained case
confirming `in`/`result` wiring actually feeds forward). `EditorCommandTests
.swift` gained `SetAdjustCommand` coverage (stable id reuse, neutral-clears,
no-op for unknown layer). Full 70-test suite green. Simulator: forced
`selectedTool = .adjust` + a real `SetAdjustCommand(saturation: 0, exposure:
0.8)` on the video layer, screenshotted — the Stage genuinely renders the
video desaturated and brightened, not a placeholder.

## Trích xuất — extract a video clip's audio onto the audio lane

Added 2026-10-09, the 3rd of the 4-part audio roadmap (Thêm nhạc, Hiệu ứng
âm thanh, **Trích xuất**, Ghi âm). Reuses every piece the earlier 2 passes
built — `AddAudioClipCommand`, `MediaImportService`'s "mint a `V2AudioAsset`
+ dedupe by stable id" pattern — same shape as Hiệu ứng âm thanh turning out
to be a one-tap variant of Thêm nhạc, not new infrastructure.

- `MediaImportService.extractAudio(from videoURL:)` (new) — exports the
  **whole** source video's audio track once via `AVAssetExportSession`
  (`AVAssetExportPresetAppleM4A`), cached under
  `importedMediaDirectory` keyed by the source filename (`"extracted-
  <name>.m4a"`), so extracting from a second clip of the same underlying
  asset — or re-extracting after deleting the first clip — reuses the
  export instead of redoing it. Uses the older completion-handler
  `exportAsynchronously` (wrapped in `withCheckedThrowingContinuation`), not
  the newer `async throws export()`, which needs a higher deployment target
  than this project's 17.0 floor.
- `AddAudioClipCommand` gained `trimStartMs`/`trimEndMs` (both default to
  the old behavior — `0`/`nil` — so Thêm nhạc/Hiệu ứng âm thanh's existing
  call sites needed no changes). Trích xuất is the one caller that sets
  them: since the exported file is the asset's *entire* audio, the placed
  clip needs its own `trim` to show only the slice matching the video
  layer's own `trimStart`/duration — `EditorShellView.extractAudio(fromLayerId:)`
  reads the selected video layer's `timing`/`trimStart` and passes them
  straight through.
- UI lives in `ToolOptionsPanel`'s existing `EditOptionsRow` (Chỉnh sửa),
  not a new tool — a new "Tách tiếng" button next to Tách/Xoá, shown only
  when the selected clip's `type == "video"` (there's no audio to pull out
  of an image/text/shape layer).
- **Deliberately not done**: muting/disabling the original video's own
  embedded audio after extraction (what CapCut does, so the same sound
  doesn't play twice). Skipped because it's currently inert either way —
  `AudioMixEngine` only ever plays a video's embedded audio when a real
  `V2VideoAudioDerivative` exists, and this app's own bundled sample videos
  have none (see the audio foundation note below) — not worth the extra
  field-wiring for a no-op today. Revisit once a real video-with-audio
  asset exists in this app.

Verified: new `MediaImportServiceTests.swift` — a synthesized (not
downloaded) source file stands in for "a video's audio track" since this
repo's own sample videos have no audio at all; confirms a real
`AVAssetExportSession` round-trip produces a file with the right duration,
and that a second call reuses the cached file/id rather than re-exporting.
`EditorCommandTests.swift` gained a test for `AddAudioClipCommand`'s new
trim fields. Full 57-test suite green. Simulator screenshot (forced
`selectedTool`/`selectedLayerId`, same established method) confirms "Tách
tiếng" renders next to Tách/Xoá when a video clip is selected.

## Hiệu ứng âm thanh is a sound-effect library, not a DSP effect — corrected same day

Corrected 2026-10-09, right after the note below shipped: that note's own
"Hiệu ứng âm thanh needs a new atomic Protocol V2 primitive... mapped onto
native `AVAudioUnitEQ`/`Reverb`/`Delay`/`TimePitch`" framing was wrong. The
user clarified: "hiệu ứng âm thanh chỉ là sound effect giống chọn audio
thôi" — it's a one-tap sound-effect library (pop/whoosh/ding/...), the same
action as Thêm nhạc, just picking from a bundled catalog instead of the
Files app. No new Protocol V2 primitive, no DSP engine, no design
discussion needed — it reuses every piece the audio foundation note already
built.

- `Resources/Media/SoundEffects/*.wav` (6 files) — synthesized placeholder
  SFX (a python `wave`-module script, not downloaded/licensed audio; no real
  sound pack exists in this repo yet). Swap in a real licensed pack later by
  replacing these files and `SoundEffectCatalog.swift`'s list; nothing else
  about the feature changes.
- `Protocol/SoundEffectCatalog.swift` (new) — `SoundEffectPreset` (id,
  title, filename, durationMs, icon) + `SoundEffectCatalog.presets`, and
  `asset(for:)` which mints a `V2AudioAsset` with a **stable id per preset**
  (`"sfx-pop"` etc., not a UUID like `MediaImportService.importAudio`'s) —
  this is what makes tapping the same effect twice reuse one
  `project.assets` entry instead of appending a duplicate.
- `AddAudioClipCommand` (`EditorCommand.swift`) gained exactly one line:
  skip appending `asset` if `project.assets` already has that id. Safe for
  Thêm nhạc too (every import mints a fresh UUID, so it never collides) —
  this is what makes it reusable for both.
- `ToolOptionsPanel` gained a `.effects` case/`SoundEffectsOptionsRow` — a
  horizontal icon row, same shape as `AspectRatioOptionsRow`; tapping calls
  `AddAudioClipCommand` at the playhead immediately, no selection state of
  its own (unlike Âm thanh — there's nothing to configure per-tap).

Verified: `EditorCommandTests.swift` gained
`testAddAudioClipCommandDoesNotDuplicateAnAssetAlreadyPresent`; full
54-test suite green; simulator screenshot (same forced-`selectedTool`
method as the note below) confirms the 6-effect panel renders under
"Hiệu ứng". Real audible confirmation of each synthesized effect needs the
user's own ears, same standing limitation as the rest of this audio work.

## Real audio playback, and "Thêm nhạc" — the first 2 of a 4-part audio roadmap

Added 2026-10-09, via Plan Mode (`~/.claude/plans/gleaming-leaping-lemon.md`),
at the user's request to build out Âm thanh: thêm nhạc, hiệu ứng âm thanh,
trích xuất, ghi âm. Recon found the real blocker before any of those could
be verifiable: **nothing in this app had ever played sound**, not a
standalone `V2AudioClip`, not a video's own embedded audio — `PreviewCanvas`/
`EditorPlaybackEngine`/`VideoFrameServer` only ever decode and draw
`CGImage` frames. This pass builds the playback foundation, then the first
user-facing feature on it (Thêm nhạc). Ghi âm/Trích xuất/Hiệu ứng âm thanh
are the next 3 passes — each becomes easier with the pieces below already
in place (import pipeline, mixing engine, audio-clip selection UI).

**`Playback/AudioMixEngine.swift` (new)** — an `AVAudioEngine` +
`AVAudioPlayerNode`-per-active-clip mixer, native AVFoundation only (no
third-party engine, per this file's own standing rule). Mirrors the
`VideoFrameServer`/`EditorPlaybackEngine` split: owns decode+mixing,
`EditorPlaybackEngine` stays the one clock. `update(project:)` rebuilds the
source list from two places every time the project changes: standalone
`V2AudioDomain` clips, and every video layer whose asset carries a
`V2VideoAudioDerivative` with `V2EmbeddedVideoAudio.enabled` (today's bundled
sample videos have no derivative, so that second path is real but untested
until a real video-with-audio asset exists). `play(atMs:)` fully stops and
reschedules every active node from scratch at the given time — no
`AVAudioPlayerNode.pause()`/resume bookkeeping — which doubles as the resync
point after a frame-decode stall. `advance(toMs:)` (called every
`playbackTick` while actually playing) starts newly-entered sources, stops
ended ones, and updates each node's volume for `gainDb` + its fade-in/out
curve. **Deliberate scope cut, stated plainly, not hidden**: audio only ever
plays during real Play — scrubbing/coasting stay silent — and there's no
sample-accurate master-clock sync between `DisplayLinkClock` and the audio
hardware clock; re-seeking on every `play()`/pause()/stall boundary bounds
drift to a few hundred ms at most, closing it further is the same "real
audio clock" step 3 work this file already flagged as future, not new scope.

**A real bug found and fixed before this could ship**: the first version
called `AVAudioEngine.start()` unconditionally inside `play(atMs:)`, even
with zero audio sources. This hung `EditorPlaybackEngineTests` for a full
600 seconds in the test runner (confirmed via `xcodebuild test`'s own
"Timed out after 600.0 seconds while waiting for a response from the
invoked process" + the specific `play()`/`pause()`-calling tests failing) —
the test process has no configured `AVAudioSession`, and touching real audio
hardware there blocks. Fixed by moving `engine.start()` into `startNode`,
lazily, only called once a node is actually about to play — a project/test
with no audio at all now never touches `AVAudioEngine` beyond constructing
it. Full 53-test suite (including this one) green after the fix.

**`EditorPlaybackEngine.swift`** owns one `AudioMixEngine`; `update(project:)`/
`play()`/`pause()`/`beginScrub()`/`playbackTick`'s stall branch and
successful-tick branch all call through to it (see the file for the exact
call sites) — the same "one clock tells every decoder what to do" shape
`VideoFrameServer` already had.

**`UI/PreviewCanvas.swift`'s `bundledURL(filename:)`** (previously
`Bundle.main` only) now falls back to
`MediaImportService.importedMediaDirectory` (`Documents/ImportedMedia`) when
the bundle lookup misses — every existing call site (`TimelineView`,
`EditorPlaybackEngine`, `VideoFrameServer`, `SharpFrameLoader`) picks this up
for free, same "one resolver, not one per call site" convention as
`VideoTimeMapping`/`WaveformCache`.

**Thêm nhạc**: `Runtime/MediaImportService.swift` (new) copies a picked file
into that sandbox directory and mints a `V2AudioAsset` (real duration via
`AVURLAsset.load(.duration)`) — the same shared import step Ghi âm/Trích
xuất will reuse later (recording/extraction both end by handing a local
file to this same step). `UI/Editor/AudioFilePicker.swift` (new) wraps
`UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy:
true)` — `asCopy: true` avoids the security-scoped-resource dance.
`EditorCommand.swift` gained `withAssets(_:)`/`withAudio(_:)` project
helpers (alongside the existing `withComposition`/`withLayers`) and 3
commands: `AddAudioClipCommand` (places the new clip at the playhead, on the
first track that doesn't already overlap that range, or a new track),
`DeleteAudioClipCommand`, `SetAudioClipVolumeCommand` (writes `gainDb`
verbatim, same "UI converts/validates, command just writes" split
`TrimClipCommand` already uses). `TimelineView`'s `AudioClipView` — which
previously took no tap gesture at all ("belongs to the later Âm thanh
phase") — is now selectable (`selectedAudioClipId`, parallel to
`selectedLayerId`, each clearing the other on selection) with the same
bounding-frame stroke visual selected video/text clips already use.
`ToolOptionsPanel` gained an `.audio` case/`AudioOptionsRow`: "Thêm nhạc" +
hint when nothing's selected, a volume slider + "Xoá" when a clip is.

**Deliberately out of scope this pass** (next increments, not forgotten):
dragging a standalone audio clip to reposition/trim it, per-clip fade UI,
multiple simultaneous tracks exposed beyond automatic first-non-overlapping-
track placement, ducking music under voice.
**Trích xuất, Hiệu ứng âm thanh, and Ghi âm all shipped in the days right
after this note — see the roadmap notes above this one for each.** Hiệu
ứng âm thanh turned out not to need a new primitive at all (it's a one-tap
sound-effect library, not a DSP processing effect); Trích xuất reused
`AddAudioClipCommand` as-is, just teaching it a `trimStartMs`/`trimEndMs`;
Ghi âm reused the exact same `addAudio(from:)` import path as Thêm nhạc,
just sourced from `AVAudioRecorder` instead of the Files app. The 4-part
audio roadmap this note opened with is now fully built.

Verified: `EditorCommandTests.swift` (5 new tests covering
`AddAudioClipCommand`'s track-placement search, `DeleteAudioClipCommand`,
`SetAudioClipVolumeCommand`) and new `AudioMixEngineTests.swift` (source
selection from `update(project:)`, including the muted-track/disabled-clip
skip cases; the fade/gain volume math) — full 53-test suite green. Simulator
screenshot (temporarily forcing `selectedTool = .audio` and the WindowGroup's
root, same established pattern this file uses elsewhere) confirms the
"Thêm nhạc" panel renders. Real audible confirmation (does sound actually
come out, is it in sync) needs the user's own ears on a real device — same
documented limitation this file already has for scrub/momentum feel.

## Latest playback plan result — native Stage for raw video, explicit Play only

Completed 2026-10-09 (sandbox → editor integration). `PlaybackSandboxView` is
the isolated baseline: one long-lived `AVPlayer`/`AVPlayerLayer`, serialized
latest-target seeks via `PlayerSeekCoordinator`, tolerant seeks while dragging,
and one exact settle seek on release. Scrubbing always pauses and never resumes
implicitly; the user must tap Play. The editor follows the same rule through
`EditorPlaybackEngine.beginScrub`/`endScrub`.

The real Stage now uses `StagePlayerSession` + `StagePlayerLayerView` for raw
video and `AVPlayerItemVideoOutput` → `CVPixelBuffer` → Core Image → Metal for
filtered video. Both paths avoid materializing a `CGImage` for video frames.
`VideoProxyService` lazily creates a preview-only 720p H.264 proxy with a
keyframe every 10 frames in `Caches/VideoProxies`; the original asset remains
the export source.
Native sessions are long-lived, reused across playhead updates, paused during
scrub/coast, and only started from an explicit `play()` call. The engine keeps
one seek in flight per player and replaces only its pending target, matching
Apple's serialized-seek guidance. Their native audio output is muted because
`AudioMixEngine` already plays the extracted video-audio derivative with the
timeline's trim/gain/fade rules; allowing both would produce duplicate audio.

Verified: device build and test compilation both succeed. Runtime smoothness,
frame pacing, and the no-autoplay interaction still need a physical iPhone
run; CoreSimulator is unavailable in this environment and no iPhone destination
is connected.

## Historical step — frame-server-only Play and scrub

Changed 2026-10-09 (step 2 of the engine plan below), at the user's
explicit request: "why do play and scroll use two different logics?"
Two paths existed only because `AVPlayer` plays sequentially well but can't
jump to an arbitrary time fast — so scrub used decoded frames and Play used
an `AVPlayerLayer`, and every switch between them was a hand-off that could
flash (black, gray, a blurry 640 px still) or briefly show a stale frame.
**This supersedes** the notes below titled "Play now uses a real `AVPlayer`
clock", the black-flash fix, and the scrub frame-cache design; they're kept
as history.

**Now**, for scrubbing, momentum *and* Play:
- `Playback/EditorPlaybackEngine.swift` is the only clock
  (`Playback/DisplayLinkClock.swift`, a `CADisplayLink` — vsync-aligned,
  replacing the `Task.sleep(16 ms)` loops). Every `currentTimeMs` change goes
  through `setTime(_:)`, which also asks the frame server to prefetch for
  every video clip covering the playhead (and clips starting within 1 s, so
  cuts don't wait). During Play, if the next frame isn't decoded the clock
  **holds** (max 2 s) like a buffering player instead of skipping — covered
  by `testPlaybackHoldsTheClockUntilFramesAreDecoded` via the
  `frameReadiness` test seam.
- `Playback/VideoFrameServer.swift` (replaces `Runtime/ScrubFrameCache.swift`)
  runs at most one `AVAssetReader` per asset, reading **forward
  continuously** from where it started, with backpressure (`DecodeGate`): it
  decodes up to 1 s ahead of the playhead (0.3 s when moving backward), then
  waits. So Play is one uninterrupted sequential decode — no seek per
  frame, no re-seek on Play. A new reader (one keyframe walk) only starts
  when the playhead jumps or moves backward past what's decoded. Frames are
  960 px long edge at the asset's native fps, tagged Rec.709 in the video
  composition so colors match the source (a suspected cause of the "dim
  gray/black" look before). Tunables + memory budget in `VideoFrameTuning`.
- `PreviewCanvas`'s `VideoFrameView` always draws the frame at the playhead
  from the server — the same view in every mode. `PreviewCanvas.refinesStills`
  (`engine.mode == .idle`) lets it swap in an exact full-quality frame
  (`SharpFrameLoader`) after 150 ms at rest.
- Deleted: `ScrubFrameCache.swift`, `VideoPlayerLayerView.swift`,
  `VideoContentView`, the `activePlayer` plumbing, preloaded players.

**Blank Stage after a jump, fixed the same day.** The user saw an empty
Stage (just the composition background + text) after scrolling. Logged
`VideoFrameServer` on the simulator: a jump evicts every frame outside the
keep window, and the new reader needs ≥1.8 s (keyframe walk on the
simulator) — up to 8 s at app launch, when it competes with the filmstrip
batch, cover image and sharp-frame requests for the decoder — before its
first frame. `VideoFrameView` drew `Color.clear` meanwhile. It now keeps the
last frame it drew (`LastShownFrame`) until a new one arrives. Benchmarked
in the iOS simulator itself (not just Mac): the composition decode path is
fine in isolation — first frame 81–114 ms from a keyframe, 72–118 fps;
Rec.709 tags cost nothing; `AVAssetReaderTrackOutput` + CI scaling was not
faster. Startup decoder contention is the remaining lever if launch-to-first-
frame matters on device.

Measured with a standalone decode script on the sample 1080×1920 clip
(Mac): sequential decode ~190 fps after a 231 ms open; starting mid-GOP at
6.5 s costs ~385 ms to the first frame (the 250-frame keyframe interval).
No audio is lost: neither sample video has an audio track and nothing played
the standalone audio clip; real audio must later follow `currentTimeMs`.
Build clean, 43/43 unit tests; no simulator run per the user's request.

## `EditorPlaybackEngine` owns the playhead — step 1 of 3, behavior-preserving

Added 2026-10-09 (`Playback/EditorPlaybackEngine.swift`). Before this,
`currentTimeMs` had **6 writers in 3 files** (software clock + `AVPlayer`
observer in `EditorShellView`, drag + momentum in `TimelineView`, the
fullscreen scrubber), and the scrub↔play hand-off was coordinated by loose
`@State` flags in views (`playbackSeekCompleted`, `lingeringPlayer`,
`sharpFrame`, `isSuspended`). The black/gray flashes were symptoms of that,
not isolated bugs.

**Now**: one `@MainActor @Observable` engine with a small state machine
(`idle / scrubbing / coasting / playing`). Only the engine writes
`currentTimeMs`. API: `play/pause/togglePlay`, `beginScrub` (idempotent per
gesture, pauses playback, cancels a coast), `scrub(deltaMs:)`/`scrub(toMs:)`,
`endScrub(velocityMsPerSecond:)` (slow → idle, fast → coast), `update(project:)`,
`preloadPlayers()`. It also owns the playback `AVPlayer`, its time observer,
the preloaded players and the momentum loop — all moved verbatim from
`EditorShellView`/`TimelineView`. `EditorShellView` now only sends commands
and reads (`currentTimeMs`/`isPlaying`/`maxDurationMs`/`activePlayerInfo` are
read-only forwards); every write to `project` goes through `setProject(_:)`
so the engine always sees the same layers the Stage renders.
`TimelineView` takes the engine instead of a `@Binding` and an `onScrub`
closure. The state machine is pure logic, so `EditorPlaybackEngineTests`
covers it (scrub clamping, idempotent `beginScrub`, coast/stop thresholds,
touch-during-coast, play/pause/end-of-timeline) — `simctl` can't synthesize
drags, so this is the only automated coverage scrub logic has.

**Deliberately unchanged in step 1**: the cached-still/player layering in
`PreviewCanvas` (`VideoContentView`/`ScrubFrameView`) and its `@State`
flags. **Step 2** moves the "last frame actually shown per video layer"
decision into the engine (`.live(player)` vs `.still`) and deletes those
flags — that's the real fix for the gray/black flicker after scrub→play, to
be designed from a reproduction log, not guessed. **Step 3** (later):
multiple simultaneous video clips, a real audio clock, Metal. `Runtime/`
(`sampleLayer`, caches) is untouched; there is no `RuntimeProjectV3` in
Swift yet — that name exists only in `packages/motion-protocol/README.md`.

## Scrubbing renders from a decoded frame cache, not an `AVPlayer` seek

Changed 2026-10-08, superseding `ScrubPlayerView` (deleted) and the two
notes below about tolerant/serialized seeks. The user tested on a real
iPhone: scrubbing forward felt fine, scrubbing backward stuttered. Root
cause measured, not guessed: both sample videos have a keyframe only every
**250 frames (~8.3 s)** (`AVAssetReader` + `kCMSampleAttachmentKey_NotSync`
probe). Every backward `seek` lands mid-GOP and forces a decode walk from
the previous keyframe; forward motion can mostly keep decoding onward.
No seek tolerance or seek serialization can remove that cost.

**Architecture now** (`currentTimeMs` is the only source of truth while
paused/scrubbing — no `AVPlayer` on that path at all):
- `Runtime/ScrubFrameCache.swift` — `ScrubFrameDecoder` decodes a whole
  time *window* sequentially with `AVAssetReaderVideoCompositionOutput`
  (rotated + downscaled to 640 px long edge on the GPU, 15 fps), so the
  keyframe walk is paid once per window instead of once per seek.
  `ScrubFrameCache` (`@Observable`, main actor) stores the frames, picks
  windows biased toward the direction of motion (2 s behind / 6 s ahead),
  starts the next window 1 s before the edge, and evicts frames more than
  6 s from the playhead. Tunables live in `ScrubFrameTuning` (memory is
  roughly 165 MB worst case per asset at current values).
- `PreviewCanvas.swift`'s `ScrubFrameView` reads the nearest cached frame
  **synchronously in `body`** — the same render pass as every other layer
  — and calls `prefetch` on each `atSeconds` change. After 150 ms of no
  movement it swaps in an exact full-quality frame (`SharpFrameLoader`,
  zero-tolerance `AVAssetImageGenerator`), because cached frames are
  downscaled and quantized to 15 fps.
- Play is unchanged: a real `AVPlayer` plays and drives `currentTimeMs`
  (media clock as master during playback is standard and intentional).

**Deliberately not done**: an MTKView/Metal compositor. `PreviewCanvas`
already evaluates every layer at the same `atMs`; the bottleneck was
decode, not compositing. Revisit only if compositing many layers becomes
the bottleneck. The real long-term fix for long-GOP footage is an
all-intra/short-GOP proxy made at import, which is also what pro NLEs do.

**Black flash on Play, fixed the same day**: the video branch used to *swap*
`ScrubFrameView` out for a fresh `AVPlayerLayer`, which draws black until
its player has decoded a frame. Now `VideoContentView` (`PreviewCanvas.swift`)
always keeps the still underneath and layers the player on top;
`VideoPlayerLayerView` stays `alpha = 0` until `isReadyForDisplay`.
`EditorShellView` only hands the player to the Stage after the session's
initial seek completes (`playbackSeekCompleted`), and ignores the player's
time observer until then — it was reporting the old position and yanking
`currentTimeMs` backward on Play. While playing, `ScrubFrameView` is
suspended (no background decode competing with the player). On pause the
paused player keeps showing (`lingeringPlayer`) until an exact still for the
same moment arrives, or the playhead moves.

**Source-time mapping fixed the same day**: every place that picked a frame
from the file used timeline-relative time and ignored
`V2VideoPayload.trimStart` — after a left trim (or for any clip not
starting at source 0, e.g. a split's 2nd half), Stage scrub, Stage play,
filmstrip tiles and the cover image all showed the wrong footage.
`Runtime/VideoTimeMapping.swift` is now the single timeline↔source
conversion (`trimStart` + elapsed × `playbackRate`) used by all four:
`ResolvedLayerFrame.sourceMs` (Stage scrub), `EditorShellView`'s player
seek/time observer, `FilmstripClipView.tileSeconds`, and the cover image.
Playback carries straight across split halves without a re-seek
(`isContinuous(with:)`). The filmstrip's batch key now includes
`trimStart`/rate so a left trim refetches tiles. Covered by
`VideoTimeMappingTests`. Editing commands (split/trim handles) still assume
`playbackRate == 1`; nothing authors a rate yet.

Build clean, unit tests green; no simulator pass this round per the user's
request (they test on their device).

## Scrub seeks are now serialized — fixes a real anti-pattern Apple's own docs warn against

Added 2026-10-08, after researching how CapCut-style apps achieve
real-time scrubbing (web research, not guessed — see this session's
sources: Apple's Technical Q&A QA1820 and the AVFoundation transport-
behavior docs). QA1820 states plainly: calling `AVPlayer.seek(to:)`
repeatedly in rapid succession **cancels each seek already in flight**,
producing "a lot of seeking and not a lot of displaying of the target
frames" — Apple's own fix is to use the completion-handler variant and
never issue a new seek until the previous one has actually finished,
keeping only the latest requested time pending in the meantime.

`ScrubPlayerView`'s `.onChange(of: atSeconds)` was doing exactly the
anti-pattern QA1820 warns against: calling `player.seek(to:...)` (no
completion handler) on every single tick during momentum/fast scrubbing,
with no regard for whether the previous seek had finished — very likely
the real remaining source of stutter even after velocity-aware tolerance
was already in place.

**Fixed**: every seek now goes through `requestSeek(_:to:toleranceSeconds:)`
instead of calling `player.seek` directly. If a seek is already running
(`isSeeking`), the request is just recorded as `pendingSeek` (overwriting
any earlier pending one) and returns immediately — no new seek fires.
`performSeek`'s own completion handler is the only place that ever starts
the *next* seek, using whatever the latest `pendingSeek` is by then. This
naturally collapses any burst of rapid-fire requests down to "the most
recent target, applied the instant the player is free" — never queuing or
replaying every intermediate position, matching the "only render the
newest frame" principle from the same research pass.

Deliberately not pursued (flagged as a separate, much larger undertaking
if simple serialization turns out insufficient): dropping `AVPlayerLayer`
entirely for scrubbing in favor of a dedicated Metal/`MTKView` frame-
decode pipeline, the way professional NLEs (Premiere/Final Cut/DaVinci)
actually do it. That's real, sound architecture for a mature editor, but
a multi-day rewrite affecting every layer type's render path, not a
targeted fix — only worth it if the cheap, documented QA1820 fix above
turns out not to be enough.

Build + unit test suite (`NeonixEditorTests`) green. Per the user's own
request this round, UI tests and a simulator screenshot pass were
deliberately skipped — they're testing the actual feel on their own real
device and will ask for verification when they want it.

## Play now uses a real `AVPlayer` clock — scrubbing's tolerant-seek path is explicitly untouched

Added 2026-10-08, after the user tested momentum scrolling on a real
iPhone and found a separate problem: pressing Play still didn't look
smooth. Root cause, confirmed by reading the code rather than guessed:
`EditorShellView` never actually set `PreviewCanvas.activePlayer` —
"Play" was just the same software `playbackTimer` tick advancing
`currentTimeMs` 60×/sec, which `ScrubPlayerView` turned into 60 tolerant
re-seeks per second. Tolerant seeking is the right tool for *scrubbing*
(see the earlier scrub-lag note) but is not, and was never going to be,
genuinely smooth decoded video — the user explicitly asked to set the
frame/scrub question aside entirely and "gỡ từng nút thắt" (untangle one
knot at a time): just make Play call the real iOS player.

**What changed, scoped narrowly to Play only:**
- `EditorShellView` gained `activeVideoLayer(atMs:)` (which video layer, if
  any, covers a given moment), `ensureRealPlayerPlaying(for:)`, and
  `releaseRealPlayer()`. While `isPlaying` and a video layer covers
  `currentTimeMs`, a real `AVPlayer` is created once per asset, seeked
  there, and actually `.play()`s — its own `addPeriodicTimeObserver`
  drives `currentTimeMs` from then on, not the software timer tick.
  `onReceive(playbackTimer)` now only does the old software-clock advance
  when *no* video covers the current moment (e.g. a text-only stretch),
  so the two clocks never fight over the same instant.
- Both `PreviewCanvas` call sites (windowed + fullscreen Stage) now pass
  a real `activePlayer: (assetId, AVPlayer)?` instead of always `nil` —
  `LayerContentView`'s existing `VideoPlayerLayerView` branch (which
  already existed in the code, just never actually reachable before this)
  is what finally renders the real decoded output during Play.
- Pausing, scrubbing, or reaching the end all route through
  `releaseRealPlayer()` (also wired to `.onChange(of: isPlaying)`), so
  nothing keeps decoding once Play isn't actually running.

**Deliberately out of scope, per the user's own framing**: `ScrubPlayerView`
(paused/scrubbing preview) is completely untouched — still tolerant-seek
based, still the thing the earlier scrub-lag/momentum notes describe.
Multi-clip seamless hand-off when playback crosses from one video clip
into a *different* one mid-lane is handled (the asset switch re-creates
the player), but was not stress-tested beyond the single-clip sample
projects this app ships today.

Verified on the simulator by temporarily forcing `isPlaying = true` in
`EditorShellView`'s `init` (same forced-default-then-revert pattern used
throughout this file) and screenshotting: the playhead/filmstrip had
genuinely advanced (to `00:06`) and the Pause icon was showing, confirming
real playback is actually driving the clock, not a single static render.
Full unit + UI test suite green. Real-device smoothness itself (the
actual thing being fixed) still needs the user's own eyes on a real
iPhone — a simulator screenshot can confirm the clock is advancing, not
how smooth the decoded motion looks frame to frame.

## Timeline momentum scrolling + velocity-aware scrub tolerance

Added 2026-10-08, after the user tested the scrub-lag fix above on a real
iPhone and flagged two more things: (1) releasing a fast drag on the
timeline just stopped dead — no inertia/coast, unlike CapCut's or any
native `UIScrollView`'s feel; (2) a theory that CapCut's smoothness comes
from direct Photos-library data access. (2) doesn't hold up — this app's
video files are already local bundled assets, exactly as "close" as a
Photos-library asset would be; the real technique (confirmed, not a
Photos internal) is widening seek tolerance while moving fast and
narrowing it once settled, which `ScrubPlayerView` already did in a fixed
(non-velocity-aware) way.

- **Momentum** (`TimelineView.swift`'s main scrub `DragGesture`): a real
  per-frame exponential-friction decay loop (`startMomentum`), not a
  single `withAnimation` to a computed end point — `currentTimeMs` must
  hold the true, instant-accurate value every frame (not just an
  interpolated rendering value) so a fresh touch mid-coast can read it as
  its own drag's correct starting point with no visible jump. Seeded from
  `DragGesture.Value.velocity` (iOS 17+), friction tuned so a fast flick
  coasts roughly half a second. A new touch (`onChanged`'s first tick)
  cancels any in-flight momentum task immediately.
- **Velocity-aware scrub tolerance** (`PreviewCanvas.swift`'s
  `ScrubPlayerView`): derives `atSeconds`'s own rate of change (content-
  seconds per wall-clock second — this view has no idea a drag gesture
  exists, only the resulting value stream) and widens the `AVPlayer` seek
  tolerance proportionally (capped at 0.3s) while moving fast, instead of
  always using the fixed `VideoFrameCache.scrubBucketMs` tolerance — lets
  `AVPlayer` reuse a nearby already-decoded frame during a fast coast
  rather than chasing a fresh precise seek every tick. The existing
  120ms-settle → zero-tolerance precise seek is unchanged.

Build + full unit/UI test suite green. Same caveat as the scrub-lag fix
above: `simctl` cannot synthesize a real drag/flick gesture, so the actual
felt smoothness of momentum + tolerance scaling needs a real device/
simulator touch test, not just a screenshot.

## `project.yml` now pins `DEVELOPMENT_TEAM` — regenerating used to silently wipe the user's manually-picked signing team

Found 2026-10-08, right after the user got real-device signing working
(Team "Manh Trieu", Team ID `5BZL4WMZ53`, confirmed paid Apple Developer
Program) by picking it manually in Xcode's Signing & Capabilities pane.
The very next `xcodegen generate --spec project.yml` this session ran (for
an unrelated reason) **reset it back to no team at all** — Xcode's next
build failed with *"Signing for 'NeonixEditor' requires a development
team"*. Root cause: `project.yml` never declared `DEVELOPMENT_TEAM`/
`CODE_SIGN_STYLE` at all, so every regenerated `project.pbxproj` has no
memory of whatever team was picked by hand in the GUI last — xcodegen is
the source of truth per this repo's own rule ("never hand-edit the
`.xcodeproj`"), so a setting that only lives in Xcode's UI state doesn't
survive the next `generate`.

Fixed by adding `CODE_SIGN_STYLE: Automatic` and `DEVELOPMENT_TEAM:
5BZL4WMZ53` directly to the `NeonixEditor` target's `settings.base` in
`project.yml` — now every regeneration keeps the real team wired up, no
manual re-picking needed. If this Team ID ever needs to change (different
Apple Developer account), update it here, not just in Xcode's GUI, or it
will be lost on the next `xcodegen generate` again.

## Real device showed letterboxed black bars (simulator didn't) — `GENERATE_INFOPLIST_FILE` was missing on the main target

Found 2026-10-08, running on a real iPhone for the first time this
project (everything up to this point had only ever been verified on the
Simulator). The user reported the app rendering inside a small centered
box with solid black letterboxing top and bottom on their physical
iPhone, while every simulator screenshot this whole project had ever
confirmed full-screen rendering with zero issues — the classic iOS
symptom of an app missing a proper Launch Screen, which makes SpringBoard
fall back to an old, un-scaled legacy canvas. Confirmed by actually
inspecting the built `.app`'s `Info.plist`
(`/usr/libexec/PlistBuddy -c "Print" NeonixEditor.app/Info.plist`), not
guessed: it had **no `UILaunchScreen` key at all**, despite `project.yml`
declaring `INFOPLIST_KEY_UILaunchScreen_Generation: "YES"` right there in
the target's settings.

**Root cause**: `INFOPLIST_KEY_*` build settings only get synthesized into
the compiled Info.plist when `GENERATE_INFOPLIST_FILE: "YES"` is also set
— without it, Xcode just silently ignores every `INFOPLIST_KEY_*` entry.
`project.yml`'s two test targets already had `GENERATE_INFOPLIST_FILE:
"YES"`; the main `NeonixEditor` target never did, even though it was the
one actually declaring `INFOPLIST_KEY_UILaunchScreen_Generation` and
`INFOPLIST_KEY_UISupportedInterfaceOrientations`. **The Simulator
tolerates a missing `UILaunchScreen` key far more leniently than a real
device's SpringBoard does** — this is why the gap went unnoticed through
every single simulator-based verification this project has ever done.

Fixed by adding `GENERATE_INFOPLIST_FILE: "YES"` next to the existing
`INFOPLIST_KEY_*` lines in `project.yml`'s `NeonixEditor` target,
regenerating via `xcodegen generate --spec project.yml`, and confirming
directly against the rebuilt `.app`'s `Info.plist` that `UILaunchScreen`
and `UISupportedInterfaceOrientations` are both now actually present.
Full unit + UI test suite re-run green after the fix. **Lesson for next
time a real-device-only symptom shows up**: `PlistBuddy -c "Print"` the
actual built Info.plist directly rather than trusting what `project.yml`
*declares* — a setting that has no effect is indistinguishable from a
correct one by reading the YAML alone.

## Scrubbing lag, fixed two different ways for two different parts of the Timeline

Reported 2026-10-08 as "kéo timeline, video chạy không real-time — kéo xong
mới chạy" (dragging the timeline, the video doesn't track in real time —
only starts moving once you stop dragging). Root-caused by actually
reading the code (`TimelineView`'s `DragGesture`, `PreviewCanvas`,
`VideoFrameCache`), not guessed: the gesture→`currentTimeMs` path itself
has zero throttling — the lag was entirely in how the **Stage preview**
and the **filmstrip thumbnails** each independently fetched video frames.
Researched how real editors (CapCut/Photos) solve this — not from
published internals (Photos is closed-source), but from the same public
AVFoundation APIs any of them would build on — and applied both:

- **Stage preview** (`PreviewCanvas.swift`'s `LayerContentView`) used to
  extract one still image per scrub bucket via `VideoFrameCache`'s
  `AVAssetImageGenerator.image(at:)` — async, but still a real decode per
  bucket, and buckets can advance faster than decodes complete while
  dragging fast, so the Stage kept showing a stale frame until the drag
  stopped and the last in-flight decode finally resolved. Replaced with
  `ScrubPlayerView` (new, same file): a persistent, paused `AVPlayer` per
  asset, re-seeked with a **tolerant** seek (`toleranceBefore/After`
  matching `VideoFrameCache.scrubBucketMs`) on every `atMs` change —
  cheap, reuses whatever's already buffered nearby, tracks the drag in
  real time. Once `atSeconds` stops changing for 120ms, one final
  zero-tolerance seek snaps to the exact frame. `VideoFrameCache` itself
  is untouched and still backs the filmstrip and `AssetDurationCache`.
- **Filmstrip thumbnails** (`FilmstripClipView`/`FilmstripTileView` in
  `TimelineView.swift`) used to have each tile fire its own independent
  `VideoFrameCache.frame(...)` request when it scrolled into view.
  Replaced with `VideoFrameCache.filmstripImages(assetId:url:times:)`, one
  `AVAssetImageGenerator.generateCGImagesAsynchronously(forTimes:)` batch
  call per clip for every tile it needs — the documented AVFoundation API
  for building a filmstrip, instead of N separate single-frame requests.
  **A real regression caught on the simulator before shipping this**: the
  first version awaited the *whole* batch before updating anything: logs
  showed all 34/34 tiles of a sample clip decoding successfully, correctly,
  in ~3.7s — but the UI showed nothing for that whole 3.7s, then populated
  all at once, instead of filling in progressively like the old per-tile
  version did. Fixed by changing `filmstripImages` to return an
  `AsyncStream<(index: Int, image: UIImage?)>` instead of a single
  collected dictionary, so `FilmstripClipView` fills `tileImages[index]`
  as each tile's own completion actually fires, keeping one batched
  request but the old progressive-fill feel.
  `isTileVisible`/`visibleRange` (the old per-tile visibility gate) were
  removed along with this — the whole clip's tile set is requested in one
  call regardless of scroll position now, a simplification that's fine for
  this app's current short sample clips; a very long clip would want this
  windowed to the visible range instead, not implemented yet (see
  `VideoFrameCache.filmstripImages`'s own doc comment).

Both changes verified on the simulator (screenshots showing the Stage
still renders correctly and the filmstrip fills in with real decoded
frames, not placeholders) and the full unit + UI test suite re-run green.
Real-time drag tracking itself (does the Stage visually keep up with a
fast finger drag) could not be verified this way — `simctl` cannot
synthesize a drag gesture (see this file's own UI-testing note below), so
confirming the actual scrub-smoothness improvement needs a real device/
simulator touch test, not just a static screenshot.

## Bottom nav tools: a phased roadmap exists, Phase 1 is now implemented

Planned 2026-10-08 (via Plan Mode, approved by the user), Phase 1 built the
same day. The 8-tool bottom nav (`EditorTool.swift`) has only ever
highlighted whichever icon was tapped — nothing opened, nothing edited the
project. The user asked for a plan to take these from placeholder to real
features; the full phased roadmap (what's already built vs. missing per
tool, 2 shared prerequisites, a 3rd prerequisite only 3 tools need, and the
recommended phase order with reasoning) is **not duplicated here** — see
the approved plan, still findable at
`~/.claude/plans/twinkly-noodling-hearth.md`, or re-derive it: the
reasoning won't have gone stale fast.

**Two real gaps the planning pass found, confirmed by reading the code,
not assumed**: nothing in `PreviewCanvas.swift` ever reads `layer.filter` —
Adjust/Effects/Bộ lọc already compile to *correct* Protocol V2 JSON
(`EffectPresetKind.colorAdjust`, `feColorLUT`, etc.) but have **zero
visual effect** on the Stage, a real prerequisite (a Core Image–based
filter bridge) gating 3 of the 8 tools specifically, not a vague "more work
needed." And there was no Command/undo system at all (zero matches for
`Command` in the whole module) despite this file's own long-standing
"Command pattern, not JSON Patch or CRDT" rule — Phase 1 is also where
that rule's first real implementation landed.

**Phase 1 — Tỷ lệ khung hình (aspect ratio) + Phông nền (background)**,
chosen first specifically because neither needs clip selection (they edit
`composition`, not a layer) and neither needed the filter bridge —
fastest path to a genuinely complete, visible feature end to end.
- `EditorCommand.swift`: `protocol EditorCommand { func apply(to
  project: V2Project) -> V2Project }`, plus `SetAspectRatioCommand`/
  `SetBackgroundColorCommand`. Confirmed with the user before writing
  this: changing aspect ratio **does not re-anchor or rescale any
  layer** — layers keep their authored absolute `frame`/`transform`
  values exactly, "like a crop," even if that means part of a layer now
  sits outside the new canvas bounds. No automatic reflow logic exists or
  is planned for this.
- `EditorHistory.swift`: undo/redo via **whole-document snapshots**, not
  per-command inverse operations — `V2Project` is a small, plain
  `Codable` value type today, so snapshotting the entire document on every
  edit is trivially correct and costs nothing meaningful yet. A
  generalized diffing/patch engine is explicitly deferred until document
  size or real collaboration actually requires it (same reasoning as this
  file's own "CRDT deferred" rule below) — don't build one preemptively
  when a tool's Command needs undo.
- `ToolOptionsPanel.swift`: a contextual panel shown above the bottom nav,
  gated by `EditorTool.hasOptionsPanel` (currently only `.aspectRatio`/
  `.background`) — every other tool still shows nothing, matching
  `EditorToolbarView`'s existing "tap only highlights" behavior exactly
  where a tool has no panel yet.
- `EditorShellView`'s previously-hardcoded-disabled undo/redo buttons are
  now wired for real (`history.canUndo`/`canRedo`), the first thing in
  this app that actually uses them.
- Verified: `Tests/AppModuleTests/EditorCommandTests.swift` (apply +
  undo/redo round-trips, matching `ProtocolCodableTests`' precedent of
  testing pure logic directly) plus the usual simulator screenshot check
  for both panels (forcing `selectedTool` briefly, same established
  method). **A real bug the screenshot caught**: the first aspect-ratio
  icon implementation fixed `width: 28` and scaled height from it
  (`28 * height/width`), which overflows badly for a portrait ratio like
  9:16 where height is the *larger* side — fixed with a proper aspect-fit
  helper that picks whichever dimension is actually larger as the
  constraint.

## Phase 2 of the bottom-nav roadmap — Chỉnh sửa (clip selection + split/delete)

Built 2026-10-08, right after Phase 1, per the same approved plan
(`~/.claude/plans/twinkly-noodling-hearth.md`). Reuses Phase 1's Command/
`ToolOptionsPanel` infra directly — no new shared mechanism needed, just
the two pieces this tool specifically requires: clip selection (nothing
in the Timeline was tappable before this) and two new commands.

- **`SplitClipCommand`/`DeleteClipCommand`** (`EditorCommand.swift`) plus
  a `V2Project.withLayers(_:)` helper alongside the existing
  `withComposition(_:)`. Split is a no-op (returns `project` unchanged) if
  `atMs` isn't strictly inside the target clip's own time range, or the
  layer isn't found — matches this app's "no ported validator, fail
  closed, not a crash" convention (see "Valid by construction" below)
  rather than needing its own error path for something the UI already
  prevents (the panel only enables Split when the playhead is actually
  inside the selected clip). **Splitting a video clip shifts the second
  half's `trimStart` forward by exactly the first half's duration** (same
  ms units as `timing`, not seconds — a real mistake made and caught
  writing this feature's own unit test, see below) so playback continues
  from the correct source position instead of restarting. Both halves
  keep the *original* layer's `order` unchanged, so they automatically
  stay in the same lane — directly validates that the "lanes = shared
  `order`, positioned by `timing.start`" model from the Timeline-lanes
  note below composes with Split for free, no extra code needed.
- **Selection state**: `EditorShellView`'s `@State selectedLayerId:
  String?`, threaded down to `TimelineView` as a `Binding` and on into
  `LaneRowView`/`FilmstripClipView`/`TimelineClipView`. Tap-to-select,
  tap-again-to-deselect. Only visual `layers[]` clips are selectable —
  the standalone audio lane is explicitly out of scope here (belongs to
  the later Âm thanh phase). Visual treatment (an extra white stroke
  overlay) and its two-part verification (NSLog confirming the state
  reaches the view + an oversized debug-colored stroke confirming the
  overlay mechanism itself renders, since the real 2.5pt white stroke is
  subtle against this demo clip's background) are in `ui-design-note.md`,
  not duplicated here.
- **A real bug caught by writing the unit test, not the simulator check**:
  the first `SplitClipCommand` test assumed `V2VideoPayload.trimStart` was
  in seconds (matching `AVFoundation`-style APIs elsewhere in this app)
  and asserted the shifted value as `2 + 3 = 5`. The actual result was
  `3002.0` — correct, once re-checked against `V2Timing`'s own ms units:
  `trimStart` is ms, same as `timing.start`/`duration` everywhere else in
  Protocol V2, and the command's own `+ firstDuration` (ms) was right all
  along. Fixed the test's fixture/assertion, not the command.
- Verified: `EditorCommandTests.swift` gained
  `testSplitClipCommandProducesTwoCorrectlyTimedLayersWithShiftedTrimStart`,
  `testSplitClipCommandIsNoOpWhenSplitPointIsOutsideClipRange`,
  `testDeleteClipCommandRemovesOnlyTheTargetedLayer` — full regression
  suite (`KeyframeSamplerTests`/`ProtocolCodableTests`/
  `EditorCommandTests`/`EditorNavigationUITests`) run and confirmed green
  after the test fix.

Drag-to-trim handles directly on a clip were deferred out of the phase
above, then built the same day once the user asked for them specifically
— see the next note.

## Drag-to-trim clip handles — the "future work" from the note above, built the same day

Added 2026-10-08. Scoped against a CapCut reference screenshot the user
sent: a selected clip grows 2 draggable white handles at its own left/
right edges instead of a border; an unselected clip is just a flat color
block, no border at all (for video **or** text/audio) — both explicit,
confirmed asks, not just a loose "match the picture."

**Confirmed with the user before building, via `AskUserQuestion`**: should
an *extend* drag (lengthening a clip) be capped at the clip's own current
timing range (simpler), or allowed to reveal more real source footage up
to the asset's actual duration (matches real CapCut, needs an async
duration lookup)? **Chose the real-CapCut behavior.** This is why
`AssetDurationCache` (`Runtime/`, new file) exists — an in-memory-only
(no disk tier; a single `AVURLAsset.load(.duration)` per video is cheap)
cache of a video asset's real total duration, keyed by filename, loaded
by `FilmstripClipView` via `.task(id: isSelected)` once a clip is
selected. Until it resolves, an extend-right drag just isn't clamped any
further than what's already known — fails closed to "don't extend yet,"
not a crash or a guess.

- **Border removal**: `FilmstripClipView`'s permanent blue stroke,
  `TimelineClipView`'s per-type stroke + 0.18-opacity fill, and the
  standalone-audio-lane `AudioClipView`'s cyan stroke are all gone.
  `TimelineClipView` now fills with the full type color (white icon/label
  for contrast, since a solid block needs a light foreground) instead of
  a translucent tint + outline — matches the reference screenshot's solid
  orange text block exactly.
- **`TrimClipCommand`** (`EditorCommand.swift`): writes `timing`/
  `trimStart`/`trimEnd` verbatim, zero clamping of its own — the drag
  gesture (`TimelineView`) is where the clamping/validation logic lives,
  same "no ported validator, make invalid states unconstructable at the
  call site" rule as every other Command here.
- **Undo collapses a whole drag gesture into one step**, not one per
  pixel: `EditorShellView` gained `beginTrim()`/`updateTrim(_:)`/
  `endTrim()`, a different shape from the normal `apply(_:)` (which
  records *and* applies together) specifically for this — `beginTrim()`
  snapshots the pre-drag project once, every `onChanged` tick calls
  `updateTrim(_:)` which applies directly without touching `history`, and
  `endTrim()` (on `onEnded`) is the one place that actually calls
  `history.record(_:)`, with the snapshot `beginTrim()` captured. Same
  "don't record every intermediate state" reasoning that already kept
  `TimelineView`'s own scrub-drag out of the undo stack — just applied
  here to a drag that *does* need exactly one undo step at the end.
- Full design rationale, the handle's own drag math (left handle moves
  the clip's start while its end stays fixed, walking `trimStart` down to
  a 0 floor for video; right handle moves the end, walking `trimEnd` up
  to `assetDurationMs`; both floor `newDuration` at 200ms and simply stop
  updating rather than overshoot), and the simulator verification are in
  `ui-design-note.md` — not duplicated here.
- Verified: `EditorCommandTests.swift` gained
  `testTrimClipCommandWritesTimingAndVideoTrimFieldsVerbatim`/
  `testTrimClipCommandIsNoOpForUnknownLayer` (covers the Command's own
  contract; the drag-math clamping itself lived in view code, not unit-
  tested directly this pass — **superseded by the next note**, which
  extracted exactly that logic and gave it real test coverage) — full
  regression suite run and confirmed green.

## Drag-to-trim v2 — lane-wide ripple reflow + a black-bordered handle

Added 2026-10-08, same day, after the user flagged the version above as
"doing the trim wrong" and asked for their intent to be restated before
more code. Full rationale and the worked examples that resolved 3
ambiguities (each confirmed via `AskUserQuestion`) are in
`ui-design-note.md` — this note is the architecture-level summary.

**The core fix**: the first version only ever touched the single dragged
clip. The corrected model treats a video/image lane as a "push lane" that
must never show a gap (confirmed with the user) — extending or shrinking
one clip cascades through *every* clip after it in the lane (not just the
immediate neighbor), each keeping its own `timing.duration`, only its
`timing.start` repositioning; the left handle uses the identical
mechanism in reverse. Text/overlay lanes (gaps allowed) keep the simpler
hard-stop-at-neighbor behavior unchanged.

- **`reflowLane(...)`/`isPushLaneType(_:)`/`previousClipEnd(...)`/
  `nextClipStart(...)`** (`TimelineView.swift`) — changed from `private`
  to internal specifically so `LaneReflowTests.swift` (new file) could
  reach them via `@testable import`, no gesture/view harness needed. 4
  tests cover forward cascade (extend + shrink, confirming the
  "pull closer" symmetry), backward cascade with genuine slack, and the
  one subtle case that took a worked example from the user to nail down:
  if cascading backward would push the lane's first clip below `0`, the
  deficit gets added back onto every computed position *including the
  dragged clip's own* — which is what makes a clip already packed tight
  against an earlier neighbor simply refuse to extend left at all (no
  slack to push into), while a clip with real room ahead of it still can.
- **`TrimClipCommand` gained `siblingStarts: [String: Double]`**
  (defaults to `[:]`, so every existing call site/test kept compiling
  unchanged) — the dragged clip's own layer updates exactly as before,
  plus every sibling in `siblingStarts` gets its `timing.start` rewritten
  (duration untouched), all in the same atomic command/undo step.
- **Handle visual**: `TrimHandleView` gained a black 1pt stroke around the
  white bar (plain white disappeared against bright video content) and
  grew slightly (4pt→6pt visible width, 70%→80% of row height) — matches
  the CapCut reference more closely.
- Verified: `LaneReflowTests.swift`'s 4 scenarios all matched hand-
  computed expected values exactly; full regression suite
  (`EditorCommandTests`/`KeyframeSamplerTests`/`LaneReflowTests`/
  `ProtocolCodableTests`/`EditorNavigationUITests`) run and confirmed
  green; the black-bordered handle confirmed on the simulator via the
  usual forced-`@State` + screenshot method.

## Timeline lanes: `order` identifies a *lane*, not a per-clip sequence number — no Protocol V2 change needed

Decided 2026-10-08, after a design discussion with the user before any code.
Starting point: `V2Layer.order` already existed (`Protocol/V2Layers.swift`)
and was already used exactly one way — `PreviewCanvas.swift`'s `LayerTree`
sorts siblings by it (`sorted { $0.order < $1.order }`) to decide render
stacking, ascending = bottom of the stack. The question was how the
Editor's future multi-clip timeline (main video track holding several
sequential clips, future overlay/text/sticker tracks) should assign and
interpret `order`.

**Rejected first proposal**: number every individual clip its own `order`
(main track clip1/clip2/clip3 = 0/1/2, overlay 1 = 3, overlay 2 = 4, ...).
Walked through why with the user: inserting a 4th main-track clip would
force renumbering every unrelated overlay layer that comes after it in the
sequence — a cascading-renumber smell, and it duplicates information
`timing.start` already carries (which clip comes first in a track is
already fully determined by when it starts).

**Decided model instead — three rules, confirmed one at a time:**

1. **`order` identifies a lane (timeline row), not a clip.** Every layer
   sharing one `order` value is the same row. Left-to-right position within
   a lane comes from each clip's own `timing.start`, never from `order` —
   moving a clip earlier/later in its lane is a plain `timing.start` edit
   (ordinary Command, no "renumber order" step needed), and adding/removing
   a clip from one lane never touches any other lane's `order`.
2. **Lanes are homogeneous by type** — a lane only ever holds clips of one
   `V2Layer.type` (all-video, or all-text, or all-image, never mixed). The
   user's own reasoning: matches CapCut's own timeline, where each visual
   "section" is one content category, and keeps the auto-lane-packing rule
   below simple (never has to compare a video clip's time range against a
   text clip's to decide shared-lane eligibility).
3. **One packing rule for every lane type, not just the main track** — any
   two clips of the same type that don't overlap in time (`timing.start`/
   `duration` ranges disjoint) *may* share a lane; if they'd overlap, the
   clip being placed needs a new lane (a new `order` value) instead. This
   directly answers the user's own open question ("text theo hàng" — how
   should several non-overlapping text captions lay out): generalizing what
   used to look like a main-track-only exception into one rule means text/
   overlay captions get exactly the same "pack if it fits" behavior video
   clips do, instead of forcing one full row per caption. The actual
   assignment algorithm (classic greedy interval packing — sort by
   `timing.start`, place each clip in the first open lane whose last clip
   ends before this one starts, else open a new lane) is Editor-tier/Command
   logic, not built yet (no multi-clip authoring commands exist yet at all);
   this note fixes the *data model* the eventual commands must honor.

**Explicitly out of scope for this decision, by the user's own request**:
audio. `V2AudioDomain.tracks[].clips[]` (`Protocol/V2Audio.swift`) already
solves "multiple clips per track" for audio in a completely separate
structure from `layers[]`/`order` — whether text/overlay should eventually
follow that same dedicated-domain shape instead of flat `layers[]` + lane
`order` was raised and **explicitly deferred**: the user wants a separate
follow-up discussion about audio specifically, since it's "an exception that
doesn't relate to this round's layer `order`" — don't fold audio into this
model without that follow-up conversation happening first.

**No Protocol V2 schema change** — `order`/`timing` already existed exactly
as described; this is purely a convention for how the Editor assigns them,
plus `TimelineView.swift`'s row-grouping logic (`LaneRowView` now renders
*one lane*, i.e. a `[V2Layer]`, not one row per `V2Layer`) — see
`ui-design-note.md` for the UI-side implementation notes and the
multi-clip-lane fixture this was verified against.

## LUT (3D color grade) is a new asset kind + one new, deliberately non-SVG filter primitive

Added 2026-10-07/08, Swift only so far (TS port not yet done — same
"prototype in Swift first" approach as every other protocol addition here).
Closes a gap flagged back when `EditorTool.swift`'s 7-tool v1 scope was
decided: "Bộ lọc" (LUT-style one-tap filter presets) was deferred because
neither existing filter primitive can express it — `feColorMatrix` is
linear-only, `feComponentTransfer` is per-channel independent with no
cross-channel coupling, and a real 3D LUT is an arbitrary, non-linear,
cross-channel-coupled color grade (a precomputed grid of input→output RGB
triples, not a formula — the same distinction as a Lightroom color *preset*
vs. its individual HSL sliders, confirmed with the user in conversation
before designing anything).

**Design, confirmed with the user one decision at a time before any code:**
1. **LUT data lives in a new `V2Asset` case, `.lut(V2LutAsset)`** — not
   inlined into the filter primitive. A realistic 33³ cube is ~36,000 RGB
   triples; inlining that into every filter using it would bloat the
   project JSON by hundreds of KB per LUT, the same reasoning that already
   keeps images/video/fonts as external `uri` references rather than
   base64 blobs. `V2LutAsset` (`Protocol/V2Types.swift`): `id`, `uri`,
   `dimension` (the cube's edge length, e.g. 17/33/64 — read from the
   file's own header, not duplicated/guessable from `uri`), `mimeType?`,
   `integrity?`.
2. **`uri` points to a standard `.cube` file (Adobe/ACES Cube LUT format)**,
   not a custom JSON array format — this was a real product requirement,
   not just a format preference: the user wants end users to be able to
   import their own `.cube` files (downloaded from colorists/online) and
   have them just work, no conversion step. Any renderer can write a
   `.cube` parser (plain text, well-specified), keeping Protocol V2's
   "same pixels from the same JSON everywhere" promise intact.
3. **New filter primitive `feColorLUT`** (`Protocol/V2Filter.swift`) —
   `V2FilterPrimitiveBase` + `assetId` (references the `.lut` asset), full
   stop. Not a real SVG primitive (SVG has no 3D LUT filter) — a
   deliberate, documented, named exception to "the 17 SVG primitives can
   build anything," the same kind of exception `rangeSelectors` already is
   in the text-layer schema. **No intensity/opacity field** — confirmed
   with the user as the better fit for the existing atomicity rule instead
   of adding a convenience field: `feColorLUT` always applies at full
   strength, and a partial-strength "Bộ lọc" is an Editor-tier concept that
   compiles to this primitive followed by an *already-existing*
   `feComposite` (`operator: "arithmetic"`, `k2`/`k3`) blending the LUT's
   `result` back against the original by whatever percentage the user
   picked — exactly the same "decompose into existing atoms instead of
   adding a field" move the in/out-preset-as-group-layer design already
   established.
4. **End users never see the word "LUT"** — in the Editor UI this is just
   "Bộ lọc" (the nav tool already scoped in `EditorTool.swift`), a
   thumbnail-driven one-tap preset. "LUT" is purely a Protocol V2/Editor-tier
   implementation term, same information-hiding precedent as
   `EffectPresets.swift`'s named presets hiding `V2FilterPrimitive` chains.

**Verification**: `Tests/AppModuleTests/ProtocolCodableTests.swift` (new
file — every existing test was `KeyframeSamplerTests`, which exercises
runtime sampling behavior; this is pure `Codable` wire-shape verification,
so it got its own file rather than being shoehorned in). Covers: a `.lut`
asset round-trips through JSON with `dimension` intact; a bare `feColorLUT`
primitive round-trips; and a realistic 2-primitive chain
(`feColorLUT` → `feComposite`, the intensity-blend shape an Editor-tier
preset would actually compile to) decodes both primitives in order with
the right wiring. No rendering exists yet — like `V2MotionPath` before its
Runtime resolver was built, this is Protocol-only so far; actually drawing
a LUT-graded frame (e.g. via Core Image's `CIColorCube`/
`CIColorCubeWithColorSpace`, the native iOS primitive this format was
chosen to map onto cleanly) is separate, not-yet-started work, as is the
"Bộ lọc" tool's own picker UI and the `.cube` import flow.

## A `simctl terminate` + `simctl launch` cycle can silently reuse a warm process — forcing `@State` defaults needs a full simulator reboot to verify reliably

Found 2026-10-07, while verifying a scrubbing-bar change in `EditorShellView`
by the established pattern in this file (temporarily force a `@State`
default, rebuild, install, launch, screenshot, revert). This time the
screenshot kept showing stale UI — wrong tab selected, old bar width — even
after confirming via `strings` on the compiled object file that the new
source was genuinely compiled, and even after a full `rm -rf` of
`DerivedData` and clean rebuild.

**Root cause, in two parts:**
1. This project's Debug build (for the iOS Simulator destination this
   session always uses) produces a `NeonixEditor.debug.dylib` alongside a
   thin `NeonixEditor` stub executable — Xcode's "debug executable as
   library" mechanism (built to support Previews' dynamic code injection).
   The stub's own entry point is literally `___debug_blank_executor_main`;
   it loads the real app code from the dylib at runtime. **`strings`/`grep`
   on the main `NeonixEditor` binary proves nothing** — the real Swift
   string literals/view code live in `NeonixEditor.debug.dylib`, a
   separate file in the same `.app` bundle. (Earlier verification passes
   in this session happened not to hit this, by coincidence of what was
   being checked.)
2. Separately, and more importantly: a plain `xcrun simctl terminate
   <bundle-id>` followed by `xcrun simctl launch <bundle-id>`, run in quick
   succession while iterating, does **not** reliably produce a true cold
   process start on this simulator/Xcode combination — a forced `@State`
   default (e.g. a tab `selection` or `isFullscreen` initial value) kept
   reading as its *old* value across several such cycles, even once the
   dylib itself was confirmed (via `strings`) to contain the new code.

**Fix: `xcrun simctl shutdown <udid>` then `xcrun simctl boot <udid>`** (a
full simulator reboot, not just an app terminate/relaunch) before trusting
any screenshot taken to verify a forced `@State` default. This reliably
produced a genuinely fresh process every time it was tried this session,
immediately resolving stale-looking screenshots with no further source
changes. Add this reboot step to the existing "temporarily force a
`@State` default to verify" workflow documented elsewhere in this file —
don't assume `terminate`+`launch` alone is equivalent to a cold start.

## `simctl` cannot synthesize real taps — a real `XCUITest` target caught a bug that build/screenshot verification never could

Added 2026-10-07, `ios-editor/UITests/` (`NeonixEditorUITests` target in
`project.yml`, `EditorNavigationUITests.swift`). Every verification method
used in this repo up to this point — `xcodebuild build`, `xcodebuild test`
(unit tests), `simctl io screenshot` — can confirm code compiles, sampling
logic is correct, and a screen *looks* right, but **none of them can press a
button**. `simctl` has no tap/touch injection at all (confirmed early in the
session). `XCUIApplication` (a real UI test target) is the one tool in this
toolchain that actually synthesizes a touch through Accessibility, the same
path a person's finger does.

This gap was real, not theoretical: a user report ("Huỷ doesn't return to
Folder") turned out to need this test to actually resolve, after several
rounds of plausible-but-wrong fixes based on reasoning and screenshots alone
(see `EditorShellView`'s and `PreviewCanvas`'s doc comments for the full
root-cause story). **The found bug: `PreviewCanvas`'s `GeometryReader` +
`.scaleEffect` combo silently absorbed real taps meant for `EditorShellView`'s
`Huỷ`/`Xuất` buttons sitting above it, for 2 of 3 sample compositions,
100% reproducibly — even with `.clipped()` already applied.** Fixed with
`.allowsHitTesting(false)` on `PreviewCanvas` wherever it's embedded (it has
no interactive content of its own, so this costs nothing and sidesteps
needing to pin down the exact mechanism `.clipped()` wasn't fully covering).

**Methodology that actually found it, after reasoning-based fixes failed
twice**: add `NSLog` (not `print` — a UI test's app-under-test runs as a
separate process, and `print()` output does not flow into `xcodebuild`'s own
log stream; `NSLog` goes through the unified logging system, retrievable via
`xcrun simctl spawn <udid> log show --predicate 'eventMessage CONTAINS
"..."' --last 10m`) at each suspected layer, then eliminate one variable at a
time under the *same* real UI test: not the Liquid Glass button style
(reproduced with `.buttonStyle(.glass)` removed entirely), not an async
video-decode race (reproduced with a 5s settle delay before the tap), not
`titlebarHeight`'s `PreferenceKey` oscillation (reproduced after that was
independently found and fixed — a real second bug, worth fixing on its own,
but not the cause of this one), not the test code itself (reproduced using
the exact passing test's own code, pointed at a different project) —
narrowed to `PreviewCanvas` specifically by swapping it for a plain `Color`
with the same frame chain, which made the tap work every time. Each of these
eliminations took a real, separate `xcodebuild test` run against the
simulator; there was no shortcut once reasoning alone stopped being reliable.

**Running these from the command line (reference, since each is a multi-step
flow a future session will need again)**:
```
xcodebuild -project NeonixEditor.xcodeproj -scheme NeonixEditor \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:NeonixEditorUITests
```
(`-only-testing:NeonixEditorUITests/EditorNavigationUITests/<methodName>`
to isolate one test — UI tests are slow, 15-20s+ each, launching the real
app and synthesizing real events, not instant like the unit tests).

## Regenerating `NeonixEditor.xcodeproj` via `xcodegen` can orphan DerivedData under a new hash — check for duplicates before trusting what the simulator shows

Found 2026-10-07: at one point there were **3** different
`NeonixEditor-<hash>` folders under `~/Library/Developer/Xcode/DerivedData/`
simultaneously, from 3 different days. Root cause: `xcodegen generate`
rewrites `project.pbxproj` with fresh internal object identifiers every
time it runs, and Xcode's own DerivedData hash is sensitive to that — so
a session that calls `xcodegen generate` repeatedly (this one does, every
time `Sources/AppModule` gains/loses a file) can leave old hash folders
behind, each holding a *stale* build of the app. **This matters beyond disk
space**: if Xcode's own GUI "Run" button happens to be using a different
(older) hash than whatever `xcodebuild`/`simctl` commands in this session
were just using, the person testing in Xcode sees stale behavior while
every verification in this session looks fine — this exact scenario is
what happened, and looked at first like a real dismiss/navigation bug
before being correctly diagnosed as stale cache. **If a rebuilt change
"isn't showing up" and the usual newest-mtime install trick (see the next
note) doesn't explain it, check for more than one `NeonixEditor-*` folder**
(`ls ~/Library/Developer/Xcode/DerivedData/ | grep -i neonix`) and delete
every one except the single fresh one before concluding anything else is
wrong. Also uninstall `com.neonix.editor` from every simulator the person
might be testing on, not just whichever one this session's own commands
target — a stale `.app` bundle can also linger per-simulator independently
of DerivedData. After a full wipe, the person should also do **Product >
Clean Build Folder (⇧⌘K) in Xcode itself** (and ideally quit/reopen Xcode)
before their next GUI Run, since this session can't reach into Xcode's own
in-memory module/build cache from the command line.

## `PreviewCanvas` never scaled to fit its container — it rendered `composition.width`/`height` as literal screen points

Found and fixed 2026-10-07, a real, previously-invisible bug. `PreviewCanvas`
used to be `ZStack { ... }.frame(width: composition.width, height:
composition.height).clipped()` — composition dimensions treated as literal
SwiftUI points, with zero scaling. Every external caller added
`.aspectRatio(ratio, contentMode: .fit)`, which looked like it was doing
the fitting, but **was always a no-op**: the ratio passed in was computed
from the same `composition.width`/`height` already baked into the fixed
internal frame, so there was nothing for `.aspectRatio` to adjust —
`.frame(width:height:)` with literal numbers reports that exact size
regardless of what any wrapping modifier proposes. This went unnoticed
because every fixture composition happened to use small values (240-320)
coincidentally close to a phone's own point width, and every caller sat
inside a `ScrollView`, where overflow just scrolled instead of visibly
colliding with anything. **`EditorShellView`'s fixed, non-scrolling 3-section
layout is what finally surfaced it**, once `ProjectsView`'s 3 sample
projects were given 3 different, more realistic composition sizes (9:16 =
360×640, 16:9 = 640×360, 1:1 = 480×480): the 640-wide ones rendered as a
literal 640pt-wide view, overflowing straight through the top nav bar and
down into the timeline.

**Fix: `PreviewCanvas.body` is now `GeometryReader { ... }`**, computing
`scale = min(geo.size.width / composition.width, geo.size.height /
composition.height)`, rendering the actual layer content at its native
`composition.width`/`height` frame (so every layer's absolute x/y/width/
height values stay correct), then `.scaleEffect(scale)` (a pure visual
transform, preserves relative layout) and a final `.frame(width:
geo.size.width, height: geo.size.height)` to fill whatever box the caller
gave it. Every external `.aspectRatio(...)` call site became redundant —
removed from `EditorShellView` (which now just hands it an explicit
`.frame(width:height:)` box); left alone in `EditorDemoView`/
`TextWrapDemoView` (harmless now that the inner content is genuinely
flexible, and those two still need it to turn a `ScrollView`'s unconstrained
proposed height into a bounded one).

**`EditorShellView`'s stage is a fixed square, not a rectangle that
inherits the project's own aspect ratio** — the other half of this fix,
decided in conversation. Stage's own allotted rectangle (`geo.size.height -
titlebarHeight - timelineHeight - 1`) is turned into a hard
`squareSide = min(geo.size.width, stageHeight)`, and the video renders at
`squareSide * 0.9` within it — so **any** project aspect ratio scales down
to fit the same square, leaving a consistent ~10% margin, and a project's
own shape can never again influence how much space Stage/Titlebar/Timeline
each get. Verified on the simulator across all 3 of `ProjectsView`'s sample
aspect ratios (9:16/16:9/1:1) — none overflow into the nav bar or timeline
anymore. `ProjectSample` now carries its own `compositionWidth`/
`compositionHeight` (9:16/16:9/1:1 across the 3 defaults) specifically to
keep exercising more than one shape at once, not because these particular
ratios are meaningful to "Trip to Paris" etc.

## iOS 26 Liquid Glass button styles are available — confirmed by reading the SDK, not guessed

Added 2026-10-07, `EditorShellView`'s top bar (`Huỷ`/`Xuất`). The simulator
here runs a build new enough (`iPhoneSimulator27.0.sdk`) to have
`SwiftUI.GlassButtonStyle`/`GlassProminentButtonStyle` — confirmed by
`grep`-ing the actual `.swiftinterface` under
`.../iPhoneSimulator27.0.sdk/System/Library/Frameworks/SwiftUI.framework/`
rather than assuming API names from memory. Both require `iOS 26.0, *`.
`project.yml`'s deployment target stays `17.0` (not bumped) — these are
applied behind `if #available(iOS 26.0, *) { .buttonStyle(.glass) } else {
<plain fallback> }`, so the app still builds/deploys down to 17.0 and only
upgrades the chrome on new-enough devices, rather than hard-requiring 26.

A real `ToolbarItem` button (e.g. `ProjectsView`'s `+`) already gets this
glass chrome "for free" on iOS 26 — the system auto-styles toolbar buttons
this way. A custom-laid-out bar like `EditorShellView`'s top row is *not* a
real toolbar, so it needs `.buttonStyle(.glass)`/`.glassProminent` applied
explicitly to get the same look. The effect is subtle on a plain
`Color(.systemBackground)` backdrop (a soft capsule + faint shadow, not a
dramatic frosted blur) — that's expected, not a sign it isn't working; it
reads much more clearly over a colorful/complex background, same reason
the toolbar `+` button also looks like a plain white circle over a mostly-
white screen.

## `DerivedData` can hold stale builds under a second hash — always install by newest mtime, not `find | head -1`

Discovered 2026-10-07 verifying the Editor shell redesign below: `find
/Users/macairm1/Library/Developer/Xcode/DerivedData/NeonixEditor-* ...`
matched **two** differently-hashed `NeonixEditor-<hash>` folders (one from
2026-10-06, stale), and `| head -1` picked whichever `find` happened to
list first — not the newest. The simulator kept showing the *old*
`ContentView` fixture picker after rebuilding/reinstalling `RootTabView`,
which looked exactly like a state-restoration bug but wasn't one; it was
genuinely installing yesterday's binary. Fixed by always picking the
newest by mtime (`stat -f "%m %N" ... | sort -rn | head -1`), and deleted
the stale folder. If a rebuilt change "isn't showing up" on the simulator
again, check `find ... -exec stat -f "%m %N" {} \; | sort -rn` for more
than one `NeonixEditor-*` folder before assuming anything else is wrong.

## The real Editor screen is being built as a shell first — `EditorShellView`, 7 bottom tools, all still placeholders

Started 2026-10-07. Scoped in conversation against a CapCut reference
screenshot: of CapCut's 11 bottom-nav tools (Chỉnh sửa/Âm thanh/Văn bản/
Hiệu ứng/Lớp phủ/Chú thích/Bộ lọc/Tuỳ chỉnh/Nhãn dán/Tỷ lệ khung hình/Phông
nền), **7 are in scope for v1** (`EditorTool.swift`): Chỉnh sửa, Văn bản,
Tuỳ chỉnh, Hiệu ứng, Âm thanh, Tỷ lệ khung hình, Phông nền. 4 are
deliberately deferred, each for a different reason, not just "later":
- **Bộ lọc** (LUT-style one-tap filter presets) — needs a *new* Protocol V2
  primitive. A LUT is an arbitrary 3D→3D color mapping (sampled grid +
  interpolation); it can't be expressed as a composition of the existing
  `feColorMatrix` (linear only) and `feComponentTransfer` (per-channel
  independent, no cross-channel coupling) primitives — see the
  conversation this was audited in if this needs re-deriving. **Tuỳ
  chỉnh** (manual brightness/contrast/saturation/hue sliders) is kept in
  its place for v1 since that *is* atomic today, no protocol change needed.
- **Chú thích** — CapCut's version is AI auto-caption; no AI backend exists.
- **Lớp phủ** / **Nhãn dán** — both need the same underlying mechanism (an
  extra image/video layer composited on top), but Nhãn dán also needs a
  sticker/emoji asset library this app doesn't have yet. Build them
  together, later, not twice.

**`EditorShellView.swift` (`UI/Editor/`) is the screen shell only.**
Redesigned again the same day, right after the version above: the user
asked for the scrubber bar, the "add content" row, and the 7-tool bottom
toolbar all removed, keeping **only** the stage and exactly one control row
underneath it — fullscreen (left), play/pause (center), undo/redo (right),
matching a reference screenshot. `EditorTool.swift` still documents the
7-tool v1 scope decided earlier (see above), but **nothing in
`EditorShellView` references it anymore** — where those tools resurface in
the UI (a future nav redesign) is a separate, not-yet-decided question, not
dropped work; don't delete `EditorTool.swift` over this, and don't
re-add the removed rows without the user asking again.

Fullscreen and undo/redo are disabled placeholders — no fullscreen
presentation mode and no command/undo stack exist yet (see "Command
pattern, not JSON Patch or CRDT" below: that's the intended mechanism for
undo, just not built).

**`TimelineView.swift` adds the timeline below the stage/controls row**,
same day. One horizontal track row per `project.layers[]` entry (excluding
`"group"` wrapper layers — they have no content of their own, only
children), positioned/sized by each layer's own `timing.start`/
`timing.duration` at a fixed `pxPerMs` scale, plus a draggable playhead
bound to `EditorShellView`'s own `currentTimeMs`. **No thumbnail
extraction** — each clip is a flat color/icon block keyed by `layer.type`
(blue/video, green/image, orange/text, purple/audio, pink/shape+path), not
a real filmstrip; that reuses `VideoFrameCache`'s still-frame extraction
when it's built, not in scope here. No pinch-to-zoom either — `pxPerMs` is
a fixed constant.

One SwiftUI layout bug worth remembering if this regresses: the first
version let the playhead `Rectangle` use `.frame(maxHeight: .infinity)`
inside a `ScrollView` with no outer height constraint, which made the
whole timeline section stretch to fill all remaining vertical space in the
parent `VStack` instead of hugging its own content height — confirmed
visually on the simulator (a single one-row timeline left ~1200pt of blank
white space below it). Fixed by computing an explicit `contentHeight`
(`rowHeight`/`rowSpacing` × track count) and applying it to the playhead,
the `ZStack`, and the `ScrollView` itself — never let a draggable/playhead
element size itself via `maxHeight: .infinity` inside a scroll container
again without an explicit height applied somewhere in the chain.

**Nav and chrome are the native iOS Photos editor's own light style**
(`Huỷ`/`Xong` text buttons, not icon buttons), using **system dynamic
colors** throughout (`Color(.systemBackground)`, `.secondarySystemBackground`,
`.label`/`.primary`/`.secondary`, `.systemGray4`) instead of the
hand-hardcoded `Color.black`/`.white` the first version of this shell used.
This isn't a "light theme" choice so much as *not picking a theme at all* —
dynamic system colors already render light or dark automatically based on
the user's own iOS appearance setting, which is exactly the "stays light
unless the user has chosen dark mode" behavior asked for. Don't reintroduce
hardcoded black/white here.

Opened from `ProjectsView` (Folder tab) via `.fullScreenCover(item:)`, not
a `NavigationLink` push — confirmed on the simulator that a pushed page
inside a `TabView`'s `NavigationStack` leaves that tab's own tab bar
visible underneath it, which a `fullScreenCover` doesn't. Every project row
opens the same placeholder composition today
(`EditorDemoView.makeDocument(media: .videoPortrait, ...)` compiled via
`compile(_:)`) — `ProjectSample` has no real document backing yet (see its
own doc comment), so there's nothing per-project to load.

## The app's real root UI is now `RootTabView` (Home/Folder/Account) — `ContentView`'s fixture picker is dev-only now

Changed 2026-10-07. Until now, `App.swift`'s `WindowGroup` launched
`ContentView` directly — the Editor-demo/Text-wrap fixture picker built
throughout this project for verifying Protocol V2/Runtime work on the
simulator. That picker was never meant to be the shipped product's actual
UI; it's a test harness. The user asked for the real top-level navigation
to be built next, deferring the actual Editor screen: a 3-tab shell —
**Home** (browse video templates), **Folder** (saved/created projects),
**Account** (profile/settings) — matching a reference screenshot's layout
(trend/carousel template rows) for Home's visual shape specifically, not
its branding.

`App.swift` now launches `RootTabView` (`UI/RootTabView.swift`), a plain
`TabView` wrapping `HomeView`/`ProjectsView`/`AccountView` (new
`UI/Home/`, `UI/Projects/`, `UI/Account/` folders), each in its own
`NavigationStack`. `ContentView` itself is untouched and still fully
functional — it's reachable only via **Account > Developer > "Test
fixtures (editor demo)"** now, not the app's own launch screen.

**All three new screens are placeholder/sample data on purpose** — there is
no template catalog, no project-library persistence, and no real
account/auth system yet; each view's own doc comment says so at the
field/struct that's fake (`TemplateSample`, `ProjectSample`, the hardcoded
profile row in `AccountView`). Don't mistake the gradients-as-thumbnails or
the hardcoded project list for real data wiring — they exist purely to
verify the layout holds together, per the user's own stated reasoning
("xây UI trước, backlog Runtime làm sau").

Verified on the simulator: built, installed, and screenshotted all three
tabs (temporarily driving `RootTabView`'s `selection` state since `simctl`
has no tap/gesture injection) before reverting that state back to `0`
(Home, the real default).

## Transform anchor is an offset from the layer's own center; transform/opacity keyframe coverage is now complete

Confirmed 2026-10-06 via explicit user choice: `V2Transform.anchor`'s
`(0,0,0)` means "pivot at the layer's own center" and a non-zero value is a
**pixel offset from that center** — not an absolute top-left-origin
coordinate. This was a live ambiguity (both readings are plausible from the
schema alone) resolved in favor of matching every existing fixture/preset's
already-correct center-pivot rendering, rather than retroactively breaking
all of them. `LayerNodeView.anchorPoint(_:)` in `PreviewCanvas.swift`
converts it to SwiftUI's `UnitPoint` via `0.5 + anchorX/frameWidth` (and the
`y`/frameHeight equivalent), which is where this reading actually lives in
code.

Every animatable transform/opacity path the real TS schema declares
(`COMMON_NUMBER_PATHS`, including `motion.*` — see below) is now implemented
end-to-end (`KeyframeSampler` reads the track, `ResolvedLayerFrame` carries
the sampled value, `PreviewCanvas` renders it): `opacity`,
`frame.width`/`frame.height`, `transform.translate.x/y/z`,
`transform.scale.x/y/z`, `transform.rotate.x/y/z`, `transform.skew.x/y`,
`transform.anchor.x/y/z`. Rendering notes for the newer ones:
- `scale.z` has **no own visual effect** on a flat 2D layer — correct,
  matches real CSS/After Effects (it only matters for 3D content that
  itself extends in z) — still sampled/stored for round-trip fidelity.
- `translate.z` is approximated as an apparent-scale multiplier
  (`perspective / (perspective - z)`, the same relation already used for
  `rotate.x`/`rotate.y`), applied only once `perspective` is authored —
  not a true z-depth compositing system.
- `skew.x`/`skew.y` render via `.transformEffect(_:)` with a manually-built
  shear `CGAffineTransform` (there's no dedicated `.skewEffect()`).

Still-known gaps, not in scope for this pass, not started without further
instruction: `composite.blendMode`/`composite.isolation` (no blend-mode
rendering at all), `enabled` (layer visibility toggle unread by the
renderer), and per-layer-type animatable paths (shape `cornerRadius`, path
`style`/`morph.progress`, image crop rect, video
`trimStart`/`trimEnd`/`playbackRate`). Swift has no ported validator (see
"Valid by construction" below), so a track on any unsupported path is a
silent no-op with zero diagnostic — worth keeping in mind before assuming a
track "doesn't do anything" is a renderer bug rather than an unimplemented
path.

## Motion path (`layer.motion` / CSS `offset-path`) is implemented, Runtime-side (not Editor-tier yet)

Implemented 2026-10-06, after initially being deferred. `V2MotionPath`
(`Protocol/V2MotionPath.swift`) was already a full shape port
(`offsetPath`/`offsetDistance`/`offsetRotate`/`offsetAnchor`, JSON
round-tripped fine), but nothing sampled or rendered it — a track on
`"motion.offsetDistance"` etc. was a silent no-op, and `PreviewCanvas` never
read `layer.motion` at all. Both gaps are closed now.

**Why this one runs at Runtime, not compiled once like text-on-path:**
`TextPathResolver` (text following a path) is an Editor-tier compile step —
it bakes per-character `dx`/`dy`/`rotate` once, because a document's text
never re-shapes itself later. Motion path can't use that shortcut:
`offsetDistance` is itself a *live animated number* (a keyframe track), so
"where is the layer on its path" has to be recomputed every sampled frame,
not resolved once ahead of time. `MotionPathResolver.swift` (`Runtime/`) is
that per-frame resolver; `KeyframeSampler.sampleLayer` calls it after
sampling `layer.motion`'s own three animatable sub-paths
(`motion.offsetDistance`, `motion.offsetRotate.angle`,
`motion.offsetAnchor.x/y` — `offsetRotate.mode` is a string enum, not in
`COMMON_NUMBER_PATHS`, so it's authored but never itself animated), storing
the result in `ResolvedLayerFrame.motionDx`/`motionDy`/`motionRotation`
(`0`/`0`/`0`, a no-op, for any layer without `motion`). `PreviewCanvas`
adds these on top of the ordinary `translateX/Y`/`rotateZ` — motion path
augments a layer's transform, it doesn't replace it.

**Shared arc-length machinery with text-on-path**, pulled out into
`Runtime/PathFlattening.swift` (`FlattenedPath`/`flattenPath(_:)`, moved out
of `TextPathResolver` so both resolvers use the identical "distance along a
path → point + tangent" math — not two parallel implementations that could
silently disagree on tessellation).

**New capability `TextPathResolver` didn't need: SVG elliptical arc
segments.** Text-on-path only ever used a hand-built circle (line
segments); `V2PathContour` can also carry real SVG arc segments (`rx`/`ry`/
`x-axis-rotation`/`large-arc-flag`/`sweep-flag`, SVG's endpoint
parameterization), and a generic motion path needs those to actually work,
not just lines/beziers. `MotionPathResolver.buildCGPath` / `.
arcToBezierSegments` implement the standard W3C SVG 1.1 Appendix F.6.5
endpoint→center conversion, splitting into ≤90° pieces each approximated by
a cubic bezier — the same technique every conformant SVG renderer uses for
path `A`/`a` commands, not a shortcut. Verified two ways: a direct geometry
test (two 180° arcs forming a circle of radius 50 — flattened circumference
matches `2πr` within 1 unit, and the point exactly halfway around lands
within 1 unit of the true antipodal point) and a full JSON-fixture test
through `sampleLayer` (catches any `V2PathSegment.arc` Codable/JSON-key
mismatch the programmatic test wouldn't). A third fixture (a line-segment
square) verifies the full per-frame pipeline end-to-end against exact hand
-computed arithmetic: offsetDistance track sampling, offsetAnchor
subtraction, and `offsetRotate: "auto"` picking up each edge's tangent angle
(0° along a horizontal edge, 90° along a vertical one). All three live in
`KeyframeSamplerTests.swift`. Also spot-checked visually on the simulator
(`EditorDemoView`'s "Object's own animation" toggle, temporarily given a
square motion path): the layer visibly displaced off its default centered
position, consistent with the sampled offset.

**Still Protocol V2-only, not an Editor-tier concept yet** — no compiler
step authors `layer.motion` from a named preset ("move along a circle"),
the way `PresetCompiler` does for in/out or effects. Building that authoring
layer (and reusing this same arc-length math for a `pathId`-reference
resolver against real project geometry, same reuse `TextPathResolver`'s own
doc comment already flagged as future work) is separate, not-yet-started
work.

## Named easing (Ease In/Out/In-Out) is an Editor-tier shorthand for literal cubic-bezier numbers

Implemented 2026-10-06. `V2Easing.cubicBezier(x1:y1:x2:y2:)` was already
fully atomic and already implemented in the Runtime (`cubicBezierEase` in
`KeyframeSampler.swift`) — nothing to add to Protocol V2 for this. What was
missing: a *named* shorthand ("Ease In", "Ease Out", "Ease In Out") so an
author doesn't have to type four bezier numbers by hand, and the compiler
wiring to actually apply any easing to preset keyframes at all (before this,
every in/out preset silently used linear — no easing was ever attached).

Same rule as every other named convenience in this file: the name
(`PresetBinding.easing: String?`, `"easeIn"`/`"easeOut"`/`"easeInOut"`) lives
only at the Editor tier; `PresetCompiler.resolveEasing(_:)` resolves it to
the literal CSS-standard curve (`ease-in` = `cubic-bezier(0.42,0,1,1)`,
`ease-out` = `cubic-bezier(0,0,0.58,1)`, `ease-in-out` =
`cubic-bezier(0.42,0,0.58,1)`) before anything becomes Protocol V2 JSON —
the JSON never contains the word "ease". The easing lands on the *first*
keyframe of each in/out pair, matching `interpolate()`'s existing
convention of reading a segment's easing off its starting keyframe.

Verified: built an "Easing" picker in `EditorDemoView` (Linear/Ease In/Ease
Out/Ease In Out, shared by in+out for this demo), read back
`project-v2.json` with Ease In Out selected — both the in-keyframe (`time:
0`) and the out-keyframe (`time: {anchor:"end", offsetMs:500}`) carry
`easing: {type:"cubicBezier", x1:0.42, y1:0, x2:0.58, y2:1}` exactly, the
second keyframe of each pair has none (correct — easing describes the
curve *leaving* a keyframe, not arriving at one).

## Group layers compose transform/opacity by real view nesting, not merged tracks

Locked in 2026-10-06. Protocol V2's `tracks[]` allows exactly one track per
`path`, so two independent animations that want the *same* property on the
*same* layer (e.g. an object's own custom keyframes on `transform.rotate.z`,
plus an in/out preset that also wants to animate something) cannot both
live in one flat keyframe list — concatenation (the trick that already
merges an in-preset and an out-preset onto one `opacity` track, since those
never overlap in time) only works when the two contributors are temporally
disjoint. A custom animation running the *whole* clip and a preset running
over *part* of it are not disjoint, and CapCut-style tools clearly do allow
both at once — so simple concatenation doesn't generalize to that case.

**Resolution: `PresetCompiler.compile(_:)` always wraps an object that has
an in/out preset in a synthetic, invisible parent `"group"` layer.** The
preset's tracks live on the wrapper (on *its own* `opacity`/`transform`);
the object becomes the wrapper's child (`parentLayerId`) and keeps its own
tracks, if any, on *its own* `opacity`/`transform` — two different layers,
so the two animations can never collide, no matter how their time ranges
relate. This is a fixed rule (preset present → always wrap), not conditional
on whether a collision would actually occur, which keeps the compiler's
output shape predictable. An object with no preset compiles to a single
flat layer exactly as before — wrapping only happens when there's a preset
to hold.

`PreviewCanvas.swift` renders this by building a real tree from the flat
`parentLayerId`-linked `layers[]` (`LayerTree.build`) and rendering it as
genuinely nested SwiftUI views (`LayerNodeView`, recursive): a group's
`.offset`/`.scaleEffect`/`.rotationEffect`/`.opacity` modifiers wrap a
container its children render inside, so SwiftUI's own layout engine
composes parent and child transforms correctly — no manual matrix
multiplication needed, and it generalizes to arbitrary nesting depth for
free. This is also why `scale` had to switch from being baked into
`.frame(width:height:)` to a real `.scaleEffect()`: the old approach only
happened to look right for a single ungrouped layer and would not compose
through nesting.

Verified on the simulator (`EditorDemoView`'s "Object's own animation"
toggle): a photo with Fade in/out *and* a continuous whole-clip rotation
(standing in for a future real custom-keyframe authoring UI, which doesn't
exist yet) renders both correctly at once — full opacity and exactly 180°
rotated at the clip's midpoint. Read back `project-v2.json` confirms the
split: `demo-layer-fx` (`type: "group"`, no parent) owns the `opacity`
track; `demo-layer` (`parentLayerId: "demo-layer-fx"`) owns the
`transform.rotate.z` track — never the same layer, never the same track.

**This is the general rule for every future preset/effect, not just
in/out** — confirmed 2026-10-06. Any named preset whose compiled form needs
its *own* keyframe track(s) (an entrance/exit animation, a future shake/
pulse/bounce preset, anything time-varying) must wrap the object in its own
group layer the same way, rather than writing onto the object's own layer
or trying to merge into whatever track is already there. The dividing line:
- **Needs a track → wrap.** Same reasoning as in/out: the object's own
  layer might already carry a track on the same `path` (today only via
  `injectCustomRotation`-style test code; once real custom-keyframe
  authoring exists, from the user), and two tracks can never share one
  layer's one `path` slot.
- **Doesn't need a track → don't wrap.** `effectPresets` (glow/blur/sepia/
  ...) compiles to a `filter` id reference — a static field, not a track —
  so it was never at risk of colliding with anything and stays directly on
  the object's own layer, no wrapper needed. Don't wrap presets "for
  consistency" when they have no track of their own; wrapping is a
  conflict-avoidance mechanism, not a decoration.

If/when a second preset that needs tracks is added (e.g. a future
"shake"), it should go through the *same* wrapper the in/out preset uses
when both are present on one object (one group, multiple tracks on it —
same as Fade-in + Fade-out already sharing the `opacity` track on today's
wrapper), not a second nested wrapper layer, unless two such presets
genuinely need to animate the *same* path independently (at which point
the same disjoint-time-concatenation question from the top of this note
applies again, one level up).

## Protocol V2 must stay atomic — no named/convenience presets

This is the central design rule, confirmed 2026-10-06, and it generalizes
beyond animation:

**Protocol V2 (`packages/motion-protocol`) only ever contains the lowest-level
atomic primitives** — raw keyframe tracks, raw paint, raw geometry, raw SVG
filter-primitive graphs. It never contains a *named* convenience shortcut for
something a human would call by name (a preset, a style, a one-click effect).
Anything with a name — "fade in", "glow", "slide out", "sepia" — is an
**Editor-tier concept** that compiles down into Protocol V2's atomic form.
The Editor Document stores the name + params; a compiler step expands it.

This was first established for **animation presets**: `ios-editor`'s
`EditorDocument`/`PresetCompiler.swift` holds `{ kind: "fade", durationMs }`
and expands it into raw end-anchored keyframe tracks before anything becomes
Protocol V2 JSON (see `PresetCompiler.swift`'s doc comment on same-path
track merging). Protocol V2 itself never hears the word "fade".

**The same rule now applies to visual effects.** `V2Filter`'s 17 SVG filter
primitives (`feGaussianBlur`, `feFlood`, `feComposite`, `feMerge`, etc.) are
the atomic, protocol-level representation of an effect graph — this is the
complete standard SVG primitive set and can build anything (glow, inner
glow, drop shadow, lighting, turbulence) by composition. `V2Effect`'s named
atoms (`outer-glow`, `inner-glow`, `shadow`, `blur`, `grayscale`, `sepia`,
...) are a **ready-made convenience layer that belongs at the Editor tier**,
compiling down into a `V2Filter` primitive chain — the exact same shape of
relationship as the animation-preset case above.

**Status: applied in both Swift and TS (2026-10-06).** `ios-editor`
follows this rule — `Protocol/V2Layers.swift` has no `effects`/
`backdropEffects` field (only `filter`/`backdropFilter` id references);
`EditorDocument/EffectPresets.swift` holds the named presets
(`EffectPresetKind`) and compiles each into a `V2FilterPrimitive` chain
(`compileFilter`), registered in the project's root `filters[]` and
referenced by id — verified end-to-end (built, ran on the simulator, read
the saved `project-v2.json` back to confirm the compiled primitive chain's
`in`/`result` wiring).

The agreed approach was **prototype in Swift first, then port proven changes
back to the TS schema** — that port has now happened: `V2Effect` and
`src/v2/effects.ts` are **deleted** from `packages/motion-protocol`; the
layer schema (`src/v2/layers/base.ts`) has only `filter`/`backdropFilter` id
references, same as Swift. This was an explicit, confirmed breaking change to
`formatVersion: 2` (no migration path was written for documents that used the
old `effects`/`backdropEffects` fields — ask before writing one if a real
document needs it). Tests across `project.test.ts`/`animation.test.ts`/
`filter-schema.test.ts` were updated to match. **Not yet done:** `pnpm
typecheck`, `pnpm test`, and `pnpm generate:schema` (to refresh the committed
`schema/v2.json`, which is now stale) still need to be run — this sandbox has
no Node, so the user must run them locally and report back before trusting
this is fully green.

## Layer transform: one explicit component form, no `operations[]`

Locked in 2026-10-06. A layer transform (`V2Transform` in
`ios-editor/Sources/AppModule/Protocol/V2Types.swift`) is authored
through exactly 6 fields — `translate`, `scale`, `rotate`, `skew`, `anchor`,
`perspective` — and nothing else. There is deliberately no second, ordered
`operations: [...]` list living alongside it anymore. **Do not re-add one**,
even to support some new transform need — these fields already cover both
2D and 3D:

- **2D**: `translate.x/y`, `scale.x/y`, `rotate.z` (a pure in-plane spin —
  `PreviewCanvas.swift`'s `.rotationEffect`, no perspective needed),
  `skew.x/y`, `anchor.x/y`.
- **3D**: `translate.z`, `scale.z`, `rotate.x`/`rotate.y` (tilting the layer
  out of the screen plane — `PreviewCanvas.swift`'s `.rotation3DEffect`,
  which needs `perspective` to read as depth rather than a flat skew),
  `anchor.z`, and `perspective` itself (the one capability the old
  `operations[]` form had that the component form didn't — promoted to its
  own explicit field instead of an ordered extension entry).

Why: the previous design kept `operations[]` *alongside* the component
form, with an undocumented "`operations[]` wins when both are present"
tie-break that the Swift renderer only partially honored (silently ignored
`operations[]` translate/scale/skew/matrix while only reading
rotate/rotateY) — a real, silent correctness gap. Two representations of
the same thing that can disagree is exactly what the atomicity rule above
exists to prevent.

This is scoped to the **layer** transform only. clip-path/mask/pattern
*definition* transforms are a different object with a legitimately 2D-only
need — they keep their own ordered-operation list,
`V2SvgTransformOperation` (`Protocol/V2Clip.swift`), which is not a
duplicate of `V2Transform` and does not reintroduce this conflict.

## Text layout stays atomic — intent vs. resolved split

Locked in 2026-10-06, Swift only so far (not yet ported to TS — same
"prototype in Swift first" approach as the other rules here). A text
layer's `layout` used to be one object mixing two genuinely different
things: **authoring intent** (`textAlign`, `wrap`, `whiteSpace`,
`textOverflow`, `maxLines`, `textIndent`, `hardBreaks`, `sizing` — "how do I
want this wrapped/aligned") and **resolved shaping output**
(`lineHeight`, `contentWidth`/`contentHeight`, `contentOffsetX`/`Y` — "what
did shaping the font against that intent actually measure"). Keeping both in
Protocol V2 at once is a real atomicity risk, worse than the animation/effect
preset cases above: `V2TextChunk.x`/`y` (the per-line position — the only
fully unambiguous, renderer-neutral representation of *where text actually
sits*) were optional, so a document could omit them and lean on `layout`
alone, forcing every renderer to run its own line-breaking/shaping to
reconstruct positions — and Core Text (iOS) vs. HarfBuzz vs. a browser
engine do not wrap text identically. That breaks the one guarantee Protocol
V2 exists to make: any renderer draws the same pixels from the same JSON.

**Resolution:** `V2TextLayout` (`Protocol/V2TextLayer.swift`) now holds only
the resolved fields (`lineHeight`, `contentWidth`, `contentHeight`,
`contentOffsetX`, `contentOffsetY`). The intent fields moved to
`EditorTextLayoutIntent` (`EditorDocument/EditorTextLayer.swift`), Editor-tier
only. `TextLayoutCompiler.swift` is the compiler step that resolves intent +
font + frame width into that `V2TextLayout` plus one `V2TextChunk` per
*already-wrapped visual line*, each with a required (never omitted by this
app) `x`/`y` origin — using real Core Text line-breaking
(`CTTypesetterSuggestLineBreak`/`CTTypesetterSuggestClusterBreak`), not a
third-party engine, not hand-rolled fake numbers. Verified end-to-end: built,
ran on the simulator (`Text wrap` fixture in `ContentView`), confirmed
visually across wrap/align/width combinations, and read the saved
`text-project-v2.json`/`text-editor-document.json` back to confirm the split
(Protocol V2's `layout` has no `textAlign`/`wrap` anywhere; chunk `x`/`y`
values and `lineHeight` deltas matched real font-metric math, not hardcoded
numbers).

Known gaps, intentionally out of scope for this slice: `maxLines`/
`textOverflow` (ellipsis) truncation isn't implemented; `hardBreaks` isn't
read by the compiler yet; text is not currently track-animatable (no
`sampleLayer` support for `payload.chunks.*` paths). None of these change the
intent/resolved split above — they're renderer feature gaps, the same
category as `.step`/`.spring` easing not being evaluated yet.

## Text font stays per-span (matches real SVG `<tspan>`)

Considered and reverted 2026-10-06: briefly tried moving `font` from
`V2TextSpan` to one shared `V2TextLayerPayload.font`, justified at first as
a file-size optimization. Measured it instead: one `V2TextFont` object is
~43 bytes compact-JSON; even a 200-character caption wrapping into 5-6
lines only costs ~215 bytes of duplication — trivial next to a real
project's asset metadata/keyframe tracks (tens of KB+). Since the size
argument didn't hold up, and per-span font is a real SVG/CSS capability
(independent per-`<tspan>` font-family) with real schema-fidelity value,
**`V2TextSpan.font` stays** — same shape as the real TS schema, nothing
removed from Protocol V2 here. `EditorTextLayer`/`TextLayoutCompiler` still
only author one font per layer today (no per-word mixed-font UI exists yet),
but that's an Editor-tier/product-scope limitation, not a protocol one —
Protocol V2 keeps the full capability in case it's needed later.

## `rangeSelectors` (stagger/typewriter templates) stays in Protocol V2 — a deliberate, measured exception

Decided 2026-10-06. `payload.rangeSelectors[]` (`V2TextRangeSelector` —
`unit`, `range`, `stagger: {perUnitDelayMs, direction}`, a template `track`)
is a named authoring shorthand that gets expanded only downstream, at the
not-yet-built `motion-compiler` (Protocol V2 → Runtime IR) stage — meaning a
persisted Protocol V2 document can rely on it without ever materializing
per-character spans/tracks. By the letter of the atomicity rule above, this
is *not* atomic: a renderer has to understand the concept "stagger," not
just read numbers.

**This was audited the same way the `V2TextSpan.font` question was — by
measuring, not guessing — and this time the numbers justify keeping it.**
Fully expanding a stagger template into real per-character spans + one
layer-level track per character (each track needs a long explicit path like
`payload.chunks.line-0.spans.ch-12.fillOpacity` plus a full keyframe pair)
costs roughly **170 bytes per character**. For a 5-character "HELLO" that's
~850 bytes either way (negligible). For a 50-character stagger reveal, full
expansion costs **~8.5 KB**, vs. ~280 bytes for the compact template form —
and that gap grows linearly, unbounded, with text length. This is the
opposite shape of the font question (which scaled with *line count*, always
small): here the per-unit cost is large (long paths) and the unit count
(characters) can be large, so the "it'll get heavy" argument is measured,
real, and unbounded for this one specifically — not a vague feeling.

**Resolution: keep `rangeSelectors` in Protocol V2 as compact, unexpanded
intent.** Compactness wins over strict atomicity here, as an explicit,
documented exception — not an oversight. If `motion-compiler` or any other
future renderer doesn't implement stagger expansion, it should fail closed
with a diagnostic (matching the existing doc comment's note on `unit:
"word"` being reserved-but-unimplemented) rather than silently rendering
static, unstaggered text.

Implemented in Swift and verified on the simulator (`ios-editor`'s
`Text wrap` fixture, "Typewriter reveal" toggle): `KeyframeSampler.swift`'s
`resolveTextRuns` is the Runtime interpreting `rangeSelectors` directly —
splitting a staggered span into one run per character, each with its own
real Core Text x-offset (`TextLayoutCompiler.offsetForCharacter`, not an
approximation) and its own time-shifted opacity sample. Two notes from
building this:
- **The reveal *look* (instant vs. fade) is an Editor-tier choice**
  (`EditorTypewriterIntent.reveal`), not hardcoded in
  `PresetCompiler.swift` — same rule as any other named preset/effect.
  "instant" is the honest default for testing the stagger mechanism itself
  (timing + position) without a fade blending adjacent frames and making
  it harder to judge by eye.
- **"instant" is CSS step easing** (`V2Easing.step`), not a tiny time
  window — this closed a real, previously-documented gap:
  `KeyframeSampler.swift`'s `interpolate()` used to fall back to linear for
  `.step`/`.spring` easing. `stepEase()` now implements `.step` properly
  (count + jump-start/jump-end), so a hard on/off switch is a first-class
  Runtime capability, usable anywhere a track accepts an easing — not
  something specific to typewriter reveals. `.spring` remains the one
  still-linear-fallback gap.

**`V2TextChunk.dx`/`.dy`/`.rotate` (per-character position/rotation)
verified the same way** — "Wave" toggle in the same fixture,
`EditorTextWaveIntent` compiles a sine-wave arc-text effect into literal
per-character `dx`/`dy`/`rotate` arrays (`PresetCompiler.swift`'s
`compileTextPayload`), no compact/unexpanded form here since these three
are already the atomic, lowest-level primitives (unlike `rangeSelectors`,
there's nothing to keep compact). `resolveTextRuns` now splits a span into
one run per character whenever a chunk carries any of `dx`/`dy`/`rotate`,
independent of whether a stagger selector also applies. Confirmed on the
simulator (real sine-wave text) and by reading back `text-project-v2.json`
(20-entry arrays with real trig values, e.g. `dx: [3, 2.121..., ~0, ...]`
matching `amplitude * 0.3 * cos(phase)` exactly — not placeholders).
`textAnchor` was audited by analysis, not by building: this app's
`TextLayoutCompiler` always resolves `chunk.x` to the literal left edge
already, so `textAnchor` would only ever be `"start"` here — nothing to
test since there's no second code path that would interpret it
differently.

**`V2TextChunk.textPath` (text following an arbitrary curve) is built the
same way wave is** — `TextPathResolver.swift` does real arc-length
placement (flattens a `CGPath` to line segments, walks cumulative length,
places each glyph's own center at the right distance along the curve,
rotated to the path's tangent there) using native Core Graphics/Core
Text only, no third-party geometry library. Compiled by
`PresetCompiler.swift`'s `compileTextPayload` into the exact same literal
`dx`/`dy`/`rotate` arrays "wave" uses — **baked at compile time, not left
as a live path reference for the Runtime to interpret**, the same
reasoning as the layout/wrap precedent above: two renderers each
implementing their own path-flattening (different tessellation tolerances,
different arc-length algorithms) would not necessarily place glyphs
identically from the same JSON, which pre-resolving avoids entirely. Only
a circle is wired up in this slice (`EditorTextPathIntent.radius`); a
`pathId`-reference resolver against the project's real `clipPaths`/
path-layer geometry is future work, reusing the same flatten/arc-length
machinery unchanged.

**A real bug surfaced and got fixed building this, worth remembering**:
the first version used `CGPath(ellipseIn:)` for the circle and the text
came out upside-down, running along the *bottom* of the circle instead of
the top — `CGPath(ellipseIn:)`'s start point and winding direction aren't
something to assume/guess. Fixed by building the circle manually
(`TextPathResolver.circlePath`) with an explicit start angle (-90°, 12
o'clock) and explicit direction (angle increasing = clockwise on screen,
i.e. left-to-right across the top) — don't go back to the built-in
initializer for this without re-verifying the orientation on the
simulator. Verified: real sentence (`wrap: "none"`, so it stays one
continuous line — text-on-path and multi-line wrapping don't compose
sensibly together, a known, reasonable scope limit) reads upright,
curving smoothly along a circle on the simulator; `rotate` values in the
saved JSON increase smoothly and almost linearly (~4°, ~10°, ~15°, ~18°,
~24°...), matching constant angular velocity along a circle — not
placeholders.

Still open, not yet built or audited: `textDecoration`,
`letterSpacing`/`wordSpacing`, `dominantBaseline`/`alignmentBaseline`/
`baselineShift`, `textLength`/`lengthAdjust`, `kerning`/`opticalSizing`/
`smallCaps`, `resolvedFontAssetIds`.

## Scrubbing must never re-decode media inline from `body`

Fixed 2026-10-06, two related but distinct bugs found by actually scrubbing
in the simulator, not just reading the code:

### Video — synchronous `AVAssetImageGenerator` blocked the main thread

`VideoFrameCache.swift` used `copyCGImage(at:actualTime:)`
(synchronous) called directly from `PreviewCanvas.swift`'s view `body` — every
slider-drag tick blocked the main thread (and therefore the SwiftUI render
loop) on a real seek+decode, which is what made scrubbing feel janky. Fixed
by switching to the `async` `AVAssetImageGenerator.image(at:)` API, driven
from a SwiftUI `.task(id:)` keyed on a coarse "scrub bucket" (`VideoFrameCache
.scrubBucket(forMs:)`, ~65ms/~15fps resolution — fine enough for scrubbing,
coarse enough to avoid firing a fresh decode on every pixel of drag) so
`LayerContentView` keeps showing its last successfully decoded frame
(`@State private var cachedVideoImage`) while a new one loads, instead of
flashing gray. Also widened `requestedTimeToleranceBefore/After` from `.zero`
to one scrub bucket, letting AVFoundation return the nearest already-decoded
frame instead of forcing a precise (slower) seek on every request. Don't
reintroduce the synchronous call for "simplicity" — it's the direct cause of
the jank this fixed.

### Photo — no caching at all, re-decoded the file from disk every render

A static image layer's content never depends on scrub position, yet
`PreviewCanvas.swift`'s old `bundledImage(filename:)` called
`UIImage(contentsOfFile:)` (disk read + decode) straight from `body` with no
cache — every slider tick re-read and re-decoded the same file from scratch,
for no reason, since the result never changes. Fixed with `BundledImageCache`
(`PreviewCanvas.swift`): decode once per filename, keep it in memory,
return the cached `UIImage` on every subsequent call. Simpler fix than the
video case (no async/`.task` needed) because the content is genuinely
static — the bug here was redundant repeated work, not a slow one-off
operation.

## Other standing rules

- **No third-party rendering/media engines.** No Skia, no FFmpeg, no bundled
  C++ engine of any kind. iOS rendering is native only: SwiftUI, Core
  Animation, Core Graphics, AVFoundation, Core Image, VideoToolbox. This was
  a deliberate correction (an earlier Skia mention in docs was only ever a
  suggestion, not an architectural decision) — see `ARCHITECTURE.md`.
- **Two-tier document model.** Editor Document (authoring intent: media +
  named preset bindings) vs Protocol V2 (atomic, renderer-neutral,
  compiled). Protocol V2 is never the only persisted document.
- **Command pattern, not JSON Patch or CRDT**, for the Editor's undo/redo
  and edit model. CRDT is explicitly deferred until real-time multi-device
  collaboration is an actual requirement.
- **"Valid by construction," not a ported validator.** `ios-editor`'s
  Swift mirror of Protocol V2 (`Sources/AppModule/Protocol/`) is a full
  *shape* port (100%, including the 17 filter primitives, full text layer,
  masks/clips/markers/patterns) but deliberately ports **no** cross-field
  validation (`superRefine` logic — duplicate IDs, dangling references,
  track-path/kind matching). Editor commands must make invalid states
  unconstructable instead; the TS validator stays canonical.
- **No SVG-import-compatibility alias fields** in anything this app
  authors. E.g. `V2LinearGradient.angle` and `V2PatternFill.transform`
  (duplicates of `x1/y1/x2/y2` and `patternTransform`) were removed from the
  Swift port — they existed in the TS schema only to ease importing
  hand-authored/legacy SVG, which isn't this app's use case.
- **Hand-written Swift Codable types are a temporary stand-in.** The long-term
  intent is generated Codable types from `schema/v2.json`, not a
  hand-maintained mirror forever (see `ARCHITECTURE.md`).

## `NeonixEditor.xcodeproj` lives at the repo root, not inside `ios-editor`

Changed 2026-10-06, at the user's explicit request (their external
device-running tool expected an ordinary `.xcodeproj`, which a bare SwiftPM
`.iOSApplication` package doesn't have — and they wanted to open the repo
root directly in Xcode, not `cd` into `ios-editor` first). **Both
`project.yml` and the generated `NeonixEditor.xcodeproj` are at
`neonix-mobile/` (the repo root)**, not under `ios-editor/` — only the
actual Swift source tree (`Sources/AppModule`, `Tests/AppModuleTests`)
stayed put under `ios-editor/`; `project.yml`'s `sources:` paths point
into it (`ios-editor/Sources/AppModule`, etc.) rather than being
relative to `ios-editor` itself. **`NeonixEditor.xcodeproj` is
generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from
`project.yml`** — it is never hand-edited, and `project.yml`, not the
`.xcodeproj` itself, is the source of truth for what files/targets exist.
After adding/removing/renaming any file under `ios-editor/Sources/AppModule`
or `ios-editor/Tests/AppModuleTests`, regenerate it from the repo root:
```
xcodegen generate --spec project.yml
```
(`xcodegen` isn't preinstalled in this sandbox; it was fetched from
`github.com/yonaskolb/XcodeGen`'s release zip into the scratchpad — the
user's own machine likely has it via Homebrew, or needs it once:
`brew install xcodegen`.)

**`ios-editor/` itself moved from `apps/ios-editor/` straight to the repo
root, 2026-10-08**, at the user's request — `apps/` only ever held this one
app, so the extra nesting wasn't earning its keep. `project.yml`'s
`sources:` paths were updated to match (`ios-editor/Sources/AppModule`,
etc., no `apps/` prefix), `NeonixEditor.xcodeproj` regenerated, and the full
unit + UI test suite re-run green after the move.

**`Package.swift` (the original SwiftPM `.iOSApplication` package) was
deleted the same day**, not kept alongside. The first attempt kept both
files side by side in the same directory, reasoning they were independent
build systems reading the same source tree — true for command-line
`xcodebuild` (verified both built clean in isolation), but **false for
opening the project in Xcode's GUI**: Xcode auto-discovers any `Package.swift`
sitting in a `.xcodeproj`'s own directory and tries to validate it too, and
`.iOSApplication` is a product type Apple restricts to being opened
*directly* as its own package — having a sibling `.xcodeproj` present
trips `"iOS app products are only permitted in Swift Playground packages"`,
a real, GUI-only build error the command-line check never surfaced. Once
`NeonixEditor.xcodeproj` existed and was confirmed building/testing clean on
its own, `Package.swift` had no remaining purpose, only this failure mode —
deleted, along with the `.swiftpm/`/`.build/` directories it generated
(reversible via git if ever needed; this repo has one).

Removing it also deleted the one awkward side effect it had caused: two
`#if SWIFT_PACKAGE`/`#else` branches (in `PreviewCanvas.swift`'s
`bundledURL(filename:)` and `KeyframeSamplerTests.swift`'s `@testable
import`) that existed only to paper over the two build systems disagreeing
on the resource-bundle API (`Bundle.module` vs `Bundle.main`) and the test
target's module name (`AppModule` vs `NeonixEditor`). Both are single
unconditional lines now — `Bundle.main`, `@testable import NeonixEditor` —
don't reintroduce the SwiftPM branch without first solving the GUI
conflict above some other way.

## Key files

- `ARCHITECTURE.md` — full architecture writeup, mobile-first roadmap.
- `packages/motion-protocol/README.md` — the canonical Protocol V2 field
  reference (TS/Zod source of truth for schema shape).
- `ios-editor/` — the Swift vertical slice's source tree (Runtime
  sampler, native SwiftUI/AVFoundation renderer, Editor Document + preset
  compiler demo). No Node/pnpm in this sandbox — iOS work is verified via
  `xcodebuild` directly (see inline comments for the simulator workflow,
  including the manual `.app` bundle assembly this needed before the real
  `.xcodeproj` existed). **The buildable project itself —
  `NeonixEditor.xcodeproj` / `project.yml` — lives at the repo root**, not
  in this folder; see the note above this one.
