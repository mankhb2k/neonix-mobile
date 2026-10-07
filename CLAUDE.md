# CLAUDE.md

Working notes for Claude Code sessions in this repo. See `ARCHITECTURE.md`
for the full picture; this file is the short, load-bearing rule list.

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

Added 2026-10-07, `apps/ios-editor/UITests/` (`NeonixEditorUITests` target in
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

This was first established for **animation presets**: `apps/ios-editor`'s
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

**Status: applied in both Swift and TS (2026-10-06).** `apps/ios-editor`
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
`apps/ios-editor/Sources/AppModule/Protocol/V2Types.swift`) is authored
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

Implemented in Swift and verified on the simulator (`apps/ios-editor`'s
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
- **"Valid by construction," not a ported validator.** `apps/ios-editor`'s
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

## `NeonixEditor.xcodeproj` lives at the repo root, not inside `apps/ios-editor`

Changed 2026-10-06, at the user's explicit request (their external
device-running tool expected an ordinary `.xcodeproj`, which a bare SwiftPM
`.iOSApplication` package doesn't have — and they wanted to open the repo
root directly in Xcode, not `cd` into `apps/ios-editor` first). **Both
`project.yml` and the generated `NeonixEditor.xcodeproj` are at
`neonix-mobile/` (the repo root)**, not under `apps/ios-editor/` — only the
actual Swift source tree (`Sources/AppModule`, `Tests/AppModuleTests`)
stayed put under `apps/ios-editor/`; `project.yml`'s `sources:` paths point
into it (`apps/ios-editor/Sources/AppModule`, etc.) rather than being
relative to `apps/ios-editor` itself. **`NeonixEditor.xcodeproj` is
generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from
`project.yml`** — it is never hand-edited, and `project.yml`, not the
`.xcodeproj` itself, is the source of truth for what files/targets exist.
After adding/removing/renaming any file under `apps/ios-editor/Sources/AppModule`
or `apps/ios-editor/Tests/AppModuleTests`, regenerate it from the repo root:
```
xcodegen generate --spec project.yml
```
(`xcodegen` isn't preinstalled in this sandbox; it was fetched from
`github.com/yonaskolb/XcodeGen`'s release zip into the scratchpad — the
user's own machine likely has it via Homebrew, or needs it once:
`brew install xcodegen`.)

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
- `apps/ios-editor/` — the Swift vertical slice's source tree (Runtime
  sampler, native SwiftUI/AVFoundation renderer, Editor Document + preset
  compiler demo). No Node/pnpm in this sandbox — iOS work is verified via
  `xcodebuild` directly (see inline comments for the simulator workflow,
  including the manual `.app` bundle assembly this needed before the real
  `.xcodeproj` existed). **The buildable project itself —
  `NeonixEditor.xcodeproj` / `project.yml` — lives at the repo root**, not
  in this folder; see the note above this one.
