import CoreGraphics
import Foundation

/// Resolves a named easing shorthand (`PresetBinding.easing`) into the
/// literal `V2Easing` Protocol V2 actually stores. The curve constants
/// match the standard CSS `ease-in`/`ease-out`/`ease-in-out` keywords —
/// `nil`/`"linear"`/anything unrecognized resolves to `nil` (the schema's
/// own linear default), matching how every preset keyframe behaved before
/// this field existed.
func resolveEasing(_ name: String?) -> V2Easing? {
    switch name {
    case "easeIn": return .cubicBezier(x1: 0.42, y1: 0, x2: 1.0, y2: 1.0)
    case "easeOut": return .cubicBezier(x1: 0, y1: 0, x2: 0.58, y2: 1.0)
    case "easeInOut": return .cubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1.0)
    default: return nil
    }
}

/// The 6 basic in/out presets: Fade, Slide, Zoom, each with an `in` and
/// `out` variant. Returns one or more `(path, keyframes)` pairs — Zoom
/// drives both `transform.scale.x` and `transform.scale.y`.
///
/// `out` keyframes are both end-anchored (`{ anchor: "end", offsetMs }`),
/// the same trim-safe pattern as the `fade-out-end-anchor` fixture: the
/// effect always finishes exactly at the clip's end regardless of
/// `timing.duration`, instead of being pinned to an absolute start-relative
/// time that would land in the wrong place if the clip were trimmed.
///
/// `easing` (already resolved to a literal `V2Easing` by `resolveEasing`,
/// never a name — Protocol V2 never sees "ease in") lands on the *first*
/// keyframe of each pair: `KeyframeSampler.swift`'s `interpolate()` reads a
/// segment's easing off its starting keyframe, same convention as CSS.
func presetKeyframes(kind: PresetKind, direction: PresetDirection, durationMs: Double, easing: V2Easing?) -> [(path: String, keyframes: [V2Keyframe])] {
    func inOut(from: Double, to: Double) -> [V2Keyframe] {
        direction == .in
            ? [V2Keyframe(time: .absolute(0), value: from, easing: easing),
               V2Keyframe(time: .absolute(durationMs), value: to)]
            : [V2Keyframe(time: .anchored(anchor: .end, offsetMs: durationMs), value: from, easing: easing),
               V2Keyframe(time: .anchored(anchor: .end, offsetMs: 0), value: to)]
    }

    switch kind {
    case .fade:
        return [("opacity", inOut(from: direction == .in ? 0 : 1, to: direction == .in ? 1 : 0))]
    case .slide:
        return [("transform.translate.x", inOut(from: direction == .in ? -300 : 0, to: direction == .in ? 0 : 300))]
    case .zoom:
        let keyframes = inOut(from: direction == .in ? 0.5 : 1, to: direction == .in ? 1 : 0.6)
        return [("transform.scale.x", keyframes), ("transform.scale.y", keyframes)]
    }
}

/// Lowers an `EditorDocument` into a `V2Project`. This is where the
/// same-property merge happens (e.g. picking Fade as both the in **and**
/// out preset means both touch `opacity`): collect every `(path, keyframes)`
/// pair contributed by either preset, concatenate per path, and emit exactly
/// one `V2Track` per touched path — the protocol itself still only allows
/// one track per path, so this merge must happen here, before any JSON
/// exists.
///
/// **If an in/out preset is present, the object is always wrapped in a
/// synthetic parent `"group"` layer that carries the preset's tracks**,
/// instead of writing them onto the object's own layer — see CLAUDE.md's
/// "Group layers compose transform/opacity by real view nesting" note.
/// This is a fixed, predictable rule (preset present → always wrap), not a
/// conditional one (e.g. "only wrap if a path would actually collide with
/// the object's own animation") — simpler to reason about, and it means an
/// object's own future custom keyframes (not modeled by `EditorLayer` yet)
/// can never collide with a preset's tracks: they'd live on two different
/// layers, each with their own independent `tracks[]`, composed visually by
/// `PreviewCanvas`'s real view nesting rather than merged into one track
/// list the way same-preset same-path concatenation above is.
func compile(_ document: EditorDocument) -> V2Project {
    var filters: [V2Filter] = []
    var layers: [V2Layer] = []

    for editorLayer in document.layers {
        var keyframesByPath: [String: [V2Keyframe]] = [:]
        var pathOrder: [String] = []
        func contribute(_ binding: PresetBinding?, direction: PresetDirection) {
            guard let binding else { return }
            let easing = resolveEasing(binding.easing)
            for (path, keyframes) in presetKeyframes(kind: binding.kind, direction: direction, durationMs: binding.durationMs, easing: easing) {
                if keyframesByPath[path] == nil { pathOrder.append(path) }
                keyframesByPath[path, default: []].append(contentsOf: keyframes)
            }
        }
        contribute(editorLayer.inPreset, direction: .in)
        contribute(editorLayer.outPreset, direction: .out)

        let presetTracks = pathOrder.map { path in
            V2Track(id: "\(editorLayer.id)-\(path)", path: path, keyframes: keyframesByPath[path]!, animation: nil)
        }

        let payload: V2LayerPayload
        switch editorLayer.kind {
        case "image":
            payload = .image(V2ImagePayload(assetId: editorLayer.assetId ?? "", fit: "cover"))
        case "video":
            payload = .video(V2VideoPayload(assetId: editorLayer.assetId ?? "", fit: "cover"))
        case "text":
            payload = .text(compileTextPayload(editorLayer))
        default:
            payload = .shape(.rectangle(cornerRadius: nil, rx: nil, ry: nil, pathLength: nil), style: V2DrawStyle(fill: editorLayer.fill.map { .color($0) }))
        }

        // Named effect presets compile to a `V2Filter` (see
        // CLAUDE.md's "Protocol V2 stays atomic" rule) registered at the
        // project root and referenced by id — never stored as named
        // effects on the layer itself. Filters stay on the object's own
        // layer regardless of wrapping: a filter is a static id reference,
        // not a keyframe track, so it was never at risk of colliding with
        // anything on the wrapper.
        var filterId: String?
        if let presets = editorLayer.effectPresets, !presets.isEmpty {
            let id = "\(editorLayer.id)-filter"
            filters.append(compileFilter(id: id, presets: presets))
            filterId = id
        }

        if presetTracks.isEmpty {
            layers.append(V2Layer(
                id: editorLayer.id,
                frame: editorLayer.frame,
                transform: .identity,
                opacity: 1,
                filter: filterId,
                timing: editorLayer.timing,
                tracks: nil,
                payload: payload
            ))
        } else {
            // The wrapper mirrors the object's own `frame`/`timing` exactly
            // — the preset's end-anchored keyframes (`{anchor:"end",
            // offsetMs}`) resolve against *the layer that owns the track*,
            // so a mismatched timing here would make "out" land at the
            // wrong moment.
            let wrapperId = "\(editorLayer.id)-fx"
            layers.append(V2Layer(
                id: wrapperId,
                frame: editorLayer.frame,
                transform: .identity,
                opacity: 1,
                timing: editorLayer.timing,
                tracks: presetTracks,
                payload: .group(render3d: nil)
            ))
            layers.append(V2Layer(
                id: editorLayer.id,
                parentLayerId: wrapperId,
                frame: editorLayer.frame,
                transform: .identity,
                opacity: 1,
                filter: filterId,
                timing: editorLayer.timing,
                tracks: nil,
                payload: payload
            ))
        }
    }
    return V2Project(composition: document.composition, assets: document.assets, filters: filters.isEmpty ? nil : filters, layers: layers)
}

/// Lowers an `EditorTextLayer`'s authoring intent into Protocol V2's atomic
/// `V2TextLayerPayload`: `TextLayoutCompiler` (real Core Text shaping)
/// resolves wrap/align into one `V2TextChunk` per visual line, each with a
/// required `x`/`y` origin — see CLAUDE.md's "Text layout stays atomic" note.
private func compileTextPayload(_ editorLayer: EditorLayer) -> V2TextLayerPayload {
    guard let intent = editorLayer.text else {
        return V2TextLayerPayload(source: V2TextSource(text: ""), layout: nil, chunks: [])
    }
    let (layout, lines) = TextLayoutCompiler.compile(
        text: intent.text, fontFamily: intent.fontFamily, fontSize: intent.fontSize,
        textAlign: intent.layout.textAlign, wrap: intent.layout.wrap,
        maxWidth: editorLayer.frame.width
    )
    // Matches real SVG `<tspan>` flexibility: font lives on the span, not
    // the layer — every span this compiler emits today happens to use the
    // same font (`EditorTextLayer` only authors one), but Protocol V2 keeps
    // the per-span capability for fidelity with the real schema.
    let font = V2TextFont(families: [intent.fontFamily], size: .number(intent.fontSize))
    let uiFont = TextLayoutCompiler.resolveFont(family: intent.fontFamily, size: intent.fontSize)
    let sourceUtf16 = Array(intent.text.utf16)
    let chunks = lines.enumerated().map { index, line -> V2TextChunk in
        // "Wave"/"text on a path" both expand fully into literal
        // per-character numbers here — Protocol V2 never sees "wave" or
        // "path", only the resulting dx/dy/rotate arrays (see CLAUDE.md's
        // "Protocol V2 must stay atomic" rule and "Text layout stays
        // atomic" note on why path placement is baked at compile time
        // rather than left for the Runtime to interpret).
        var dx: [V2SvgLength]?
        var dy: [V2SvgLength]?
        var rotate: [Double]?
        if let textPath = intent.textPath {
            let lineText = String(decoding: sourceUtf16[line.range.start..<line.range.end], as: UTF16.self)
            let center = CGPoint(x: editorLayer.frame.width / 2, y: textPath.radius + 24)
            let path = TextPathResolver.circlePath(radius: textPath.radius, center: center)
            let placements = TextPathResolver.resolve(path: path, startOffset: textPath.startOffset, lineText: lineText, font: uiFont)
            dx = placements.map { .number($0.dx) }
            dy = placements.map { .number($0.dy) }
            rotate = placements.map(\.rotate)
        } else if let wave = intent.wave {
            let charCount = line.range.end - line.range.start
            let period = max(wave.periodChars, 1)
            let values = (0..<charCount).map { i -> (dx: Double, dy: Double, rotate: Double) in
                let phase = 2 * Double.pi * Double(i) / period
                return (wave.amplitude * 0.3 * cos(phase), wave.amplitude * sin(phase), wave.rotationDegrees * cos(phase))
            }
            dx = values.map { .number($0.dx) }
            dy = values.map { .number($0.dy) }
            rotate = values.map(\.rotate)
        }
        return V2TextChunk(
            id: "line-\(index)",
            sourceRange: line.range,
            x: [.number(line.x)],
            y: [.number(line.y)],
            dx: dx,
            dy: dy,
            rotate: rotate,
            spans: [V2TextSpan(
                id: "line-\(index)-span",
                sourceRange: line.range,
                font: font,
                fill: .color(intent.color)
            )]
        )
    }
    let rangeSelectors: [V2TextRangeSelector]?
    if let typewriter = intent.typewriter {
        // Named convenience ("typewriter reveal") compiled into Protocol
        // V2's compact `V2TextRangeSelector` — kept unexpanded there on
        // purpose, see CLAUDE.md's "`rangeSelectors` stays in Protocol V2"
        // note; the Runtime (`KeyframeSampler.swift`) interprets it directly
        // at sample time instead of a separate motion-compiler stage.
        //
        // The reveal *look* (instant vs. fade) is the Editor's choice
        // (`typewriter.reveal`), not hardcoded here — same rule as any
        // other named preset.
        let revealTrack: V2Track
        switch typewriter.reveal {
        case "instant":
            // A hard on/off switch, no blending — CSS step easing
            // (`stepEase` in `KeyframeSampler.swift`). The 1ms window only
            // exists because keyframe times must be strictly increasing;
            // the step easing is what actually makes it instant, not the
            // window's size.
            revealTrack = V2Track(
                id: "typewriter-reveal", path: "fillOpacity",
                keyframes: [
                    V2Keyframe(time: .absolute(0), value: 0, easing: .step(count: 1, position: "jump-end")),
                    V2Keyframe(time: .absolute(1), value: 1),
                ],
                animation: nil
            )
        default: // "fade"
            revealTrack = V2Track(
                id: "typewriter-reveal", path: "fillOpacity",
                keyframes: [
                    V2Keyframe(time: .absolute(0), value: 0),
                    V2Keyframe(time: .absolute(300), value: 1),
                ],
                animation: nil
            )
        }
        rangeSelectors = [V2TextRangeSelector(
            id: "typewriter", unit: "character", range: .all,
            stagger: V2TextRangeSelectorStagger(perUnitDelayMs: typewriter.perUnitDelayMs, direction: typewriter.direction),
            track: revealTrack
        )]
    } else {
        rangeSelectors = nil
    }
    return V2TextLayerPayload(source: V2TextSource(text: intent.text), layout: layout, chunks: chunks, rangeSelectors: rangeSelectors)
}
