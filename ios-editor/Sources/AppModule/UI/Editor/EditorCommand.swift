import Foundation

/// A named, discrete edit to the project — CLAUDE.md's "Command pattern,
/// not JSON Patch or CRDT" rule. `apply(to:)` builds a *new* `V2Project`:
/// every one of `V2Project`'s own stored properties is `let`
/// (`Protocol/V2Types.swift`), so in-place mutation isn't possible, only
/// reconstruction via its own memberwise init. Undo is handled separately
/// by `EditorHistory`'s whole-document snapshot — a command itself never
/// needs to know how to reverse what it did.
protocol EditorCommand {
    func apply(to project: V2Project) -> V2Project
}

/// Tỷ lệ khung hình — changes only `composition.width`/`height`. Layer
/// `frame`/`transform` values are left completely untouched — confirmed
/// with the user: this behaves like a crop, not a reflow. Existing layers
/// keep their authored absolute coordinates, which may now sit outside
/// the new canvas bounds, the same way cropping a photo can hide part of
/// what was already there — no automatic re-anchoring.
struct SetAspectRatioCommand: EditorCommand {
    let width: Double
    let height: Double

    func apply(to project: V2Project) -> V2Project {
        let composition = V2Composition(
            width: width, height: height, fps: project.composition.fps,
            background: project.composition.background,
            colorSpace: project.composition.colorSpace, view: project.composition.view
        )
        return project.withComposition(composition)
    }
}

/// Phông nền — changes only `composition.background` (a hex color string,
/// already rendered by `PreviewCanvas` — see CLAUDE.md's nav-tools note).
struct SetBackgroundColorCommand: EditorCommand {
    let hex: String

    func apply(to project: V2Project) -> V2Project {
        let composition = V2Composition(
            width: project.composition.width, height: project.composition.height, fps: project.composition.fps,
            background: hex, colorSpace: project.composition.colorSpace, view: project.composition.view
        )
        return project.withComposition(composition)
    }
}

/// Chỉnh sửa — splits one layer into two at `atMs`, the current playhead
/// position (matching CapCut: position the playhead where you want to
/// cut, then tap split). A no-op (returns `project` unchanged) if `atMs`
/// isn't strictly inside the clip's own time range, or the layer isn't
/// found — a command silently doing nothing on an invalid request matches
/// this app's established "no ported validator, fail closed/no-op, not a
/// crash" convention (see CLAUDE.md's "Valid by construction" rule) rather
/// than needing its own error-reporting path for what the UI should
/// already prevent (the panel only enables Split when the playhead is
/// actually inside the selected clip).
struct SplitClipCommand: EditorCommand {
    let layerId: String
    let atMs: Double

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let original = layers[index]
        guard atMs > original.timing.start, atMs < original.timing.start + original.timing.duration else { return project }

        let firstDuration = atMs - original.timing.start
        let secondDuration = original.timing.duration - firstDuration

        var first = original
        first.timing = V2Timing(start: original.timing.start, duration: firstDuration)

        var second = original
        second.id = "\(original.id)-split-\(UUID().uuidString.prefix(8))"
        second.timing = V2Timing(start: atMs, duration: secondDuration)
        // A video clip's second half must keep playing from where the
        // first half left off in the *source* file, not restart from the
        // original's own trim point — shift `trimStart` forward by exactly
        // the first half's duration.
        if case .video(var payload) = second.payload {
            payload.trimStart = (payload.trimStart ?? 0) + firstDuration
            second.payload = .video(payload)
        }

        layers[index] = first
        layers.insert(second, at: index + 1)
        return project.withLayers(layers)
    }
}

/// Chỉnh sửa — drag-to-trim via the Timeline's own left/right handles. Both
/// handles reuse this one command: `TimelineView`'s drag gesture computes
/// the new `timing`/`trimStart`/`trimEnd` (including clamping an *extend*
/// drag against the clip's real asset duration via `AssetDurationCache`,
/// confirmed with the user as the correct CapCut-matching behavior rather
/// than a shrink-only first pass) and this command just writes the result —
/// no clamping/validation here, matching this app's "no ported validator"
/// convention (the UI is responsible for only ever proposing values that
/// are already valid).
///
/// **`siblingStarts`** (added 2026-10-08, the "ripple reflow" feature): on
/// a push-lane (video/image — a main-track lane, which must never show a
/// gap, confirmed with the user), trimming one clip repositions *other*
/// clips in the same lane too — every clip after the dragged one glues to
/// whichever clip now precedes it, cascading down the whole lane in both
/// directions (not just the immediate neighbor), with each sibling's own
/// `timing.duration` left untouched — only its `timing.start` moves. This
/// dict is `TimelineView`'s own `reflowLane(...)` output; `[:]` for a
/// stop-lane trim (text etc., where a drag hard-clamps against the
/// neighbor's edge instead of pushing it, so nothing else ever needs to
/// move).
struct TrimClipCommand: EditorCommand {
    let layerId: String
    let start: Double
    let duration: Double
    let trimStart: Double?
    let trimEnd: Double?
    var siblingStarts: [String: Double] = [:]

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        var layer = layers[index]
        layer.timing = V2Timing(start: start, duration: duration)
        if case .video(var payload) = layer.payload {
            payload.trimStart = trimStart
            payload.trimEnd = trimEnd
            layer.payload = .video(payload)
        }
        layers[index] = layer

        for (siblingId, newStart) in siblingStarts {
            guard let siblingIndex = layers.firstIndex(where: { $0.id == siblingId }) else { continue }
            var sibling = layers[siblingIndex]
            sibling.timing = V2Timing(start: newStart, duration: sibling.timing.duration)
            layers[siblingIndex] = sibling
        }
        return project.withLayers(layers)
    }
}

/// Chỉnh sửa — removes one layer entirely. No confirmation step here (the
/// UI layer's job, not the command's); undo already covers "I didn't mean
/// to delete that."
struct DeleteClipCommand: EditorCommand {
    let layerId: String

    func apply(to project: V2Project) -> V2Project {
        project.withLayers(project.layers.filter { $0.id != layerId })
    }
}

extension V2Project {
    /// Every other field copied as-is — the one piece of boilerplate every
    /// project-level command above needs, factored out once rather than
    /// repeating the full memberwise reconstruction in each command.
    func withComposition(_ composition: V2Composition) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }

    func withLayers(_ layers: [V2Layer]) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }
}
