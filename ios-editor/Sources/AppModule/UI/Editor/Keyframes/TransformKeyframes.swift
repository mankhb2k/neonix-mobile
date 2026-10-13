import Foundation

/// Keyframes of the Transform properties (user decisions 2026-10-13): one Protocol V2 track per scalar property
/// (`PATHS`), times are **clip-local ms** (V2's own convention: the sampler reads them against `timing.start`), a graph
/// (easing) is stored on the keyframe where its segment starts, and the six tracks always share the same times, so one
/// diamond in the UI = one time on all tracks. Adjust and Filter are not keyframed yet. Everything here is pure
/// (`V2Layer` in, `V2Layer` out); the `EditorCommand`s below are the undo steps.
enum TransformKeyframes {
    struct Channel {
        let path: String
        let read: (ResolvedLayerFrame) -> Double
    }

    static let channels: [Channel] = [
        Channel(path: "transform.translate.x") { $0.translateX },
        Channel(path: "transform.translate.y") { $0.translateY },
        Channel(path: "transform.scale.x") { $0.scaleX },
        Channel(path: "transform.scale.y") { $0.scaleY },
        Channel(path: "transform.rotate.z") { $0.rotateZ },
        Channel(path: "opacity") { $0.opacity },
    ]
    static let paths = Set(channels.map(\.path))

    /// Two keyframe times closer than this are the same keyframe.
    static let sameTimeMs = 0.5

    static func isKeyframed(_ layer: V2Layer) -> Bool {
        (layer.tracks ?? []).contains { paths.contains($0.path) && !$0.keyframes.isEmpty }
    }

    private static func resolved(_ keyframe: V2Keyframe, in layer: V2Layer) -> Double {
        resolveKeyframeTime(keyframe.time, boundMs: layer.timing.duration)
    }

    /// The clip-local times (ms, ascending) of the layer's keyframes, whether or not they are inside the clip any more (a
    /// left trim can push one before 0).
    static func times(of layer: V2Layer) -> [Double] {
        var all: [Double] = []
        for track in layer.tracks ?? [] where paths.contains(track.path) {
            for keyframe in track.keyframes {
                let t = resolved(keyframe, in: layer)
                if !all.contains(where: { abs($0 - t) < sameTimeMs }) { all.append(t) }
            }
        }
        return all.sorted()
    }

    /// The keyframe times that fall inside the clip, as timeline times (what the timeline draws).
    static func visibleTimelineTimes(of layer: V2Layer) -> [Double] {
        times(of: layer).filter { $0 >= 0 && $0 <= layer.timing.duration }.map { $0 + layer.timing.start }
    }

    /// The keyframe (local ms) within `toleranceMs` of the timeline time `atMs`, if any.
    static func keyframe(of layer: V2Layer, atMs: Double, toleranceMs: Double) -> Double? {
        let local = atMs - layer.timing.start
        return times(of: layer).first { abs($0 - local) < toleranceMs }
    }

    /// The start (local ms) of the segment the playhead is inside: between two keyframes, the earlier one counts as "on" it.
    static func segmentStart(of layer: V2Layer, atMs: Double) -> Double? {
        let local = atMs - layer.timing.start
        let ts = times(of: layer)
        guard ts.count >= 2 else { return nil }
        return zip(ts, ts.dropFirst()).first { $0.0 <= local && local < $0.1 }?.0
    }

    /// The graph of the segment starting at `startMs` (local), read from the first channel that has it.
    static func easing(of layer: V2Layer, segmentStart startMs: Double) -> V2Easing? {
        for track in layer.tracks ?? [] where paths.contains(track.path) {
            if let keyframe = track.keyframes.first(where: { abs(resolved($0, in: layer) - startMs) < sameTimeMs }) { return keyframe.easing }
        }
        return nil
    }

    // MARK: Editing (pure)

    /// Puts a keyframe at clip-local `local` on all six tracks: the sampled value for every property, except those in
    /// `overrides` (path -> value). An existing keyframe there is updated and keeps its graph.
    static func upserting(_ layer: V2Layer, local: Double, overrides: [String: Double] = [:]) -> V2Layer {
        var layer = layer
        let sampled = sampleLayer(layer, atMs: layer.timing.start + local)
        var tracks = layer.tracks ?? []
        for channel in channels {
            let value = overrides[channel.path] ?? channel.read(sampled)
            let index = tracks.firstIndex { $0.path == channel.path }
            var keyframes = index.map { tracks[$0].keyframes } ?? []
            if let existing = keyframes.firstIndex(where: { abs(resolved($0, in: layer) - local) < sameTimeMs }) {
                keyframes[existing] = V2Keyframe(time: .absolute(local), value: value, easing: keyframes[existing].easing)
            } else {
                keyframes.append(V2Keyframe(time: .absolute(local), value: value))
                keyframes.sort { resolved($0, in: layer) < resolved($1, in: layer) }
            }
            let track = V2Track(id: index.map { tracks[$0].id } ?? "kf-\(channel.path)", path: channel.path, keyframes: keyframes, animation: index.flatMap { tracks[$0].animation })
            if let index { tracks[index] = track } else { tracks.append(track) }
        }
        layer.tracks = tracks
        return layer
    }

    /// Removes the keyframe at clip-local `local`. The last one going away bakes its values into the layer's static
    /// transform and opacity, so the picture does not jump.
    static func removing(_ layer: V2Layer, local: Double) -> V2Layer {
        var layer = layer
        let sampled = sampleLayer(layer, atMs: layer.timing.start + local)
        var tracks = layer.tracks ?? []
        for index in tracks.indices where paths.contains(tracks[index].path) {
            let kept = tracks[index].keyframes.filter { abs(resolved($0, in: layer) - local) >= sameTimeMs }
            tracks[index] = V2Track(id: tracks[index].id, path: tracks[index].path, keyframes: kept, animation: tracks[index].animation)
        }
        tracks.removeAll { paths.contains($0.path) && $0.keyframes.isEmpty }
        let bake = !tracks.contains { paths.contains($0.path) }
        layer.tracks = tracks.isEmpty ? nil : tracks
        if bake {
            let old = layer.transform
            layer.transform = V2Transform(
                translate: V2Vec3(x: sampled.translateX, y: sampled.translateY, z: old.translate.z),
                scale: V2Vec3(x: sampled.scaleX, y: sampled.scaleY, z: old.scale.z),
                rotate: V2Vec3(x: old.rotate.x, y: old.rotate.y, z: sampled.rotateZ),
                skew: old.skew, anchor: old.anchor, perspective: old.perspective
            )
            layer.opacity = sampled.opacity
        }
        return layer
    }

    /// The graph of the segment that starts at clip-local `startMs`, on every track.
    static func settingEasing(_ layer: V2Layer, segmentStart startMs: Double, to easing: V2Easing?) -> V2Layer {
        var layer = layer
        var tracks = layer.tracks ?? []
        for index in tracks.indices where paths.contains(tracks[index].path) {
            let keyframes = tracks[index].keyframes.map { keyframe -> V2Keyframe in
                abs(resolved(keyframe, in: layer) - startMs) < sameTimeMs ? V2Keyframe(time: keyframe.time, value: keyframe.value, easing: easing) : keyframe
            }
            tracks[index] = V2Track(id: tracks[index].id, path: tracks[index].path, keyframes: keyframes, animation: tracks[index].animation)
        }
        layer.tracks = tracks
        return layer
    }

    /// Splitting a clip at clip-local `offset` (CapCut's way, user 2026-10-13): each half only keeps its own keyframes (the
    /// second re-timed to its own start), and when the cut is inside the animated range both halves get a keyframe at the cut
    /// - the first at its end, the second at its start - holding the value the animation had there, so the movement is
    /// continuous across the cut. A graph on the cut segment is divided exactly (`splitEasing`).
    static func splitting(_ layer: V2Layer, at offset: Double) -> (first: V2Layer, second: V2Layer) {
        let ts = times(of: layer)
        let inside = ts.count >= 2 && ts[0] <= offset + sameTimeMs && offset <= ts[ts.count - 1] + sameTimeMs
        let sampled = sampleLayer(layer, atMs: layer.timing.start + offset)
        var firstTracks: [V2Track] = [], secondTracks: [V2Track] = []

        for track in layer.tracks ?? [] {
            guard let channel = channels.first(where: { $0.path == track.path }) else {
                firstTracks.append(track); secondTracks.append(track); continue
            }
            let all = track.keyframes.sorted { resolved($0, in: layer) < resolved($1, in: layer) }
            let before = all.filter { resolved($0, in: layer) < offset - sameTimeMs }
            let at = all.first { abs(resolved($0, in: layer) - offset) < sameTimeMs }
            let after = all.filter { resolved($0, in: layer) > offset + sameTimeMs }
            func moved(_ keyframes: [V2Keyframe]) -> [V2Keyframe] {
                keyframes.map { V2Keyframe(time: .absolute(resolved($0, in: layer) - offset), value: $0.value, easing: $0.easing) }
            }
            let value = channel.read(sampled)
            var a = before, b = moved(after)
            if let at {
                b.insert(contentsOf: moved([at]), at: 0)
                if inside { a.append(V2Keyframe(time: .absolute(offset), value: at.value, easing: nil)) }
            } else if inside, let previous = before.last, let next = after.first {
                let from = resolved(previous, in: layer), to = resolved(next, in: layer)
                let halves = splitEasing(previous.easing, at: (offset - from) / (to - from))
                a[a.count - 1] = V2Keyframe(time: previous.time, value: previous.value, easing: halves.left)
                a.append(V2Keyframe(time: .absolute(offset), value: value, easing: nil))
                b.insert(V2Keyframe(time: .absolute(0), value: value, easing: halves.right), at: 0)
            }
            if !a.isEmpty { firstTracks.append(V2Track(id: track.id, path: track.path, keyframes: a, animation: track.animation)) }
            if !b.isEmpty { secondTracks.append(V2Track(id: track.id, path: track.path, keyframes: b, animation: track.animation)) }
        }
        var first = layer, second = layer
        first.tracks = firstTracks.isEmpty ? nil : firstTracks
        second.tracks = secondTracks.isEmpty ? nil : secondTracks
        return (first, second)
    }

    /// Cuts a segment's graph at the fraction `x0` (0...1) of its time into the graphs of the two pieces (de Casteljau on the
    /// cubic-bezier, each piece normalised to run 0...1 on both axes), so the two halves together trace the original curve.
    /// Linear / none stay as they are; step, spring and degenerate cuts keep the whole graph on both halves.
    static func splitEasing(_ easing: V2Easing?, at x0: Double) -> (left: V2Easing?, right: V2Easing?) {
        guard case .cubicBezier(let x1, let y1, let x2, let y2)? = easing, x0 > 0, x0 < 1 else { return (easing, easing) }
        func axis(_ s: Double, _ a: Double, _ b: Double) -> Double { let u = 1 - s; return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 { let mid = (lo + hi) / 2; if axis(mid, x1, x2) < x0 { lo = mid } else { hi = mid } }
        let s = (lo + hi) / 2
        func lerp(_ p: (Double, Double), _ q: (Double, Double)) -> (Double, Double) { (p.0 + (q.0 - p.0) * s, p.1 + (q.1 - p.1) * s) }
        let p1 = (x1, y1), p2 = (x2, y2), p3 = (1.0, 1.0)
        let a = lerp((0, 0), p1), b = lerp(p1, p2), c = lerp(p2, p3)
        let d = lerp(a, b), e = lerp(b, c), cut = lerp(d, e)
        guard cut.0 > 1e-6, 1 - cut.0 > 1e-6, abs(cut.1) > 1e-6, abs(1 - cut.1) > 1e-6 else { return (easing, easing) }   // y may overshoot: only 0 and 1 are degenerate
        let left = V2Easing.cubicBezier(x1: a.0 / cut.0, y1: a.1 / cut.1, x2: d.0 / cut.0, y2: d.1 / cut.1)
        let rw = 1 - cut.0, rh = 1 - cut.1
        let right = V2Easing.cubicBezier(x1: (e.0 - cut.0) / rw, y1: (e.1 - cut.1) / rh, x2: (c.0 - cut.0) / rw, y2: (c.1 - cut.1) / rh)
        return (left, right)
    }

    /// Mirror on a keyframed layer: the scale.x track carries the sign, so every one of its keyframes is negated.
    static func mirroring(_ layer: V2Layer) -> V2Layer {
        var layer = layer
        layer.tracks = (layer.tracks ?? []).map { track in
            guard track.path == "transform.scale.x" else { return track }
            let flipped = track.keyframes.map { keyframe -> V2Keyframe in
                guard let n = keyframe.value.asNumber else { return keyframe }
                return V2Keyframe(time: keyframe.time, value: -n, easing: keyframe.easing)
            }
            return V2Track(id: track.id, path: track.path, keyframes: flipped, animation: track.animation)
        }
        return layer
    }

    /// A left trim moves the clip's head by `delta` ms: the content stays where it is, so the keyframes' local times move
    /// the other way (they may go negative; the sampler holds the first value until they are reached).
    static func shifting(_ layer: V2Layer, by delta: Double) -> V2Layer {
        guard delta != 0, isKeyframed(layer) else { return layer }
        var layer = layer
        layer.tracks = (layer.tracks ?? []).map { track in
            guard paths.contains(track.path) else { return track }
            let moved = track.keyframes.map { V2Keyframe(time: .absolute(resolved($0, in: layer) - delta), value: $0.value, easing: $0.easing) }
            return V2Track(id: track.id, path: track.path, keyframes: moved, animation: track.animation)
        }
        return layer
    }
}

// MARK: - Commands (one undo step each)

struct AddKeyframeCommand: EditorCommand {
    let layerId: String
    let atMs: Double
    var toleranceMs = 34.0

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let layer = layers[index]
        guard TransformKeyframes.keyframe(of: layer, atMs: atMs, toleranceMs: toleranceMs) == nil else { return project }
        let local = min(max(atMs - layer.timing.start, 0), layer.timing.duration)
        layers[index] = TransformKeyframes.upserting(layer, local: local)
        return project.withLayers(layers)
    }
}

struct RemoveKeyframeCommand: EditorCommand {
    let layerId: String
    let atMs: Double
    var toleranceMs = 34.0

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }),
              let local = TransformKeyframes.keyframe(of: layers[index], atMs: atMs, toleranceMs: toleranceMs) else { return project }
        layers[index] = TransformKeyframes.removing(layers[index], local: local)
        return project.withLayers(layers)
    }
}

struct SetKeyframeEasingCommand: EditorCommand {
    let layerId: String
    /// Clip-local start of the segment (the keyframe the graph belongs to).
    let segmentStartMs: Double
    let easing: V2Easing?

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        layers[index] = TransformKeyframes.settingEasing(layers[index], segmentStart: segmentStartMs, to: easing)
        return project.withLayers(layers)
    }
}
