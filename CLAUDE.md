# CLAUDE.md

Working notes for Claude Code sessions in this repo. See `ARCHITECTURE.md`
for the full picture; this file is the short, load-bearing rule list.

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

## Key files

- `ARCHITECTURE.md` — full architecture writeup, mobile-first roadmap.
- `packages/motion-protocol/README.md` — the canonical Protocol V2 field
  reference (TS/Zod source of truth for schema shape).
- `apps/ios-editor/` — the Swift vertical slice (Runtime sampler, native
  SwiftUI/AVFoundation renderer, Editor Document + preset compiler demo).
  No Node/pnpm in this sandbox — iOS work is verified via `xcodebuild`
  directly (see inline comments in `apps/ios-editor` for the simulator
  workflow, including the manual `.app` bundle assembly this package format
  needs).
