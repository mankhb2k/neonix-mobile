# CLAUDE.md

Working notes for Claude Code sessions in this repo. See `ARCHITECTURE.md`
for the full picture; this file is the short, load-bearing rule list.

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
