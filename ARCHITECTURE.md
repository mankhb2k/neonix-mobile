# Architecture

This document captures the architecture agreed on so far for Neonix, a
CapCut-like video editor. **Scope: mobile only, Swift/SwiftUI, for now.**
Windows, Web, and real-time collaboration (CRDT) are deliberately deferred —
named here so they aren't silently forgotten, not designed against yet.

## Goal and current repo state

The core idea: build a strict, renderer-neutral, atomic JSON authoring
format — Protocol V2 — as the semantic substrate for the editor. The editor
(wherever it eventually runs — iOS first, possibly Windows/Web later) issues
commands that describe effects, animations, and in/out transition templates;
those commands resolve down to Protocol V2 JSON. That JSON, not any
particular editor's in-memory state, is what a compiler and renderer consume.
The win: the same semantic data can, in principle, drive a renderer on any
platform without being tied to iOS/Swift specifics.

Today only `packages/motion-protocol` exists — a TypeScript/Zod package
defining Protocol V2 and generating its JSON Schema (`schema/v2.json`). There
is no app yet, and no compiler yet. Everything below is the target shape for
what comes next.

## Two-tier document model

Two different things both get called "the project," and keeping them
separate is the central architectural decision here:

- **Protocol V2** (`packages/motion-protocol`) — renderer-neutral, pure
  SVG-semantic JSON. Source of truth for **rendering, export, and
  portability**. It never contains editor concepts like named presets,
  undo history, or command metadata — only flattened geometry, paint,
  transforms, typed animation tracks, and timing.
- **Editor Project** (not yet built; lives with the iOS app) — source of
  truth for **authoring**. Holds command/undo history and preset/template
  bindings, e.g.:
  ```json
  { "layerId": "title-1", "presetId": "slide-in-left", "params": { "durationMs": 400 }, "generatedTrackIds": ["move-x", "fade-in"] }
  ```

Protocol V2 is **derived/compiled** from the Editor Project, not the only
persisted document. When a user re-edits a preset's parameters (e.g. changes
a slide-in's duration), the Editor Project knows which generated tracks that
preset owns (`generatedTrackIds`) and regenerates just those, re-emitting the
affected part of the Protocol V2 document — it never has to reverse-engineer
intent from flattened keyframes.

## Command pattern, not JSON Patch or CRDT

Edits are modeled as typed **commands**, not raw JSON Patch diffs, and not
CRDT operations:

- A command captures user *intent* (e.g. "apply slide-in-left to layer X with
  these params"), not just a before/after diff. Intent is what the Editor
  Project needs to keep presets re-editable (see above), and what undo/redo
  needs to operate on the right grain — the user undoes "the action," not an
  arbitrary field-level patch.
- Commands mutate a **fast in-memory draft** synchronously, so real-time
  timeline scrubbing and dragging stay responsive. Full
  `MotionProtocolV2Schema.parse()` validation (strict, with the cross-field
  `superRefine` checks in `project.ts`) only runs at **commit checkpoints**:
  drag-end, autosave, export. Running that validation on every frame of a
  drag would be wasteful and isn't needed for a local, single-user editor.
- Undo/redo stores `{command, inverseCommand}` pairs.
- **CRDT is explicitly deferred.** It only pays for itself once real-time
  multi-device collaboration is an actual requirement — not today, with a
  single native iOS app. If that need arises later, commands can be
  translated to CRDT ops at a sync boundary without redesigning the editor
  around CRDT from day one.

## Preset/template layer

Animation presets and transition templates (fade/slide/zoom/rotate in-out,
flips, decorative loops) are an **Editor-layer concept only**. Protocol V2
stays ignorant of "preset" as a concept — this is what keeps it portable: any
future renderer only needs to understand flattened SVG-ish primitives, never
app-specific template names.

Applying a preset is a command whose high-level intent
(`presetId` + `params`) resolves into concrete Protocol V2 tracks/effects.
This depends on Protocol V2 actually being able to express those presets
losslessly and trim-safely, which is why the current protocol redesign work
matters:

- **End-anchored keyframe times** (`{ "anchor": "end", "offsetMs": ... }`) —
  an out-animation stays correctly placed after a clip is trimmed or
  extended, without the editor recomputing absolute keyframe times.
- **A normative spec for looping/iterated tracks** (`track.animation`) —
  decorative loop presets (spin, pulse, breathe) have deterministic,
  cross-platform-consistent behavior.
- **Animatable `transform.operations[]` / 3D extensions** — flip, perspective,
  and other 3D preset animations are structurally expressible, not just the
  compact component transform fields.

(One further gap — stacking multiple independent tracks on the same property
path with a compose/blend mode, e.g. an "in" animation and a decorative loop
both touching `opacity` independently — is explicitly deferred as advanced
compositing, not required for basic presets.)

## Swift/iOS integration strategy

TypeScript/Zod remains the **single canonical schema source** — not
reimplemented in Swift:

- Swift gets **generated `Codable` mirror types** from `schema/v2.json` (e.g.
  via a JSON-Schema-to-Swift generator), not hand-written structs. This keeps
  the wire shape from drifting between the two languages as the schema
  evolves; regeneration is a build step, like `check:schema` already is for
  the JSON Schema artifact.
- The deep cross-field semantic validation in `project.ts`'s `superRefine`
  (unique IDs, reference resolution, order uniqueness, track-path/kind
  matching, keyframe bounds) is **not** re-implemented in Swift. Instead:
  - Editor commands are designed so invalid states are **impossible by
    construction** (e.g. a command that deletes a paint server always clears
    references to it; a command that reorders layers always reassigns unique
    `order` values).
  - The canonical TS validator (`MotionProtocolV2Schema.parse`) runs in
    CI/dev tooling against JSON exported from the Swift app, as the
    drift-detection backstop — not as an on-device dependency.

## Planned pipeline

```text
Protocol V2 JSON
      |
      v
motion-compiler       (not built yet)
      |
      v
Runtime V3 IR         (not built yet)
      |
      v
native platform renderer / export renderer   (not built yet)
```

`motion-compiler` lowers Protocol V2 into a resolved Runtime IR: units and
percentages resolved, font fallback resolved, filter graphs flattened,
`offset-path`/CSS motion-path semantics resolved, and animation/stagger
expansion (e.g. `expandTextRangeSelectors` for per-character stagger text)
performed. Runtime IR is what the on-device native renderer (and later
export renderer) actually consumes — Protocol V2 itself is never rendered
directly. On iOS, "native renderer" means whatever native framework fits
each layer type (SwiftUI, Core Animation, Core Graphics, AVFoundation, etc.)
— no third-party rendering engine is part of this architecture.

## Mobile-first roadmap

1. **Protocol V2 redesign** (in progress) — the track/animation gaps above.
2. **`motion-compiler`** — Protocol V2 → Runtime V3 IR.
3. **iOS app shell** — SwiftUI project, generated Codable mirror types,
   native rendering (SwiftUI / Core Animation / Core Graphics, whichever
   fits each layer type).
4. **Command layer + Editor Project format + preset library**, in Swift.

Windows, Web, and real-time collaboration are out of scope until the mobile
pipeline above is working end to end.
