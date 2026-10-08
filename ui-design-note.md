# Editor screen — UI design notes

Design rationale for `apps/ios-editor/Sources/AppModule/UI/Editor/` and
`UI/PreviewCanvas.swift`. Source files keep short pointer comments; the
"why" lives here so source stays readable.

## Layout: Stage → Titlebar → Timeline

`EditorShellView` stacks 3 sections inside one `GeometryReader`:

1. **Stage** — a square sized purely from screen width: `squareSide =
   geo.size.width`, height derived by squaring that (not fit into whatever
   height is left over). The video renders at `squareSide * 0.96`,
   centered — any project aspect ratio (9:16/16:9/1:1) scales down to fit
   inside that 96% box, pillarboxed/letterboxed as needed. The square's own
   size never depends on the project's aspect ratio.
2. **Titlebar** (`controlsRow`) — fullscreen (left, disabled), play/pause
   (center), undo/redo (right, disabled). Height is **measured**, not
   hardcoded: `TitlebarHeightKey` (a `PreferenceKey`) reads the row's real
   rendered height off a `.background(GeometryReader { ... })`, written
   back into `titlebarHeight` via `.onPreferenceChange`. A reported `0` is
   ignored (only ever a transient artifact during the `fullScreenCover`
   presentation animation) so the value settles monotonically instead of
   oscillating.
3. **Timeline** — gets whatever's left: `geo.size.height - titlebarHeight -
   stageHeight - 1 (divider)`, clamped to `0`. No minimum floor — on a
   layout where Stage's square genuinely exceeds the available height,
   Timeline can shrink to nothing. That's an accepted trade-off, not a bug.

**History**: an aspect-ratio-*adaptive* Stage (no forced square; Timeline
got whatever height was left, Stage reshaped per project) was built and
fully passed every test, then reverted by request in favor of the fixed
square above. Recoverable from git history if wanted again later.

## Titlebar details

- **Icons**: `.font(.headline)` (17pt) + `.fontWeight(.regular)` on all 4
  icons (fullscreen, play/pause, undo, redo) — uniform size and weight.
  SF Symbols support 9 weights (`ultraLight` → `black`); `.fontWeight(_:)`
  overrides whatever weight a text style like `.headline` implies.
- **Height**: currently `.padding(.vertical, 12)` + icon size — measured
  height is whatever that actually renders to (confirmed ~50-55pt on
  iPhone via pixel measurement), not a fixed constant anywhere.
- **Play/pause centering**: it's in its own `HStack(Spacer(), button,
  Spacer())`, layered via `ZStack` *underneath* a second `HStack` holding
  the left/right buttons — not one shared `HStack` with two `Spacer()`s.
  A single shared `HStack` only centers its middle child when both side
  groups are equal width; here they never are (1 button left, 2 right), so
  play/pause would sit visibly off-center, pulled toward the lighter side.

## `PreviewCanvas` scaling and the hit-testing bug

`PreviewCanvas` renders `V2Project` content authored in a fixed coordinate
space (`composition.width`/`height`, e.g. 360×640). To fit that into
whatever box a caller gives it: `GeometryReader` computes `scale =
min(geo.width/compWidth, geo.height/compHeight)`, then `content.frame(native
size).scaleEffect(scale).frame(geo.size).clipped()`.

Two real bugs found building this:

1. **No scaling at all, originally** — it used to be a bare
   `.frame(width: composition.width, height: composition.height)`, so a
   composition authored at realistic sizes (640, 1920) rendered that many
   literal *points* wide. Invisible for a long time because every demo
   fixture used small values (240-320) that happened to be close to a
   phone's own width. Fixed with the `GeometryReader`+`.scaleEffect`
   approach above.
2. **Hit-testing absorbed real taps even after that fix** — `.scaleEffect`
   changes how a view is *drawn*, not its layout footprint (a well-known
   SwiftUI gotcha), so the oversized pre-scale footprint could still
   participate in hit-testing past `.clipped()`'s boundary. Found only by
   building a real `XCUITest` (`simctl` cannot synthesize a real tap, so no
   screenshot/build check ever caught it): taps on `EditorShellView`'s
   `Huỷ` button silently failed for 2 of 3 sample compositions. Root cause
   confirmed by swapping `PreviewCanvas` for a plain `Color` — passed every
   time; the real view still sometimes absorbed the tap. Fix: `.allowsHitTesting(false)`
   on `PreviewCanvas` wherever it's embedded — it has no interactive
   content of its own, so this costs nothing regardless of the exact
   mechanism `.clipped()` wasn't fully covering.

## Nav bar

`Huỷ`/`Xuất` — text buttons (not icons), matching the native iOS Photos
editor. `.buttonStyle(.glass)` / `.glassProminent` on iOS 26+ (Liquid
Glass), falling back to plain/`.borderedProminent` below that —
`project.yml`'s deployment target stays 17.0. Both currently just
`dismiss()`; no edit-state/export pipeline exists yet to make them diverge.

## Fullscreen control bar: real Liquid Glass APIs, not `.ultraThinMaterial`

`fullscreenStage`'s bottom bar (play/pause, scrubber, exit) is a single
glass pill — same Photos-app player-bar look, confirmed via the real SDK
(`SwiftUICore.swiftinterface`), not guessed:

- `Glass` (`.regular`/`.clear`, `.tint(_:)`, `.interactive()`) + `.glassEffect(_:in:)`
  — the actual modifier that renders the glass material, applied **once**
  to the whole `HStack` (play/scrubber/exit) in `Capsule()` shape. This is
  one cohesive pill, not 3 separate glass bubbles that morph together —
  wrapping each button in its own `.glassEffect` would be the wrong pattern
  here (that's for Dynamic-Island-style clusters that visually merge/split).
- `GlassEffectContainer` still wraps that single `.glassEffect` view —
  Apple's own recommended pattern even for one glass shape (correct
  sampling), not only for multiple morphing shapes.
- Both are `@available(iOS 26.0, *)`-gated (confirmed in the SDK
  interface), same as `Huỷ`/`Xuất`'s `.buttonStyle(.glass)` — falls back to
  `.background(.ultraThinMaterial, in: Capsule())` below that, since
  `project.yml`'s deployment target stays 17.0.
- The scrubber (`FullscreenScrubber`) is a hand-built `DragGesture`-driven
  track, not a `Slider` — a `Slider` can't grow its track height on press,
  which is the "slightly enlarges while dragging" feel the user asked for
  (Photos does the same). Its track height 4pt → 8pt with a spring
  animation; dragging also pauses playback (`onScrubStart`), same
  convention `TimelineView`'s own scrubber already uses.

Verified on the simulator (temporarily driving `isFullscreen = true`): the
pill renders as one capsule with visible glass refraction of the video
behind it, play triangle + thin progress track + minimize icon all legible
inside it.

**While actively scrubbing, play/exit hide and a time readout (current /
total) appears above a full-width track** — matching the real Photos app
bar exactly (confirmed against a screenshot of it), not guessed. `isDragging`
moved out of `FullscreenScrubber`'s own `@State` into a binding
(`EditorShellView.isScrubbing`) so the *parent* row can react to the same
flag: `fullscreenControlBarContent` conditionally omits the play/exit
buttons and shows `Text`s formatted `mm:ss.hh` (current) / `mm:ss` (total)
while `isScrubbing` is true, all under one `.animation(value: isScrubbing)`
so the button-hide, text-appear, and track-thicken all animate as a single
state transition rather than three independently-timed ones. Verified on
the simulator by temporarily forcing `isScrubbing = true` (same reasoning
as every other `simctl`-can't-synthesize-gestures case in this file: a real
drag isn't something a screenshot check can exercise, but the *rendered
result* of being mid-drag can be forced and inspected directly).

**The scrubbing bar is also narrower (2/3 screen width) and a
`RoundedRectangle`, not the full pill `Capsule`** — matching a second
reference screenshot of the real Photos app exactly: while dragging, Photos
visibly shrinks its bar inward and squares off its corners, rather than
keeping the edge-to-edge pill shape. `fullscreenStage` now wraps its
`ZStack` in a `GeometryReader` to get the real screen width, and
`fullscreenControlBar(screenWidth:)` computes `barWidth` (`screenWidth *
2/3` while scrubbing, `screenWidth - 40` otherwise — the same effective
width the old fixed `.padding(.horizontal, 20)` used to produce) and
`barShape` (`RoundedRectangle(cornerRadius: 24, style: .continuous)` while
scrubbing, `Capsule()` otherwise), both type-erased through `AnyShape`
(`SwiftUICore`, iOS 17+) since `.glassEffect(_:in:)`/`.background(_:in:)`
need one concrete `some Shape` type, not two branches of different
concrete types. `ZStack(alignment: .bottom)` centers the narrower bar
horizontally for free — no separate centering logic needed. One
`.animation(value: isScrubbing)` wraps the whole bar (width + shape +
content), so the width/shape change and the content change
(`fullscreenControlBarContent`'s own play/exit/text swap) animate as one
coordinated transition, not two independently-timed ones. Verified the
same way as the rest of this section: forcing `isScrubbing = true` and
screenshotting — the bar renders as a flat-sided rounded rectangle at
roughly 2/3 width, not a pill.

**Bottom inset bumped `24` → `56`** — the bar originally sat flush against
the bottom edge, crowding the home indicator with no breathing room (looked
cramped on the simulator screenshot the user sent). A single
`.padding(.bottom, 56)` on `fullscreenControlBar` in `fullscreenStage` is
the whole fix — no new mechanism needed, just a bigger constant. Verified
the same way as the rest of this section (forced `isFullscreen = true`,
screenshotted): visible gap between the bar and the bottom edge now.

**Reconsidered and corrected: width stays constant across both states —
only the shape and content height change.** The "2/3 width while scrubbing"
behavior above was a real misreading of what the user actually wanted;
once built and seen in motion, the width jump plus shape change plus
content change happening simultaneously read as too much motion at once.
`fullscreenControlBar(screenWidth:)`'s `barWidth` is now just
`screenWidth - 40` unconditionally — `isScrubbing` only drives `barShape`
(`Capsule()` ↔ `RoundedRectangle`) and `fullscreenControlBarContent`'s own
height (via its conditional time-label row and thicker track), never the
bar's width.

**Entering scrub mode now requires a genuine hold, not an instant touch.**
`FullscreenScrubber`'s gesture changed from a plain `DragGesture
(minimumDistance: 0)` (which started scrubbing the instant a finger
touched the track, even a brief incidental brush) to `LongPressGesture
(minimumDuration: 0.2).sequenced(before: DragGesture(minimumDistance: 0))`
— Apple's own documented pattern for "hold, then drag" (the exact pattern
their own Human Interface guidance/sample code uses for this interaction).
`.onChanged` handles `.first(true)` (hold threshold reached, no finger
movement yet — this is what flips `isDragging`/`onScrubStart`) and
`.second(true, drag?)` (now actively dragging — this is what calls
`seek(to:trackWidth:)`); both call a shared `beginScrubbingIfNeeded()` so
scrub mode starts at the hold, not only once movement begins. Not
independently verified end-to-end on this pass — `simctl` can't synthesize
a real hold+drag any more than it can a plain drag (see "Verification"
below), and unlike the width/shape changes this isn't something a forced
`@State` flag can stand in for, since the *gesture recognition itself* is
exactly what's unverified, not its downstream rendering. Worth a real-device
or `XCUICoordinate.press(forDuration:thenDragTo:)`-based check before
trusting this is fully correct.

**Reconsidered a second time, after jointly analyzing 2 real Photos
screenshots with the user before writing any code** (one normal, one
mid-scrub): two more corrections landed from that discussion.

1. **One shape for both states, not a `Capsule` ↔ `RoundedRectangle`
   swap.** The real Photos bar doesn't visibly change roundness when
   scrubbing starts — both states above now share one `barShape`
   (`RoundedRectangle(cornerRadius: 24, style: .continuous)`), computed
   once as a plain property, no more `isScrubbing`-conditional `AnyShape`
   branching (the `AnyShape` type-erasure this needed is gone entirely
   now that there's only one concrete shape).
2. **The track's own fill position must land at the identical pixel for
   the identical `currentTimeMs`, in both states — not just the outer
   bar's width.** The previous pass already fixed the *bar's* width, but
   `fullscreenControlBarContent` still removed the play/exit buttons from
   the layout via `if !isScrubbing { Button {...} }`: removing a view lets
   its `HStack` reflow, so the *track itself* (not just the bar) widened
   to fill the vacated icon space once scrubbing started — same
   underlying bug as the bar-width issue, one level deeper, not caught by
   the previous fix because that fix only addressed the *outer* frame.
   Fixed by keeping both buttons permanently present in the layout and
   fading them with `.opacity(isScrubbing ? 0 : 1)` +
   `.allowsHitTesting(!isScrubbing)` instead of an `if` — their frames
   still occupy space, so `FullscreenScrubber`'s measured width (and
   therefore its 0%–100% mapping) never changes between states. Verified
   by forcing `isScrubbing` to each value, screenshotting both, and pixel-
   diffing: the bar's own left/right edges measured identical (`min=180,
   max=801` in both), and stacking crops of both states confirmed the
   filled/unfilled boundary sits at the same x position in both — not
   just close, pixel-aligned in the comparison.

Also bumped while here, a small separate tweak the user asked for directly:
track thickness `4pt → 8pt` is now `5pt → 10pt` (same mechanism, just
bigger numbers — see the dedicated writeup above on how trivial this
change is, `.frame(height: isDragging ? 10 : 5)`, one line).

**Track made longer by tightening the chrome around it, at the user's
direct request after asking what was eating the width.** The 3 things
subtracting from the track's own length, at the time: each icon's
`.frame(width: 28, height: 28)` (28pt × 2), the `HStack(spacing: 20)`
between icon/track/icon (20pt × 2), and `fullscreenControlBarContent`'s
own `.padding(.horizontal, 16)` (16pt × 2) — 128pt total off the bar's own
width. User chose to tighten 2 of the 3: `spacing: 20 → 12` (+16pt to the
track) and `.padding(.horizontal, 16 → 10)` (+12pt), leaving icon size
untouched. Track thickness bumped again in the same request, `5pt/10pt →
6pt/12pt` (same `isDragging ? 12 : 6` one-liner, keeping the established
2× scrub/normal ratio). Verified on the simulator (forced `isFullscreen =
true`, fresh reboot first per the pitfall above): track visibly longer,
icons sit closer to it.

**Both fullscreen-bar icons given `.fontWeight(.medium)`** (play/pause and
exit-fullscreen, `.font(.title3)` was previously carrying no explicit
weight). Same one-line-per-icon pattern as the titlebar icons' own weight
pass from earlier in this project. Verified on the simulator (forced
`isFullscreen = true`, fresh reboot first): the exit icon's arrow strokes
read visibly bolder than before; `play.fill`'s own weight difference is
less visible since it's already a solid filled triangle, not a stroked
glyph — expected, not a sign the change didn't apply.

**Reversed a load-bearing decision from 2 passes ago, after jointly
re-analyzing a real Photos screenshot with the user**: the track no longer
keeps a frozen pixel position for "now" across states — it keeps the
correct *percentage*, and is allowed to reposition when the track's own
width changes. This directly undoes the "keep icons in the layout, just
fade them" fix from the width-continuity pass above; that fix solved the
wrong problem; the real Photos app actually lets the track reclaim the
icons' space entirely, growing both in height (`6pt → 18pt`, not `12pt` —
a real Photos screenshot shows a *much* thicker scrub track than the
previous guess; settled on `18pt` after a quick `20pt` → `18pt` adjustment)
and width (full bar width, not reserved-but-invisible
icon slots) when scrubbing starts. `fullscreenControlBarContent` is back
to `if !isScrubbing { Button {...} }` (removing the buttons from the
layout, not just fading them) — but now each button carries
`.transition(.move(edge: .top).combined(with: .opacity))`, so removal
isn't an instant pop: the icon visibly slides up while fading out (and the
reverse — sliding down while fading in — when scrubbing ends), matching
the user's own description of the real app's animation. `FullscreenScrubber`
needed no changes at all for this — its `fraction = currentTimeMs /
maxDurationMs` times `geo.size.width` was already computing a percentage
against whatever width `GeometryReader` reports, so once the `HStack`
reflows wider (icons gone), the fill position correctly recomputes against
the new width on its own; nothing was keeping it tied to a fixed width
except that the icons simply weren't being removed before. The time-label
row's own appearance above the track (same `VStack`) is what pushes the
track down + grows it, under the same existing `.animation(value:
isScrubbing)` — no separate manual offset needed for that, confirmed by
not adding one and it still reading correctly on the simulator.

Verified on the simulator (forced `isScrubbing = true` then `false`
separately, fresh reboot before each to avoid the warm-process pitfall
below): scrubbing state shows one full-width thick track with no icons
visible at all; normal state shows both icons back in place with the thin
track between them, matching every prior pass's own verification.

**Icon fade-out re-timed to finish before the move does, not alongside
it**, after the user watched the real animation and noticed the icon was
still partially visible as it crossed into the time-label row — it should
already be invisible by then. `.combined(with:)` by itself runs both
halves of a transition on the *same* ambient animation (the
`.spring(response: 0.25, dampingFraction: 0.75)` from `.animation(value:
isScrubbing)`), so opacity and position reached their end values at
exactly the same moment — the icon stayed part-visible for the *entire*
move, only hitting true `0` right as the move finished (i.e. already past
the bar's top edge). Fixed with `AnyTransition.animation(_:)`, which lets
one half of a combined transition carry its own animation curve,
independent of the ambient one: `.opacity.animation(.easeOut(duration:
0.12))` — opacity now reaches `0` in 120ms regardless of how long the
move itself takes, so the icon is already gone well before it reaches the
time text. Not independently re-verified by screenshot this pass — the
previous/next *settled* states (icon fully visible / fully gone) are
pixel-identical to before, only the *transient mid-animation* frames
differ, and discrete `simctl io screenshot` calls can't reliably capture
an arbitrary animation-in-progress frame the way they can a settled
`@State`-forced state. Confirmed instead that the build succeeds and the
full suite still passes (`AnyTransition.animation(_:)` is a real, stable
public SwiftUI API, not a guess); the actual visual feel is something to
judge live on-device/simulator, same as any other animation-timing
tweak.

**Immediately corrected: giving `.opacity` alone a faster animation was
the wrong read of the ask.** The user clarified they wanted the icon to
*move while fading*, together, not opacity racing ahead of the position —
which is what a solo-animated `.opacity` produces when its duration (0.12s)
is much shorter than the move's own ambient spring: the icon mostly
vanishes in place before it has traveled far, reading as a quick flash-out
rather than a visible slide-and-fade. Fixed by moving the `.animation(_:)`
call to wrap the *entire* combined transition instead of just the opacity
half — `.move(edge: .top).combined(with: .opacity).animation(.easeOut
(duration: 0.18))` — so move and fade now share one curve and one
duration (perfectly synced, like the default `.combined(with:)` behavior),
just a shorter, dedicated one (0.18s) instead of inheriting the bar's
slower ambient spring (0.25s) — still finishing before reaching the
clipped edge near the time text (the original complaint), but without
decoupling the two effects from each other (the overcorrection). Same
verification caveat as above: this is a timing/feel tweak, not something a
settled-state screenshot can confirm — build + full suite pass, actual
judgment is live-only.

**A real environment pitfall hit while verifying this pass, worth
remembering**: forcing `@State` defaults and rebuilding looked like it
*stopped working* mid-session — a rebuilt app kept showing stale UI
(wrong tab selected, wrong bar width) even after a full `rm -rf` of
DerivedData and confirming the new strings were present in the freshly
compiled object file. Root cause: this project's Debug build produces a
`NeonixEditor.debug.dylib` (Xcode's "debug executable as library"
mechanism for Previews' dynamic code injection) — the actual
`NeonixEditor` executable in the `.app` is just a thin stub-executor that
loads that dylib at runtime. `strings`-checking the stub (as earlier
verification passes in this file did, by coincidence without hitting this)
proves nothing about the real code. Worse: a plain `simctl terminate` +
`simctl launch` cycle did **not** reliably cold-start the process while
iterating quickly — stale `@State` initial values kept showing even once
the dylib itself was confirmed correct. Fix: `xcrun simctl shutdown
<udid>` then `xcrun simctl boot <udid>` (full simulator reboot, not just
app terminate/relaunch) before trusting a `@State`-forced visual
verification — this reliably produced a true cold app process in every
case it was tried. See `CLAUDE.md`'s matching entry for the general rule.

## Timeline: CapCut-style filmstrip, fixed center playhead

`TimelineView.swift` redesigned 2026-10-07 after jointly analyzing a CapCut
screenshot with the user before writing any code. Three confirmed changes
from the original flat-color-block version:

1. **Video rows render as a real filmstrip, not a flat color block.**
   `FilmstripClipView` slices the clip into `rowHeight`-wide square tiles
   and decodes the actual frame at each tile's time via
   `VideoFrameCache.shared.frame(assetId:url:atSeconds:)` — the exact same
   cache `PreviewCanvas` already uses for scrub frames, no new decode path.
   Non-video rows (text/audio/shape) keep the original flat-color
   `TimelineClipView` — there's no thumbnail concept for those.
2. **Tiles outside the visible scroll window never decode.** Each tile
   computes its own content-local x-range and checks it against a
   `visibleRange` passed down from `TimelineView`; off-screen tiles render
   a plain gray placeholder and skip the `VideoFrameCache` call entirely
   (`FilmstripTileView`'s `.task(id: isVisible)`). This was a confirmed
   design choice over pre-generating the whole filmstrip up front — cheap,
   reuses the existing cache, and never decodes a long clip's frames that
   aren't even on screen. A freshly-cold-booted device may show a handful
   of still-gray tiles for a second or two right after opening the editor
   (several concurrent `AVAssetImageGenerator` decodes racing) — transient,
   not a bug; confirmed by re-screenshotting a couple seconds later.
3. **The playhead is fixed at the horizontal center of the panel — the
   content scrolls under it, not the other way around.** This is a
   deliberate reversal from the original "static track, moving playhead
   line" model, confirmed with the user against a second CapCut screenshot.
   `TimelineView`'s `DragGesture` no longer computes an absolute
   tap/drag-to-fraction position; it snapshots `currentTimeMs` at drag
   start (`dragStartTimeMs`) and derives a new absolute time from the
   gesture's total translation (`start - translation.width / pxPerMs`),
   clamped to `[0, maxDurationMs]`. Ruler and tracks share one
   `contentOffsetX = centerX - currentTimeMs * pxPerMs`, applied once to
   their common parent `VStack`, so they can never drift out of sync with
   each other.
   - **Reversed again the same day: the cover-image cell and the mute
     button scroll together with the filmstrip as ordinary content — they
     are not a fixed overlay.** The first version of this pass drew them in
     `PlayheadOverlay`, pinned at screen center regardless of scroll
     position. The user corrected this after a second look at the
     reference: in real CapCut, the mute button, the cover cell, and the
     filmstrip all sit in the *same* scrolling row, at the *same* z-index —
     only the playhead line itself is a fixed overlay. `FilmstripRowView`
     is the result: one `HStack` of `[MuteButtonCell, CoverCell,
     FilmstripClipView]` (mute+cover only on the primary video row,
     `showsCoverAndMute`), positioned with a *single* outer offset
     (`layer.timing.start * pxPerMs - prefixWidth`) so the filmstrip's own
     first tile still lands exactly where every other track's timing
     positions it — the mute/cover cells just occupy the extra space
     immediately before that point, and now scroll out of view (clipped by
     the same `.clipped()` as every other track) once `currentTimeMs` moves
     far enough past 0. `PlayheadOverlay` shrank down to just the fixed
     center line. Verified both at rest (`currentTimeMs: 0` — mute+cover
     sit left of the playhead, same as before) and forced to a non-zero
     `currentTimeMs` (1200ms) — confirmed by screenshot that mute+cover
     have scrolled off the left edge along with the earlier ruler ticks, at
     the same rate as everything else.
   - The debug `"<currentTimeMs> / <maxDurationMs> ms"` text row above the
     ruler is gone too — removed at the user's request once the ruler
     itself made it redundant.
   - Both the cover-cell tap and the mute toggle are **placeholders** —
     this editor has no "set cover" screen and (per `VideoFrameCache`'s own
     doc comment) no real audio playback at all yet, so there is nothing
     for either to actually do. `V2VideoPayload.audio.enabled` is the real
     protocol field a future mute toggle should write to once an audio
     engine exists — not wired yet, intentionally.
   - A plain white 2pt playhead line is nearly invisible against this
     panel's own white (`Color(.systemBackground)`) background wherever it
     isn't crossing colored track content — confirmed by screenshot, not
     guessed. Fixed with a wider, semi-transparent black line directly
     behind it (a cheap halo), not by changing the line's own color, so it
     still reads correctly over the filmstrip too.

Gesture live-feel (does a drag actually feel smooth, does the clamp at
0/max feel right) is explicitly **not** verifiable by `simctl` — this
sandbox has no touch injection (see `CLAUDE.md`'s own note on this); the
offset math was instead verified by forcing `currentTimeMs` to a non-zero
`@State` default and screenshotting, confirming the ruler ticks and the
filmstrip shift together by the same amount while the cover cell/mute
button/playhead stay fixed at center — the user should still judge the
actual drag feel live.

4. **Ruler+filmstrip pin to the top of the timeline panel, not centered in
   it.** `TimelineView`'s `timelineHeight` (whatever's left over after
   Stage+Titlebar, see this file's own Layout section above) is almost
   always taller than the ruler+track content actually needs — a plain
   `VStack` with one fixed-height child centers that child by default once
   given more height than it needs, which left a visible gap *above* the
   ruler too (not just below), unlike CapCut's own layout where the
   ruler+filmstrip sits flush under the titlebar divider. Fixed with
   `.frame(maxHeight: .infinity, alignment: .top)` on the outer `VStack`
   (plus trimming the padding to `.top` only) — confirmed by screenshot
   that the ruler now starts right under the `Divider()`, with all the
   leftover blank space pushed below instead of split above/below.

## Bottom tool nav: CapCut layout, app's own light chrome

Re-added 2026-10-07 — this row existed once, got removed entirely in an
earlier redesign pass (see "The real Editor screen is being built as a
shell first" in `CLAUDE.md`), and the user explicitly asked to bring it
back "giống CapCut." Before writing any code, 3 questions were raised and
confirmed with the user (not assumed):

1. **Color theme: the app's own light/system-dynamic chrome, not CapCut's
   dark theme.** `CLAUDE.md` already has a standing rule locking this
   screen's nav/chrome to system dynamic colors (matching the real iOS
   Photos editor) — the CapCut reference screenshot is dark, which would
   have directly contradicted that rule if copied verbatim. Confirmed:
   borrow CapCut's *layout* (icon above label, horizontal scroll) only, not
   its palette. `EditorToolbarView.swift` uses `.primary`/`.accentColor`/
   `Color(.systemBackground)` throughout, no hardcoded black/white.
2. **Tool order matches CapCut's own order**, not the order `EditorTool.swift`
   happened to declare cases in before. New order: Chỉnh sửa, Âm thanh, Văn
   bản, Hiệu ứng, Tỷ lệ khung hình, Phông nền, Tuỳ chỉnh — `adjust` sits
   last since it's standing in for "Bộ lọc"'s slot (see `EditorTool.swift`'s
   own doc comment on why "Tuỳ chỉnh" replaces "Bộ lọc"), which in CapCut's
   real nav comes later than the other 6 kept tools.
3. **Tapping only highlights the tool, nothing else opens.** No per-tool
   screen exists for any of the 7 (that's real, separate, not-yet-started
   work — see `EditorTool.swift`). Building 7 placeholder sheets was
   explicitly out of scope for this pass; `selectedTool` just drives which
   icon/label turns `.accentColor`, and tapping the already-selected tool
   clears it back to `nil` — "nothing selected" needed to stay a reachable,
   honest resting state given there's genuinely nothing to show either way.

**Layout integration**: `EditorShellView.windowedShell` now reserves a
fixed `toolbarHeight: CGFloat = 64` (no `PreferenceKey` measurement needed,
unlike `controlsRow`'s `titlebarHeight` — this row's content is fixed-height
by construction, nothing to measure) and subtracts it from `timelineHeight`
alongside `titlebarHeight`/`stageHeight`, with a second `Divider()` between
Timeline and the new toolbar. Verified on the simulator: all 3 sections
(Stage/Titlebar, Timeline, toolbar) render without clipping or overlap, in
the new CapCut order, light chrome — confirmed by screenshot.

**`rowHeight`/`toolbarHeight` follow-up tweaks (2026-10-07/08)**, both
direct requests, no further design discussion needed: `TimelineView`'s
`rowHeight` 40 → 48pt; `toolbarHeight` 64 → 58pt alongside the toolbar's own
icon size stepping down one SF text style (`.title3` → `.body`).

**"Bộ lọc" added as an 8th tool, 2026-10-08** — once `feColorLUT`/
`V2LutAsset` existed (see CLAUDE.md), the original reason "Bộ lọc" was
excluded ("needs a new Protocol V2 primitive") no longer applied. Explicitly
scoped to **UI only** by the user ("thêm bộ lọc để đủ chưa cần code tính
năng, mục tiêu là dựng UI trước") — placed after "Hiệu ứng" (matching
CapCut's own order), `camera.filters` icon, same tap-to-highlight/no-screen
placeholder behavior as every other tool. "Tuỳ chỉnh" no longer needs to be
framed as standing in for "Bộ lọc"'s nav slot (that framing predated this
addition) — they're simply two separate, correctly-distinct tools now, a
LUT preset picker vs. manual HSL/tone sliders, same as real CapCut.

## Playhead and drag surface now span the timeline's *full* height, not just the ruler+tracks' own content height

Fixed 2026-10-08, direct user report: "phải click đúng vào track film thì
mới scroll được" — dragging only scrubbed when the touch landed exactly on
the ruler/filmstrip block, not anywhere else in the timeline panel (the
usually-much-taller blank space below it, down to the bottom toolbar, did
nothing), and the playhead line visibly stopped partway down instead of
reaching the bottom.

**Root cause**: `TimelineView`'s `GeometryReader` had its own
`.frame(height: panelHeight)` — `panelHeight` is just the ruler+tracks'
own content height (`rulerHeight + rowsTopPadding + tracksHeight`), almost
always smaller than the full `timelineHeight` `EditorShellView` actually
hands this view. Both the playhead (`PlayheadOverlay`'s `totalHeight`) and
the drag gesture's hit area (`.contentShape(Rectangle())`, which takes its
size from the `ZStack` it's attached to) were sized off that same
`panelHeight` — so neither ever reached past the content's own bottom edge,
even though the panel visually had much more (blank, unreachable) space
below it.

**Fix**: removed the `GeometryReader`'s own fixed-height frame
(`.frame(maxHeight: .infinity)` instead, so it fills whatever height its
parent actually gives it — the real `timelineHeight`), and gave the `ZStack`
an explicit `.frame(width: geo.size.width, height: geo.size.height,
alignment: .topLeading)` so both `.contentShape`/`.gesture` and
`PlayheadOverlay`'s `totalHeight` now read the GeometryReader's full,
correct height instead of the content-only `panelHeight`. The ruler+tracks
content itself is unaffected — it still renders at its own `panelHeight`,
top-aligned, same as before; only the *interactive/visual extent* of the
playhead and drag surface grew to match the whole panel. Confirmed by
screenshot: the playhead line now visibly reaches all the way down to the
bottom toolbar's divider, not stopping partway. The drag area itself can't
be screenshot-verified (`simctl` has no touch synthesis — see `CLAUDE.md`),
but it's driven by the exact same `.frame()` call the now-correctly-full-height
playhead line is, so confirming the line's extent is a reliable proxy for
confirming the gesture surface's extent too, not a separate guess.

## Timeline lanes implementation — `LaneRowView` replaces 1-row-per-layer

Implemented 2026-10-08, the UI half of the "Timeline lanes" architecture
decision in `CLAUDE.md` (read that first for the *why* — this section is
just the *how* on the `TimelineView.swift` side).

`TimelineView` no longer renders one row per `V2Layer`. It groups `layers`
by `order` into lanes (`laneOrders: [Int]`, `lane(for:)` — a `Dictionary`
grouping, sorted ascending), and `LaneRowView` renders *one lane* (a
`[V2Layer]`, already sorted by `timing.start`), not one clip. Each clip
inside a lane positions itself independently — `FilmstripClipView` got its
self-offset (`.offset(x: timing.start * pxPerMs)`) back (it had been
removed when the old `FilmstripRowView` briefly centralized positioning
into one shared offset for mute+cover+clip together, back when a lane could
only ever hold exactly one clip) — since a lane can now hold several
non-overlapping clips, each needs its own independent screen position, not
one offset shared by the whole row. The cover cell + mute button now
anchor off the *lane's earliest clip* (`clips.first?.timing.start`, lanes
are pre-sorted) rather than "the one clip this row has."

**Verified with a temporary hand-built fixture** (`ProjectsView.swift`,
reverted after confirming): 3 non-overlapping video clips sharing
`order: 0` (0–2000ms, 2000–4000ms, 4000–6000ms, same bundled asset) plus 1
image layer at `order: 1` (500–2000ms). Screenshot confirmed: all 3 video
clips rendered in one continuous lane (one mute button, one cover cell, 3
filmstrips sitting edge-to-edge with no gap — exactly what adjacent,
non-overlapping same-lane clips should look like), and the image layer got
its own separate row below, correctly *not* carrying a cover/mute cell
(that's gated to the primary video lane only). This is the only kind of
scenario `simctl` *can* verify (a settled visual state) — the eventual
lane-packing algorithm itself (CLAUDE.md's greedy interval-packing note)
isn't implemented yet, since no multi-clip authoring commands exist yet to
drive it; this fixture only proves the *rendering* side (`LaneRowView`
correctly handling a lane that already has multiple clips) works.

## Waveform indicator on the video clip — "attached audio," no new lane

Implemented 2026-10-08, the first piece of the audio design discussion in
`CLAUDE.md` (read that first — it covers the attached/detached model this
is one half of). `WaveformCache.swift` (`Runtime/`) is a new cache,
parallel to `VideoFrameCache`/`BundledImageCache`: decodes a file's raw PCM
samples via `AVAssetReader` (16-bit linear PCM output settings — the
simplest format to walk byte-by-byte), reduces them to a 600-bucket
peak-amplitude envelope, and caches that envelope keyed by file URL (not
asset id — `V2VideoAudioDerivative` has no id of its own, just a `uri`).
Decoding runs via `Task.detached(priority: .utility)`, same discipline
`VideoFrameCache` already established for video frame decoding: a
multi-megabyte file's PCM decode is real, blocking work that must never
run on the main/render-loop thread.

`TimelineView.audioDerivativeURL(for:)` looks up a video layer's own asset,
checks whether it's a `.video` asset with a non-nil `audio` derivative, and
resolves that derivative's `uri` to a bundled file URL — this is the
"attached audio" read path the audio design note describes: no new
`V2Layer`/lane, just a lookup against data the schema already had.
`FilmstripClipView` draws the result (`WaveformStripView`/
`WaveformBarsView`, a `Canvas` bar chart) along the clip's own bottom edge,
*inside* its existing `rowHeight` bounding box — deliberately not a taller
row, to avoid reworking every lane's height math for the one row type that
happens to have audio. Doesn't yet account for `trimStart`/`trimEnd` (always
shows the whole derivative file stretched across the clip) — a known,
documented simplification, not an oversight.

**Verified with a temporary fixture** (`ProjectsView.swift`, reverted after
confirming): a video asset's `audio` derivative pointed at a real
user-provided file (`Resources/Media/audio-demo.mp3`, ~6.5MB, ~4.4 minutes).
Confirmed via screenshot: a real, non-uniform waveform shape renders along
the clip's bottom edge, not a placeholder bar.

**A real debugging episode worth remembering**: the feature first appeared
to do nothing — screenshot taken a few seconds after launch showed no
waveform at all. `NSLog` (temporary, removed once confirmed — see
`CLAUDE.md`'s own established methodology for this: a UI test's/app's
logs don't flow through `print()`, only `NSLog` + `log show`) traced it to
a real but harmless cause: decoding this file's ~23 million raw Int16
samples, then doing a second full pass over all of them to build the 600
peak buckets, took **~8.5 seconds** in this Debug (`-Onone`) simulator
build — the screenshot had simply been taken too early. Letting it run
longer confirmed the waveform does render correctly once decode finishes.
**Not optimized further** — a two-pass (`copyNextSampleBuffer` into one
big array, then a second peak-scan loop over that array) does more
allocation/iteration than strictly necessary (an incremental single-pass
bucket-fill while reading would avoid ever materializing the full sample
array), but this was left as-is rather than fixed speculatively: the
result is correct and this is a one-time-per-file decode that gets cached
forever after, Release builds are meaningfully faster than this `-Onone`
measurement, and the user's actual ask was the visual feature, not decode
performance. Worth revisiting if a real multi-minute audio file in the
actual product ever makes this a felt problem.

## Standalone audio lane + "Trip to Paris" demo content, persisted (not reverted)

Added 2026-10-08, at the user's explicit request to leave this in place so
they can manually try the Timeline themselves (unlike every other fixture
in this file, which was reverted after a screenshot confirmed it).

**`TimelineView` gained a real standalone-audio-track rendering path** —
until now, only "attached" audio (a video's own embedded-audio waveform,
drawn along the clip's bottom edge) existed; nothing read
`V2AudioDomain.tracks[]` at all. `AudioTrackRowView`/`AudioClipView` render
one row per `V2AudioTrack`, each clip a purple block reusing the exact same
`WaveformCache`/`WaveformBarsView` mechanism the attached-audio indicator
already uses (`WaveformBarsView`/`WaveformStripView` gained a `color`
parameter so the two cases can look different — white-on-dark for attached,
purple for standalone — instead of hardcoding one color). Audio tracks are
a wholly separate section, appended after the visual lanes, never folded
into `order`/lane grouping — matching the explicit scope boundary from
CLAUDE.md's "Timeline lanes" note (audio was deliberately excluded from
that design). `EditorShellView.maxDurationMs` now also considers audio
clip end times, not just layer end times, so the ruler/content width
actually covers a standalone track that outlasts every visual layer.

**"Trip to Paris" (`ProjectsView`'s 9:16 sample) now carries real demo
content** — `ProjectsView.openEditorProject(for:)` replaces the old plain
`compile(EditorDemoView.makeDocument(...))` call for this one sample (the
other 2 samples are untouched): the compiled video layer's duration is
stretched to 8000ms (from the demo's own default 2500ms) so there's room
to see 3 lanes diverge/overlap; a text lane ("Trip to Paris", 1000–4000ms)
is compiled through a *second*, separate `compile(_:)` call (its own
`EditorDocument` with one text `EditorLayer`) specifically so the real
`TextLayoutCompiler`/`PresetCompiler` pipeline produces a valid
`V2TextLayerPayload` — hand-building that struct directly would have
meant constructing `V2TextSource`/`V2TextChunk`/`V2TextSpan`/`V2TextFont`
by hand, exactly the kind of low-level JSON shape the compiler exists to
spare callers from; its one resulting layer gets `order = 1` assigned
afterward (`compile(_:)` has no lane concept, every layer defaults to
`order: 0`); a standalone `V2AudioClip` (0–8000ms) references a new
`.audio` asset pointing at `Resources/Media/audio-demo.mp3` (the same file
the waveform-indicator feature was verified against).

**Verified on the simulator** (temporarily forcing `RootTabView.selection`/
`ProjectsView.openedProject` to jump straight to "Trip to Paris", reverted
after confirming — only the debug-state toggles were reverted, the demo
content itself stays): all 3 lanes render — video filmstrip, orange text
lane (and the text itself renders live on Stage, confirming the compile
pipeline produced a real, correct payload, not just a Timeline-UI
placeholder), and the purple standalone-audio lane with a real decoded
waveform (same ~8s first-decode delay as the embedded-audio case — see
that section above, same known characteristic, same file).

## Only the main lane gets full `rowHeight` — every other lane/track is half as tall

Changed 2026-10-08, direct request. `TimelineView.rowHeight` (48pt) now
applies only to the primary video lane; `otherRowHeight` (`rowHeight / 2`,
24pt) applies to every other visual lane *and* every standalone audio
track row — matching CapCut's own visual hierarchy (one prominent main
row, everything else secondary/thinner). `tracksHeight` had to stop being
a flat `rowCount * rowHeight` and instead sum the main lane's height (if
one exists) plus `otherRowHeight` for every remaining row. `isMainLane`
(`order == primaryVideoLaneOrder`) now picks which height to hand each
`LaneRowView`; `showsCoverAndMute` and `isMainLane` are the same condition,
so the cover/mute cells (only ever rendered on the main lane) still always
receive the full `rowHeight`, never the halved one. Verified on the
simulator ("Trip to Paris"): the video lane stays full-height filmstrip
tiles, the text and audio lanes both render visibly thinner, same height
as each other.

## Waveform redesign: smooth one-sided curve, not discrete bars

Changed 2026-10-08, after jointly analyzing a reference image with the
user before writing any code (a stock "sound wave" icon — symmetric,
densely-packed thin bars). Clarified in discussion that the reference's
*literal* bar shape wasn't actually what was wanted — the ask was a real
smooth graph-style curve ("mượt mà kiểu đồ thị... không bị thành từng
thanh"), plus a *separate* request to stop drawing the wave mirrored
around a center line and show only one side, since these rows are short
(22-26pt) and a symmetric wave wastes half that height for no benefit.

`WaveformBarsView` → `WaveformCurveView`: draws a real Catmull-Rom spline
(converted to cubic Bezier segments per point, the standard technique for
passing a smooth curve through an ordered sequence of points without the
wild overshoot a naive interpolation would produce) through the sample
envelope, fills the area beneath it, and strokes the curve itself on top
for definition — a real area-graph, not bars. One-sided: amplitude 0 sits
on the view's own bottom edge, amplitude 1 reaches the top, using the
*full* height for the one direction instead of splitting it between a
mirrored top and bottom half.

Confirmed with the user: once the wave is one-sided, the old 22pt
height-with-margin trick (added specifically to keep the old symmetric
wave from touching the row's edges) no longer serves any purpose —
`AudioClipView` now gives the waveform the *full* `rowHeight` directly,
anchored flush at the bottom, no inner/outer nested frame needed anymore.
Point density also dropped (`clipWidth / 3` → `clipWidth / 8`) — a smooth
spline through too many closely-spaced points from a noisy envelope looks
jittery rather than smooth; fewer, more spread-out points let the Bezier
smoothing actually read as a flowing curve.

Verified on the simulator ("Trip to Paris"): the standalone audio lane
renders a real filled curve — a short rise at the clip's very start (the
file's quiet intro, same region the old bar chart showed as several short
bars) followed by a tall plateau (the file is loud/compressed for most of
its length, a real characteristic measured back when the waveform feature
was first verified, not new). Same `WaveformCurveView` renders the
embedded-video-audio indicator on `FilmstripClipView` too — one mechanism,
both call sites, no separate code path for the two cases.

## Correction: the one-sided wave keeps the *old* half-height proportion, not the full row

Fixed 2026-10-08, right after the wave redesign above — a real
misunderstanding worth recording, not just a tweak. "Splitting the wave in
half" had been implemented as *stretching* the one remaining side to fill
the whole row (amplitude 1 → the row's very top edge). The user's actual
intent: literally cut the old symmetric wave in half and keep what's left
at its *original* proportions — the visible half should still only occupy
half the row's height, same scale as before, just not mirrored anymore.
`AudioClipView` now sizes the curve to `rowHeight / 2`, bottom-aligned
inside the full `rowHeight` box, leaving the top half showing the row's
plain background tint.

Verified by direct pixel sampling (a screenshot crop looked ambiguous at
this scale) — in the plateau region, measured background-tint height above
the wave (~13pt) almost exactly equals the wave's own height (~13pt), each
half of the real 26pt row height, confirming the fix lands exactly on the
intended 50/50 split rather than relying on a visual guess.

## Peak amplitude caps at 80% of its box, and the audio lane's color is cyan, not purple

Changed 2026-10-08, matching how other NLEs (Premiere, Final Cut, CapCut)
actually render waveforms — the user observed their loudest peaks top out
around 80%, not 100%, of their own display height. `WaveformCurveView`
gained a `peakFraction = 0.8` multiplier on the amplitude→height mapping,
so the curve never touches the very top of whatever box it's drawn in
(standalone audio lane or the embedded video-audio strip, same mechanism,
both affected) — matters most for already-loud/compressed source audio
(a real, common case, not a corner case: the demo file used to verify this
whole feature is one), which would otherwise sit flush against the top
edge for nearly its whole length and read as "clipping."

Color: the user wanted audio closer to blue than purple, but `.blue` is
already `FilmstripClipView`'s own border color for the video lane — reusing
it for audio would make the two lane types read as the same color, losing
the whole point of per-type lane coloring. Picked `.cyan` instead (same
"blue family" request, still visually distinct from the video lane) and
said so before changing it, rather than silently picking a color that
happened to collide with an existing one. Applied to `AudioClipView`
(fill/stroke/icon/waveform color) and `TimelineClipView`'s `"audio"` case
(kept in sync even though no real `V2Layer.type == "audio"` renders through
it today — audio lives in `V2AudioDomain`, not `layers[]`).

## Synthetic peak-test audio file, for verifying the 80% cap deterministically

Added 2026-10-08. The real demo file (`audio-demo.mp3`) is loudness-
maximized for nearly its whole length (a real, previously-noted
characteristic), which made it a poor file to visually confirm the new
80%-peak-cap against: most of it already sits near the digital ceiling, so
there was no visible contrast between "the cap kicked in" and "this is
just how loud the file is." `WaveformCache` normalizes each bucket's peak
against the absolute digital ceiling (`Int16.max`), not the file's own
loudest moment — so a file without genuine full-scale samples would never
visibly reach the cap at all, which the file's actual nature couldn't
demonstrate either way.

`Resources/Media/audio-peaktest.wav` (generated with a small Python script,
`wave`/`struct` from the standard library, no external tools needed) is an
8-second mono 16-bit/44.1kHz tone with 7 segments ramping amplitude
0% → 20% → 50% → **100%** (2s, held) → 50% → 20% → 0%, built specifically so
a real full-scale (0dBFS) sample is guaranteed to exist. Verified by
temporarily swapping it into the "Trip to Paris" audio asset (reverted
after confirming): the rendered curve's plateau during the 100% segment
landed at pixel y-coordinates matching the exact predicted math (half-row-
height box × 0.8 peak fraction = 40% of the full row height) to within
1px — a precise confirmation, not just "looks about right." Kept in the
bundle as a reusable test asset for future waveform-rendering verification,
not deleted after this one check.

## Waveform disk cache — survives app relaunch, not just in-memory for one session

Added 2026-10-08, direct user request after asking whether waveform
decoding was being persisted across project loads (it wasn't — see
`CLAUDE.md`'s own note on this, same entry covers the design reasoning).
`WaveformCache` gained a disk-backed tier in `Caches/WaveformCache/`,
keyed by **filename only** (not the full `URL.absoluteString` the
in-memory cache used before) — a sandboxed app's container path changes
every install/relaunch (a fresh UUID each time), so the old full-path key
would never again match a previous run's cache file; bundled resource
filenames are already unique (flattened at the bundle root), so the
filename alone is the correct, stable key. Stores raw `Float` bytes
directly (no JSON) — this is a private cache file nothing else reads, so
there's no reason to pay text-encoding overhead for it.

**Verified end-to-end, not just "should work"**: temporary `NSLog`
instrumentation (same established method as the original waveform-decode
debugging this session) confirmed the actual sequence — first launch
(after `simctl erase`, a genuinely fresh container): `miss, decoding` →
`decoded+wrote`. Second launch (`simctl shutdown`+`boot`, **no reinstall**,
simulating "close the app, restart the phone, reopen it"): `disk-hit
count=601`, instant, no redecode. This is the real scenario the feature
exists for — confirmed, not assumed from reading the code.

## Clip selection + Chỉnh sửa (Tách/Xoá) — Phase 2 of the "Bottom nav tools" roadmap

Added 2026-10-08, see `CLAUDE.md`'s own note for the Command-level
rationale (`SplitClipCommand`/`DeleteClipCommand`). This entry covers the
Timeline-specific UI pieces: how a clip gets selected and how the
selection reads visually.

**Selection model**: `EditorShellView` owns `@State selectedLayerId:
String?`, passed to `TimelineView` as a `Binding`, threaded down to
`LaneRowView` (`selectedLayerId`/`onSelectLayer`), which attaches
`.onTapGesture { onSelectLayer(layer.id) }` to each clip
(`FilmstripClipView` for video, `TimelineClipView` for everything else).
Tapping the already-selected clip deselects it (toggle, not a one-way
select) — `onSelectLayer`'s own closure in `EditorShellView`:
`selectedLayerId = (selectedLayerId == id) ? nil : id`. Only `layers[]`
clips are selectable this pass — the standalone audio lane
(`AudioTrackRowView`/`AudioClipView`) deliberately has no tap gesture,
since editing audio clips belongs to the later Âm thanh phase, not
Chỉnh sửa.

**Selection highlight (superseded same day — see the drag-to-trim entry
below)**: the first version of this added a
`RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2.5)`
overlay on top of the clip's existing type-color stroke. **Verified two
ways** before being replaced, not just visually: (1) temporary `NSLog`
instrumentation in `FilmstripClipView.body` confirmed `isSelected=true`
actually reaches the view for the forced-selected layer id; (2) a
temporary oversized (12pt) red debug stroke, swapped in for the real white
one, rendered clearly on screen — proving the `.clipShape(...).overlay(...)`
mechanism itself works on this view, before it was repurposed for the
handles below. Kept this paragraph rather than deleting it — the
verification method (NSLog + an oversized debug-colored swap to prove an
`.overlay` renders at all) is reusable and worth remembering independent
of which specific overlay it was applied to.

**Edit panel** (`ToolOptionsPanel`'s `.edit` case, `EditOptionsRow`): shows
a hint text ("Chọn 1 clip trên timeline để chỉnh sửa") when nothing's
selected, or Tách (split, scissors icon)/Xoá (delete, trash icon,
`.destructive` role) once a clip is selected. Tách is disabled whenever
the playhead sits at or outside the selected clip's own time range
(`canSplit`) — splitting exactly at an edge would produce a zero-length
half, so the button simply doesn't invite that rather than the command
needing to reject it after the fact.

## Drag-to-trim handles + no-default-border clips — analyzed against a CapCut reference screenshot

Added 2026-10-08, same day as clip selection above, replacing its white-
stroke selection highlight. The user sent a CapCut screenshot and asked to
analyze it together before coding: a selected clip there grows two white
handle bars at its own left/right edges (for trimming) instead of a
border, the area between them washes lightly brighter ("đang ở chế độ
chỉnh sửa"), and an *unselected* clip is just a flat color block — no
border at all, for video **or** text/audio.

**Border removal** (confirmed explicit ask: "mặc định xoá hết viền
border... chỉ có 1 khối màu"): `FilmstripClipView`'s permanent
`Color.blue` 1pt stroke, `TimelineClipView`'s per-type-color 1pt stroke +
0.18-opacity fill, and the standalone-audio-lane `AudioClipView`'s cyan
1pt stroke are all gone. `TimelineClipView` now fills with the full
type color (not translucent) and switched its icon/label to white, since
a solid color block needs a light foreground to stay readable, matching
the reference screenshot's solid orange "Aa" block exactly.
`AudioClipView`'s fill went from 0.18 → 0.45 opacity — a touch more
opaque to read as a block, but still translucent enough that the
waveform drawn on top of it stays visible (a genuinely solid fill would
wash the waveform out).

**Drag-to-trim scope, confirmed with the user via `AskUserQuestion`
before building**: should an *extend* drag (making a clip longer, not
just shorter) be capped at the clip's own current `timing`/`trimStart`/
`trimEnd` range (simpler, no asset-duration lookup needed), or be allowed
to reveal more of the real source footage up to the asset's actual
duration (matches real CapCut, needs an async duration lookup to clamp
against)? **The user chose the real-CapCut behavior** — extending is
allowed up to the asset's own total duration, not just the currently-used
range.

- **`AssetDurationCache`** (`Runtime/`, new file): the one new piece this
  choice required — an in-memory-only (no disk tier, unlike
  `WaveformCache`; a single `AVURLAsset.load(.duration)` call per video is
  cheap enough not to bother persisting) cache of a video asset's real
  total duration, keyed by filename. `FilmstripClipView` loads it via
  `.task(id: isSelected)` once a clip becomes selected; if it hasn't
  resolved yet, an extend-right drag just isn't clamped further than
  whatever's already known — "fail closed to a no-op," this app's
  standing convention, rather than guessing or blocking the drag entirely.
- **`TrimHandleView`** (shared by `FilmstripClipView`/`TimelineClipView`):
  a narrow (4pt) white rounded bar sitting inside a wider (20pt)
  invisible tappable area, so a finger doesn't need to land pixel-
  perfectly on the thin visible bar — only rendered at all when
  `isSelected`, at `.overlay(alignment: .leading/.trailing)`. The "active"
  wash between the handles is `Color.white.opacity(0.15)` over the whole
  clip.
- **Drag math, both handles, same shape for video and non-video clips,
  the only difference being whether `trimStart`/`trimEnd` exist to
  clamp against**: each handle's `DragGesture` snapshots the clip's own
  layer state into `@State dragStartLayer` on its *first* `onChanged`
  tick (same "capture the pre-drag origin once, compute every subsequent
  tick as an absolute delta from it" pattern `TimelineView`'s own
  scrub-drag already established — never an incremental per-tick delta,
  which would drift). Left handle moves the clip's *start* while its end
  stays fixed (for video, walks `trimStart` — floored at 0, the one real
  "can't reveal footage before the asset's own beginning" limit); right
  handle moves the *end* while start stays fixed (for video, walks
  `trimEnd`, ceilinged at `assetDurationMs` once known). Both guard
  `newDuration >= 200ms` and simply stop updating (not crash, not partially
  apply) if a further drag would shrink past that floor.
- **Undo collapses one whole drag into a single step**, not one per pixel
  moved: `EditorShellView` gained `beginTrim()`/`updateTrim(_:)`/
  `endTrim()` — `beginTrim()` (called once, on the gesture's first
  `onChanged`) snapshots the pre-drag `project` into `trimDragOriginal`;
  every subsequent tick calls `updateTrim(_:)`, which applies the new
  `TrimClipCommand` directly to `project` *without* touching
  `history`; `endTrim()` (on `onEnded`) records that one pre-drag snapshot
  into `history` and clears `trimDragOriginal`. This is a different shape
  from every other Command in this app (`apply(_:)` normally records
  *and* applies together) specifically because a drag produces dozens of
  intermediate states that should never each be their own undo step —
  the same reasoning that already kept `TimelineView`'s own scrub-drag
  out of the undo stack entirely, just applied here to a drag that *does*
  need exactly one undo step at the end, not zero.
- **`TrimClipCommand`** (`EditorCommand.swift`): deliberately does zero
  clamping/validation itself — it just writes whatever `start`/`duration`/
  `trimStart`/`trimEnd` the drag gesture already computed (and already
  clamped) into the target layer. Matches this app's "no ported
  validator, make invalid states unconstructable at the call site instead"
  rule rather than duplicating the clamp logic in two places.

Verified on the simulator (forced `selectedLayerId`/`currentTimeMs`, same
established method): the left handle renders as a correctly-positioned
rounded white bar right at the clip's own left edge; the text block
("Aa Text") and the standalone audio block both render as solid color
with no border, matching the reference screenshot. `EditorCommandTests.swift`
gained `testTrimClipCommandWritesTimingAndVideoTrimFieldsVerbatim`/
`testTrimClipCommandIsNoOpForUnknownLayer`. (The drag-math clamping itself
originally lived only in `TimelineView`'s view code, not unit-testable
without extracting it — since superseded, see the next entry, which
extracted exactly that logic into `reflowLane(...)` and gave it its own
test file.)

## Drag-to-trim v2 — black-bordered handle + lane-wide ripple reflow

Added 2026-10-08, same day, after the user flagged the first version as
"doing the trim wrong" and asked for a restatement of their intent before
any more code — the corrected design below is what that restatement
confirmed (and the 3 remaining ambiguities it raised were each resolved
via `AskUserQuestion` before implementing).

**Handle visual**: `TrimHandleView` gained a `Color.black`, 1pt
`.stroke(...)` around the white bar (previously plain white, which
disappeared against bright video content) — also bumped from 4pt→6pt
visible width and 70%→80% of row height, reading closer to the CapCut
reference. The invisible tap target grew 20pt→24pt to match.

**The real behavior change — lane-wide "ripple" reflow, not just a single
clip's own trim.** The first version only ever touched the dragged clip
itself, with no relationship to its neighbors. Confirmed with the user
(their own words, translated): a video is never really "pushing" its
neighbor directly — the dragged clip is just extending its own duration,
and it's the clips further down the lane that end up repositioned as a
consequence. The corrected model, confirmed one `AskUserQuestion` at a
time:

1. **Cascades the whole lane, not just the immediate neighbor** — extending
   clip A into clip B also pushes C, D, and everything further down the
   lane, each keeping its own `timing.duration` unchanged, only its
   `timing.start` moving. (Rejected alternative: push only B, risking B
   overlapping C — not chosen.)
2. **Shrinking pulls the lane closer**, symmetric with extending — the
   same "always glued, zero gaps" invariant applies in both directions.
3. **The left handle uses the identical push mechanism as the right
   handle** — not a hard stop. This one needed the most unpacking: the
   user's own clarifying example (a clip at 4-6s, dragged to 2-6s) was
   really about confirming that *only the dragged clip's own numbers*
   are what the gesture computes directly; everyone else's reposition is
   a derived consequence of keeping the lane glued, worked out by a
   reflow pass over the whole lane, not a direct "move clip X" instruction
   issued by the gesture. Also confirmed: video has a real asset-duration
   ceiling on how far it can extend; **image does not** (matches
   `TimelineClipView`'s existing no-ceiling behavior, nothing to change
   there).

**This only applies to "push lanes"** — video and image (`isPushLaneType`
in `TimelineView.swift`), i.e. the main-track lane types that must never
show a gap. Text/overlay lanes (gaps allowed) keep the simpler hard-stop
behavior from the first version: a drag just can't cross into wherever a
neighbor already is.

**`reflowLane(laneClips:draggedLayerId:newDraggedStart:newDraggedDuration:)`**
(`TimelineView.swift`, changed from `private` to internal specifically so
`LaneReflowTests.swift` could reach it via `@testable import` without a
full gesture/view harness) is the whole algorithm: sorts the lane by
current start, walks forward from the dragged clip gluing each later
clip to the one before it (`start = previous.start + previous.duration`),
walks backward doing the mirror image, then — the one subtlety that took
a worked example to get right — if that backward walk would push the
lane's very first clip below `0`, the deficit gets added back onto
*every* computed start including the dragged clip's own, which is what
makes a clip that already has another clip packed tight in front of it
simply refuse to extend further left (there's no slack to push into
without going negative) while a clip at the very front of its lane (or
one with genuine slack ahead of it) still extends freely. `TrimClipCommand`
gained a `siblingStarts: [String: Double]` field (defaults to `[:]`) to
carry the computed repositions through to the one atomic edit.

**Verified via unit tests, not just reasoning** — `LaneReflowTests.swift`
(new file): forward cascade on extend, forward cascade on shrink
(confirms the "pull closer" symmetry), backward cascade with genuine
slack, and the 0-floor clamp scenario (A packed at 0, B tightly glued
after it, B's left handle tries to go negative — confirms the whole
cascade snaps back to the original positions, not a partial/broken state).
All 4 scenarios matched hand-computed expected values exactly. Full
regression suite (`EditorCommandTests`/`KeyframeSamplerTests`/
`LaneReflowTests`/`ProtocolCodableTests`/`EditorNavigationUITests`) run
and confirmed green afterward.

## Verification

`apps/ios-editor/UITests/EditorNavigationUITests.swift` — real tap-driven
tests (`XCUIApplication`) covering all 3 sample aspect ratios. This is the
only verification method in this project that synthesizes an actual touch;
everything else (`xcodebuild build`, unit tests, `simctl io screenshot`)
can't catch a hit-testing bug like the one above.
