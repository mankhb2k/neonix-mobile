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

## Verification

`apps/ios-editor/UITests/EditorNavigationUITests.swift` — real tap-driven
tests (`XCUIApplication`) covering all 3 sample aspect ratios. This is the
only verification method in this project that synthesizes an actual touch;
everything else (`xcodebuild build`, unit tests, `simctl io screenshot`)
can't catch a hit-testing bug like the one above.
