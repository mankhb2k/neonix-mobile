import Foundation

/// How a clip's animations live in Protocol V2. Each animation (In, Out, Combo) is its own invisible parent `"group"` layer holding the
/// preset's tracks, nested around the clip: clip -> In wrapper -> Out wrapper -> Combo wrapper (CLAUDE.md, "Group layers compose by real
/// nesting"). The clip keeps its own tracks (the user's keyframes), so nothing ever collides on a path.
///
/// A wrapper's id carries what the editor needs to read it back - `<clipId>~anim~<slot>~<presetId>~<durationMs>` - so the picked preset shows
/// in the sheet and survives undo/redo (snapshots hold the layers), without a second state next to the document. V2 treats the id as an
/// opaque label. A wrapper mirrors its clip's `timing` (an end-anchored Out resolves against the wrapper's own timing): `normalized` keeps
/// that true after any edit and drops wrappers whose clip is gone.
enum AnimationWrappers {
    static let marker = "~anim~"

    struct Applied: Equatable {
        var slot: AnimationSlot
        var presetId: String
        var durationMs: Double
    }

    static func wrapperId(clipId: String, _ applied: Applied) -> String {
        "\(clipId)\(marker)\(applied.slot.rawValue)~\(applied.presetId)~\(Int(applied.durationMs.rounded()))"
    }

    /// `(clipId, applied)` for a wrapper layer id, nil for any other layer.
    static func parse(_ id: String) -> (clipId: String, applied: Applied)? {
        guard let range = id.range(of: marker) else { return nil }
        let parts = id[range.upperBound...].split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let slot = AnimationSlot(rawValue: parts[0]), let ms = Double(parts[2]) else { return nil }
        return (String(id[..<range.lowerBound]), Applied(slot: slot, presetId: parts[1], durationMs: ms))
    }

    /// The animations on a clip, by slot.
    static func applied(for clipId: String, in layers: [V2Layer]) -> [AnimationSlot: Applied] {
        var result: [AnimationSlot: Applied] = [:]
        for layer in layers {
            if let parsed = parse(layer.id), parsed.clipId == clipId { result[parsed.applied.slot] = parsed.applied }
        }
        return result
    }

    /// The clip's parent once its own wrappers are skipped (a legacy wrapper from a compiled template, or nil).
    static func baseParent(of clip: V2Layer, in layers: [V2Layer]) -> String? {
        var parent = clip.parentLayerId
        while let id = parent, let layer = layers.first(where: { $0.id == id }), parse(layer.id)?.clipId == clip.id { parent = layer.parentLayerId }
        return parent
    }

    /// Replaces every animation of `clipId` with `animations` (at most one per slot): old wrappers go, fresh ones are nested in the order
    /// In, Out, Combo and take the clip's place in the layer array (so z-order is unchanged).
    static func rebuilt(_ project: V2Project, clipId: String, animations: [Applied]) -> V2Project {
        guard let clipIndex = project.layers.firstIndex(where: { $0.id == clipId }) else { return project }
        var clip = project.layers[clipIndex]
        let base = baseParent(of: clip, in: project.layers)
        var layers = project.layers.filter { parse($0.id)?.clipId != clipId }
        guard let index = layers.firstIndex(where: { $0.id == clipId }) else { return project }

        let ordered = AnimationSlot.allCases.compactMap { slot in animations.first { $0.slot == slot } }
        // Outermost first in the array: the last slot wraps all the others.
        var wrappers: [V2Layer] = []
        var parent = base
        for applied in ordered.reversed() {
            guard let preset = AnimationCatalog.preset(id: applied.presetId), preset.slots.contains(applied.slot) else { continue }
            let id = wrapperId(clipId: clipId, applied)
            let tracks = AnimationCatalog.tracks(
                for: preset, slot: applied.slot, durationMs: applied.durationMs,
                canvas: (project.composition.width, project.composition.height), idPrefix: id
            )
            wrappers.append(V2Layer(
                id: id, parentLayerId: parent, order: clip.order, frame: clip.frame, transform: .identity, opacity: 1,
                timing: clip.timing, tracks: tracks, payload: .group(render3d: nil)
            ))
            parent = id
        }
        clip.parentLayerId = parent
        layers[index] = clip
        layers.insert(contentsOf: wrappers, at: index)
        return project.withLayers(layers)
    }

    /// One slot changed: `preset == nil` removes it.
    static func setting(_ project: V2Project, clipId: String, slot: AnimationSlot, presetId: String?, durationMs: Double) -> V2Project {
        var animations = Array(applied(for: clipId, in: project.layers).values).filter { $0.slot != slot }
        if let presetId { animations.append(Applied(slot: slot, presetId: presetId, durationMs: durationMs)) }
        return rebuilt(project, clipId: clipId, animations: animations)
    }

    /// Keeps wrappers honest after any edit: each mirrors its clip's timing, frame and lane; one whose clip is gone is dropped. Returns the
    /// same project when nothing needs fixing.
    static func normalized(_ project: V2Project) -> V2Project {
        guard project.layers.contains(where: { $0.id.contains(marker) }) else { return project }
        let ids = Set(project.layers.map(\.id))
        var changed = false
        var layers: [V2Layer] = []
        for layer in project.layers {
            guard let parsed = parse(layer.id) else { layers.append(layer); continue }
            guard let clip = project.layers.first(where: { $0.id == parsed.clipId }), ids.contains(clip.id) else { changed = true; continue }
            if layer.timing.start != clip.timing.start || layer.timing.duration != clip.timing.duration || layer.order != clip.order
                || layer.frame.width != clip.frame.width || layer.frame.height != clip.frame.height {
                var fixed = layer
                fixed.timing = clip.timing; fixed.order = clip.order; fixed.frame = clip.frame
                layers.append(fixed); changed = true
            } else {
                layers.append(layer)
            }
        }
        return changed ? project.withLayers(layers) : project
    }
}

/// Sets, replaces or removes one animation of a clip. One undo step. `durationMs` is the entrance/exit length (ignored for a combo).
struct SetAnimationCommand: EditorCommand {
    let layerId: String
    let slot: AnimationSlot
    /// nil = no animation in this slot.
    let presetId: String?
    var durationMs: Double = 500

    func apply(to project: V2Project) -> V2Project {
        guard let clip = project.layers.first(where: { $0.id == layerId }), clip.type != "group" else { return project }
        if let presetId, AnimationCatalog.preset(id: presetId)?.slots.contains(slot) != true { return project }   // fail closed
        let duration = slot == .combo ? 0 : min(max(durationMs, 100), max(clip.timing.duration - 100, 100))
        return AnimationWrappers.setting(project, clipId: layerId, slot: slot, presetId: presetId, durationMs: duration)
    }
}
