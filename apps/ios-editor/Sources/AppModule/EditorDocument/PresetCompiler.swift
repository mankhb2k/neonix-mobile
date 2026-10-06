import Foundation

/// The 6 basic in/out presets: Fade, Slide, Zoom, each with an `in` and
/// `out` variant. Returns one or more `(path, keyframes)` pairs — Zoom
/// drives both `transform.scale.x` and `transform.scale.y`.
///
/// `out` keyframes are both end-anchored (`{ anchor: "end", offsetMs }`),
/// the same trim-safe pattern as the `fade-out-end-anchor` fixture: the
/// effect always finishes exactly at the clip's end regardless of
/// `timing.duration`, instead of being pinned to an absolute start-relative
/// time that would land in the wrong place if the clip were trimmed.
func presetKeyframes(kind: PresetKind, direction: PresetDirection, durationMs: Double) -> [(path: String, keyframes: [V2Keyframe])] {
    func inOut(from: Double, to: Double) -> [V2Keyframe] {
        direction == .in
            ? [V2Keyframe(time: .absolute(0), value: from),
               V2Keyframe(time: .absolute(durationMs), value: to)]
            : [V2Keyframe(time: .anchored(anchor: .end, offsetMs: durationMs), value: from),
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
func compile(_ document: EditorDocument) -> V2Project {
    var filters: [V2Filter] = []

    let layers = document.layers.map { editorLayer -> V2Layer in
        var keyframesByPath: [String: [V2Keyframe]] = [:]
        var pathOrder: [String] = []
        func contribute(_ binding: PresetBinding?, direction: PresetDirection) {
            guard let binding else { return }
            for (path, keyframes) in presetKeyframes(kind: binding.kind, direction: direction, durationMs: binding.durationMs) {
                if keyframesByPath[path] == nil { pathOrder.append(path) }
                keyframesByPath[path, default: []].append(contentsOf: keyframes)
            }
        }
        contribute(editorLayer.inPreset, direction: .in)
        contribute(editorLayer.outPreset, direction: .out)

        let tracks = pathOrder.map { path in
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
        // effects on the layer itself.
        var filterId: String?
        if let presets = editorLayer.effectPresets, !presets.isEmpty {
            let id = "\(editorLayer.id)-filter"
            filters.append(compileFilter(id: id, presets: presets))
            filterId = id
        }

        return V2Layer(
            id: editorLayer.id,
            frame: editorLayer.frame,
            transform: .identity,
            opacity: 1,
            filter: filterId,
            timing: editorLayer.timing,
            tracks: tracks.isEmpty ? nil : tracks,
            payload: payload
        )
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
    let chunks = lines.enumerated().map { index, line in
        V2TextChunk(
            id: "line-\(index)",
            sourceRange: line.range,
            x: [.number(line.x)],
            y: [.number(line.y)],
            spans: [V2TextSpan(
                id: "line-\(index)-span",
                sourceRange: line.range,
                font: font,
                fill: .color(intent.color)
            )]
        )
    }
    return V2TextLayerPayload(source: V2TextSource(text: intent.text), layout: layout, chunks: chunks)
}
