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

/// The small set of transitions available for a cut in the editor.
enum TransitionKind: String, Codable, CaseIterable, Identifiable {
    case mix
    case fadeBlack = "fade-black"
    case push

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mix: "Mix"
        case .fadeBlack: "Fade"
        case .push: "Push"
        }
    }
    var symbol: String {
        switch self {
        case .mix: "circle.lefthalf.filled"
        case .fadeBlack: "sun.max"
        case .push: "arrow.left.and.right"
        }
    }
}

/// Transitions are lowered to V2 groups and tracks. Each group wraps the clip subtree, keeping transition tracks
/// independent from the clip's authored keyframes and animation wrappers.
enum TransitionWrappers {
    static let marker = "~transition~"
    static let outgoingMarker = "~transition-out~"
    private static let fadeContentMarker = "~transition-fade-content~"
    private static let fadeBlackMarker = "~transition-fade-black~"
    static let defaultDurationMs = 500.0

    /// The same editor intent type used in saved EditorDocument JSON.
    typealias Applied = EditorTransitionIntent

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func wrapperId(outgoingId: String, incomingId: String, kind: TransitionKind = .mix, durationMs: Double) -> String {
        "\(incomingId)\(marker)\(encode(outgoingId))~\(kind.rawValue)~\(Int(durationMs.rounded()))"
    }

    static func parse(_ id: String) -> Applied? {
        guard let range = id.range(of: marker) else { return nil }
        let incomingId = String(id[..<range.lowerBound])
        let parts = id[range.upperBound...].split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 2, let outgoingId = decode(parts[0]) else { return nil }
        // `dissolve` is the original v1 wrapper spelling; keep old project documents readable as Mix.
        let kind = parts.count == 2 ? TransitionKind.mix : (parts[1] == "dissolve" ? .mix : TransitionKind(rawValue: parts[1]))
        let durationToken = parts.count == 2 ? parts[1] : parts[2]
        guard let kind, let duration = Double(durationToken), duration > 0 else { return nil }
        return Applied(outgoingId: outgoingId, incomingId: incomingId, kind: kind, durationMs: duration)
    }

    private static func outgoingWrapperId(_ applied: Applied) -> String {
        "\(applied.outgoingId)\(outgoingMarker)\(encode(applied.incomingId))~\(applied.kind.rawValue)~\(Int(applied.durationMs.rounded()))"
    }

    static func parseOutgoing(_ id: String) -> Applied? {
        guard let range = id.range(of: outgoingMarker) else { return nil }
        let outgoingId = String(id[..<range.lowerBound])
        let parts = id[range.upperBound...].split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let incomingId = decode(parts[0]), let kind = TransitionKind(rawValue: parts[1]),
              kind == .push, let duration = Double(parts[2]), duration > 0 else { return nil }
        return Applied(outgoingId: outgoingId, incomingId: incomingId, kind: kind, durationMs: duration)
    }

    static func applied(in layers: [V2Layer]) -> [String: Applied] {
        layers.reduce(into: [:]) { result, layer in
            if let applied = parse(layer.id) { result[applied.incomingId] = applied }
        }
    }

    static func applied(for incomingId: String, in layers: [V2Layer]) -> Applied? {
        layers.lazy.compactMap { parse($0.id) }.first { $0.incomingId == incomingId }
    }

    private static func isTransitionWrapper(_ id: String, for clipId: String) -> Bool {
        parse(id).map { $0.incomingId == clipId || $0.outgoingId == clipId } == true
            || parseOutgoing(id).map { $0.incomingId == clipId || $0.outgoingId == clipId } == true
            || id.range(of: fadeContentMarker).flatMap { range in
                parse(String(id[..<range.lowerBound]))
            }.map { $0.incomingId == clipId } == true
    }

    /// Returns the outermost animation/transition wrapper around a clip, so another transition composes outside it.
    private static func wrappedRoot(for clipId: String, layers: [V2Layer]) -> V2Layer? {
        guard let clip = layers.first(where: { $0.id == clipId }) else { return nil }
        var root = clip
        while let parentId = root.parentLayerId, let parent = layers.first(where: { $0.id == parentId }),
              AnimationWrappers.parse(parentId)?.clipId == clipId || isTransitionWrapper(parentId, for: clipId)
                || parentId.hasPrefix(root.id + fadeContentMarker) {
            root = parent
        }
        return root
    }

    private static func unwrapAndRemove(_ wrapperId: String, from layers: inout [V2Layer]) {
        guard let wrapper = layers.first(where: { $0.id == wrapperId }) else { return }
        let childIds = [wrapperId + fadeContentMarker, wrapperId + fadeBlackMarker]
        for index in layers.indices where layers[index].parentLayerId == wrapperId && !childIds.contains(layers[index].id) {
            layers[index].parentLayerId = wrapper.parentLayerId
        }
        if let content = layers.first(where: { $0.id == childIds[0] }) {
            for index in layers.indices where layers[index].parentLayerId == content.id {
                layers[index].parentLayerId = wrapper.parentLayerId
            }
        }
        layers.removeAll { $0.id == wrapperId || childIds.contains($0.id) }
    }

    private static func transitionTracks(id: String, kind: TransitionKind, durationMs: Double, canvasWidth: Double, isOutgoing: Bool) -> [V2Track] {
        switch kind {
        case .mix:
            return [V2Track(id: "\(id)-opacity", path: "opacity", keyframes: [
                V2Keyframe(time: .absolute(0), value: 0), V2Keyframe(time: .absolute(durationMs), value: 1)
            ], animation: nil)]
        case .fadeBlack:
            return [] // The incoming fade and black dip are separate child layers in `setting`.
        case .push:
            let path = "transform.translate.x"
            let from = isOutgoing ? 0.0 : canvasWidth
            let to = isOutgoing ? -canvasWidth : 0.0
            let start: V2KeyframeTime = isOutgoing ? .anchored(anchor: .end, offsetMs: durationMs) : .absolute(0)
            let end: V2KeyframeTime = isOutgoing ? .anchored(anchor: .end, offsetMs: 0) : .absolute(durationMs)
            return [V2Track(id: "\(id)-translate-x", path: path, keyframes: [
                V2Keyframe(time: start, value: from), V2Keyframe(time: end, value: to)
            ], animation: nil)]
        }
    }

    /// Sets/removes a transition on one adjacent pair, leaving authored animation and keyframe layers nested underneath.
    static func setting(_ project: V2Project, outgoingId: String, incomingId: String, kind: TransitionKind = .mix, durationMs: Double?) -> V2Project {
        guard let incomingIndex = project.layers.firstIndex(where: { $0.id == incomingId }),
              let outgoing = project.layers.first(where: { $0.id == outgoingId }),
              project.layers[incomingIndex].type == "video", outgoing.type == "video",
              outgoing.order == project.layers[incomingIndex].order else { return project }

        var layers = project.layers
        if let old = applied(for: incomingId, in: layers), old.outgoingId == outgoingId {
            unwrapAndRemove(wrapperId(outgoingId: outgoingId, incomingId: incomingId, kind: old.kind, durationMs: old.durationMs), from: &layers)
            if old.kind == .push { unwrapAndRemove(outgoingWrapperId(old), from: &layers) }
        }
        guard let durationMs else { return project.withLayers(layers) }

        let frameMs = 1000 / max(project.composition.fps, 1)
        let maxDuration = min(outgoing.timing.duration, project.layers[incomingIndex].timing.duration) - frameMs
        guard maxDuration >= frameMs else { return project }
        let duration = min(max(durationMs, frameMs), maxDuration)
        let applied = Applied(outgoingId: outgoingId, incomingId: incomingId, kind: kind, durationMs: duration)

        func addWrapper(for clipId: String, wrapperId: String, tracks: [V2Track], timing: V2Timing, frame: V2Frame, order: Int) {
            guard let root = wrappedRoot(for: clipId, layers: layers), let rootIndex = layers.firstIndex(where: { $0.id == root.id }) else { return }
            let wrapper = V2Layer(id: wrapperId, parentLayerId: root.parentLayerId, order: order, frame: frame,
                                 transform: .identity, timing: timing, tracks: tracks, payload: .group(render3d: nil))
            if let childIndex = layers.firstIndex(where: { $0.id == root.id }) {
                layers[childIndex].parentLayerId = wrapperId
                layers.insert(wrapper, at: rootIndex)
            }
        }

        let incoming = layers.first { $0.id == incomingId }!
        let incomingWrapperId = wrapperId(outgoingId: outgoingId, incomingId: incomingId, kind: kind, durationMs: duration)
        let incomingTracks = transitionTracks(id: incomingWrapperId, kind: kind, durationMs: duration,
                                              canvasWidth: project.composition.width, isOutgoing: false)
        addWrapper(for: incomingId, wrapperId: incomingWrapperId, tracks: incomingTracks,
                   timing: incoming.timing, frame: incoming.frame, order: incoming.order)

        if kind == .fadeBlack {
            let contentId = incomingWrapperId + fadeContentMarker
            let blackId = incomingWrapperId + fadeBlackMarker
            guard let wrapperIndex = layers.firstIndex(where: { $0.id == incomingWrapperId }),
                  let rootIndex = layers.firstIndex(where: { $0.parentLayerId == incomingWrapperId }) else { return project }
            layers[rootIndex].parentLayerId = contentId
            let content = V2Layer(id: contentId, parentLayerId: incomingWrapperId, order: incoming.order, frame: incoming.frame,
                                  transform: .identity, timing: incoming.timing, tracks: [V2Track(id: "\(contentId)-opacity", path: "opacity", keyframes: [
                                    V2Keyframe(time: .absolute(0), value: 0), V2Keyframe(time: .absolute(duration), value: 1)
                                  ], animation: nil)], payload: .group(render3d: nil))
            let black = V2Layer(id: blackId, parentLayerId: incomingWrapperId, order: incoming.order,
                                frame: V2Frame(width: project.composition.width, height: project.composition.height), transform: .identity,
                                timing: incoming.timing, tracks: [V2Track(id: "\(blackId)-opacity", path: "opacity", keyframes: [
                                    V2Keyframe(time: .absolute(0), value: 0),
                                    V2Keyframe(time: .absolute(duration / 2), value: 1),
                                    V2Keyframe(time: .absolute(duration), value: 0)
                                ], animation: nil)],
                                payload: .shape(.rectangle(cornerRadius: nil, rx: nil, ry: nil, pathLength: nil),
                                                style: V2DrawStyle(fill: .color("#000000"))))
            layers[wrapperIndex].tracks = nil
            layers.insert(contentsOf: [content, black], at: wrapperIndex + 1)
        }

        if kind == .push {
            let outgoingWrapper = outgoingWrapperId(applied)
            let outgoingTracks = transitionTracks(id: outgoingWrapper, kind: .push, durationMs: duration,
                                                  canvasWidth: project.composition.width, isOutgoing: true)
            addWrapper(for: outgoingId, wrapperId: outgoingWrapper, tracks: outgoingTracks,
                       timing: outgoing.timing, frame: outgoing.frame, order: outgoing.order)
        }
        return project.withLayers(layers)
    }

    /// Drops orphaned transitions and keeps a valid wrapper aligned with its incoming clip after trims/speed changes.
    static func normalized(_ project: V2Project) -> V2Project {
        let transitions = project.layers.compactMap { layer -> (V2Layer, Applied)? in
            parse(layer.id).map { (layer, $0) }
        }
        guard !transitions.isEmpty else { return project }
        var layers = project.layers
        var changed = false
        for (wrapper, applied) in transitions {
            guard let incoming = layers.first(where: { $0.id == applied.incomingId }),
                  let outgoing = layers.first(where: { $0.id == applied.outgoingId }),
                  incoming.type == "video", outgoing.type == "video", incoming.order == outgoing.order else {
                unwrapAndRemove(wrapper.id, from: &layers)
                unwrapAndRemove(outgoingWrapperId(applied), from: &layers)
                changed = true
                continue
            }
            let lane = layers.enumerated()
                .filter { $0.element.order == incoming.order && isPushLane($0.element) }
                .sorted { ($0.element.timing.start, $0.offset) < ($1.element.timing.start, $1.offset) }
                .map(\.element)
            guard let incomingIndex = lane.firstIndex(where: { $0.id == incoming.id }), incomingIndex > 0,
                  lane[incomingIndex - 1].id == outgoing.id else {
                unwrapAndRemove(wrapper.id, from: &layers)
                unwrapAndRemove(outgoingWrapperId(applied), from: &layers)
                changed = true
                continue
            }
            if wrapper.timing.start != incoming.timing.start || wrapper.timing.duration != incoming.timing.duration
                || wrapper.frame.width != incoming.frame.width || wrapper.frame.height != incoming.frame.height || wrapper.order != incoming.order {
                guard let index = layers.firstIndex(where: { $0.id == wrapper.id }) else { continue }
                var fixed = wrapper
                fixed.timing = incoming.timing; fixed.frame = incoming.frame; fixed.order = incoming.order
                layers[index] = fixed
                changed = true
            }
            if applied.kind == .fadeBlack {
                for id in [wrapper.id + fadeContentMarker, wrapper.id + fadeBlackMarker] {
                    guard let index = layers.firstIndex(where: { $0.id == id }) else { continue }
                    if layers[index].timing.start != incoming.timing.start || layers[index].timing.duration != incoming.timing.duration
                        || layers[index].order != incoming.order {
                        layers[index].timing = incoming.timing; layers[index].order = incoming.order
                        if id.hasSuffix(fadeContentMarker) { layers[index].frame = incoming.frame }
                        changed = true
                    }
                }
            }
            if applied.kind == .push, let outIndex = layers.firstIndex(where: { $0.id == outgoingWrapperId(applied) }),
               (layers[outIndex].timing.start != outgoing.timing.start || layers[outIndex].timing.duration != outgoing.timing.duration) {
                layers[outIndex].timing = outgoing.timing; layers[outIndex].frame = outgoing.frame; layers[outIndex].order = outgoing.order
                changed = true
            }
        }
        return changed ? project.withLayers(layers) : project
    }
}

/// Converts editor transition intent into atomic V2 groups/tracks. Editor clip timing stays
/// contiguous; `TransitionFramePlan` resolves the centered frame window without shifting clips.
/// Shared by EditorDocument compilation and the live editor command.
enum TransitionLowerer {
    static func apply(_ project: V2Project, outgoingId: String, incomingId: String,
                      kind: TransitionKind, durationMs: Double?) -> V2Project {
        guard let source = project.layers.first(where: { $0.id == outgoingId }), isPushLane(source) else { return project }
        guard source.order == primaryVideoLaneOrder(of: project.layers) else { return project }
        let clips = project.layers.enumerated()
            .filter { $0.element.order == source.order && isPushLane($0.element) }
            .sorted { ($0.element.timing.start, $0.offset) < ($1.element.timing.start, $1.offset) }
            .map(\.element)
        guard let index = clips.firstIndex(where: { $0.id == outgoingId }), index + 1 < clips.count,
              clips[index + 1].id == incomingId, clips[index].type == "video", clips[index + 1].type == "video" else { return project }

        let changed = TransitionWrappers.setting(project, outgoingId: outgoingId, incomingId: incomingId, kind: kind, durationMs: durationMs)
        let nextDuration = TransitionWrappers.applied(for: incomingId, in: changed.layers)?.durationMs ?? 0
        if durationMs != nil && nextDuration == 0 { return project }
        return TransitionWrappers.normalized(AnimationWrappers.normalized(changed))
    }
}

/// Resolves a transition at editor time without changing clip placement.
/// Preview and export use the same interval and edge-frame sampling rules:
/// both source clips remain on their authored timeline, and a source is held
/// at its first/last frame only while its transition partner crosses the cut.
struct TransitionFramePlan {
    struct Window: Equatable {
        let outgoingId: String
        let incomingId: String
        let kind: TransitionKind
        let startMs: Double
        let cutMs: Double
        let endMs: Double

        var durationMs: Double { endMs - startMs }
        func progress(at timeMs: Double) -> Double {
            guard durationMs > 0 else { return 1 }
            return min(max((timeMs - startMs) / durationMs, 0), 1)
        }
        func contains(_ timeMs: Double) -> Bool { timeMs >= startMs && timeMs < endMs }
    }

    private(set) var windows: [Window]

    init(project: V2Project) {
        let layers = project.layers
        let intents = TransitionWrappers.applied(in: layers).values
        windows = intents.compactMap { intent in
            guard let outgoing = layers.first(where: { $0.id == intent.outgoingId }),
                  let incoming = layers.first(where: { $0.id == intent.incomingId }),
                  outgoing.type == "video", incoming.type == "video",
                  outgoing.order == incoming.order else { return nil }
            let cut = outgoing.timing.start + outgoing.timing.duration
            guard abs(incoming.timing.start - cut) < 1 else { return nil }
            let duration = min(intent.durationMs, outgoing.timing.duration, incoming.timing.duration)
            guard duration > 0 else { return nil }
            return Window(outgoingId: outgoing.id, incomingId: incoming.id, kind: intent.kind,
                          startMs: cut - duration / 2, cutMs: cut, endMs: cut + duration / 2)
        }.sorted { $0.startMs < $1.startMs }
    }

    func activeWindow(at timeMs: Double) -> Window? { windows.first { $0.contains(timeMs) } }

    func isVisible(_ layerId: String, at timeMs: Double) -> Bool {
        if let window = activeWindow(at: timeMs), layerId == window.outgoingId || layerId == window.incomingId { return true }
        return false
    }

    /// Returns the authored timeline time to sample. Outside its clip window,
    /// a transition participant holds the nearest edge frame.
    func sourceTimelineTime(for layer: V2Layer, at timeMs: Double) -> Double {
        guard isVisible(layer.id, at: timeMs) else { return timeMs }
        return min(max(timeMs, layer.timing.start), layer.timing.start + layer.timing.duration)
    }

    /// Builds only render metadata. The media clip timings and every later clip
    /// stay untouched; generated wrappers cover the transition and keep the incoming clip's render span alive afterward.
    func renderProject(from project: V2Project) -> V2Project {
        guard !windows.isEmpty else { return project }
        var result = project
        var layers = result.layers
        for window in windows {
            let transitionId = layers.first { TransitionWrappers.parse($0.id)?.incomingId == window.incomingId }?.id
            let outgoingId = layers.first { TransitionWrappers.parseOutgoing($0.id)?.outgoingId == window.outgoingId }?.id
            let incomingEndMs = project.layers.first { $0.id == window.incomingId }
                .map { $0.timing.start + $0.timing.duration } ?? window.endMs
            let outgoingStartMs = project.layers.first { $0.id == window.outgoingId }?.timing.start ?? window.startMs
            let expandedIds = Set(layers.compactMap { layer -> String? in
                guard let animation = AnimationWrappers.parse(layer.id), animation.clipId == window.incomingId else { return nil }
                return layer.id
            })
            for index in layers.indices {
                let id = layers[index].id
                let isIncomingTransition = id == transitionId
                let isOutgoingTransition = id == outgoingId
                let isFadeChild = transitionId.map { id.hasPrefix($0) && id != $0 } ?? false
                guard isIncomingTransition || isOutgoingTransition || isFadeChild || expandedIds.contains(id) else { continue }
                var layer = layers[index]
                let originalStart = layer.timing.start
                if expandedIds.contains(id) || isIncomingTransition || (isFadeChild && layer.type == "group") {
                    // Keep the incoming subtree alive for the rest of its clip. The transition track reaches its final value
                    // at window.endMs and then holds it; ending this wrapper at the cut window would blank the clip.
                    layer.timing = V2Timing(start: window.startMs, duration: max(0, incomingEndMs - window.startMs))
                } else if isOutgoingTransition {
                    // A push starts at the outgoing clip's normal position, moves during the window, then remains off-canvas.
                    layer.timing = V2Timing(start: outgoingStartMs, duration: max(0, window.endMs - outgoingStartMs))
                } else {
                    // The Fade black shape is the only generated child that should disappear at the end of the window.
                    layer.timing = V2Timing(start: window.startMs, duration: window.durationMs)
                }
                if expandedIds.contains(id), var tracks = layer.tracks {
                    // Preserve the clip's authored animation start: its local
                    // keyframes move with the expanded wrapper's new start.
                    let lead = max(0, originalStart - window.startMs)
                    tracks = tracks.map { track in
                        let keyframes = track.keyframes.map { keyframe in
                            guard case .absolute(let ms) = keyframe.time else { return keyframe }
                            return V2Keyframe(time: .absolute(ms + lead), value: keyframe.value, easing: keyframe.easing)
                        }
                        return V2Track(id: track.id, path: track.path, keyframes: keyframes, animation: track.animation)
                    }
                    layer.tracks = tracks
                }
                layers[index] = layer
            }
        }
        result = result.withLayers(layers)
        return result
    }
}

enum TransitionRenderPlan {
    static func compile(_ editorProject: V2Project) -> V2Project {
        TransitionFramePlan(project: editorProject).renderProject(from: editorProject)
    }
}

/// One undoable editor action. The intent is lowered by the same path used when loading EditorDocument JSON.
struct SetTransitionCommand: EditorCommand {
    let outgoingId: String
    let incomingId: String
    var kind: TransitionKind = .mix
    /// nil removes the transition.
    let durationMs: Double?

    func apply(to project: V2Project) -> V2Project {
        TransitionLowerer.apply(project, outgoingId: outgoingId, incomingId: incomingId,
                                kind: kind, durationMs: durationMs)
    }
}
