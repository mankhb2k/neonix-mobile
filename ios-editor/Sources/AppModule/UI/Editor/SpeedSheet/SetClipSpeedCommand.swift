import Foundation

/// How many ms of source footage a video clip plays: its length x its constant rate, or the stretch its speed curve covers.
func sourceSpanMs(of layer: V2Layer) -> Double? {
    guard case .video(let payload) = layer.payload else { return nil }
    if let last = payload.speedCurve?.last { return last.sourceMs }
    return layer.timing.duration * (VideoTimeMapping(layer: layer)?.rate ?? 1)
}

/// Gives a video clip a new length without touching the footage it plays: `edit` rewrites its payload (rate or curve), the clip's own keyframes
/// scale with the new length, and the clips after it in the same lane follow (push-lane ripple, `reflowLane`), so a main lane never gets a hole
/// or an overlap. Shared by `SetClipSpeedCommand` and `SetClipSpeedCurveCommand`.
func retimedClip(_ project: V2Project, clipId: String, newDuration: Double, edit: (inout V2VideoPayload) -> Void) -> V2Project {
    var layers = project.layers
    guard let index = layers.firstIndex(where: { $0.id == clipId }), case .video(var payload) = layers[index].payload else { return project }
    let old = layers[index]
    edit(&payload)
    var clip = old
    clip.payload = .video(payload)
    clip.timing = V2Timing(start: old.timing.start, duration: newDuration)
    clip = TransformKeyframes.scalingTimes(clip, by: newDuration / old.timing.duration)
    layers[index] = clip

    let lane = layers.filter { $0.order == clip.order && $0.type != "group" }
    let (_, starts) = reflowLane(laneClips: lane, draggedLayerId: clip.id, newDraggedStart: clip.timing.start, newDraggedDuration: newDuration, floorAtZero: false)
    let moved = layers.map { layer -> V2Layer in
        guard layer.id != clip.id, let start = starts[layer.id], start != layer.timing.start else { return layer }
        var shifted = layer
        shifted.timing = V2Timing(start: start, duration: layer.timing.duration)
        return shifted
    }
    return project.withLayers(moved)
}

/// Speed, Normal (user 2026-10-15): one rate for the whole clip, 0.1x ... 9x (`SpeedScale`). The clip keeps the same stretch of source
/// footage - only the time it takes changes: `timing.duration = source span / rate`, `playbackRate` holds the rate (absent = 1x), `trimStart`
/// is untouched, and a speed curve the clip had is dropped. Always computed from the clip as it is *now*, so applying it again (a ruler drag)
/// gives the same result as one step. No-op (fail closed) for anything that is not a video clip.
struct SetClipSpeedCommand: EditorCommand {
    let layerId: String
    let rate: Double

    func apply(to project: V2Project) -> V2Project {
        guard let old = project.layers.first(where: { $0.id == layerId }), case .video(let payload) = old.payload, let span = sourceSpanMs(of: old) else { return project }
        let oldRate = VideoTimeMapping(layer: old)?.rate ?? 1
        let newRate = SpeedScale.snapped(rate)
        guard newRate != oldRate || payload.speedCurve != nil else { return project }
        let newDuration = SpeedScale.duration(sourceMs: span, rate: newRate, fps: project.composition.fps)
        return retimedClip(project, clipId: layerId, newDuration: newDuration) {
            $0.playbackRate = newRate == 1 ? nil : newRate
            $0.speedCurve = nil
        }
    }
}

/// Speed, Curve: a speed that changes along the clip. `points` are in ms of the clip's source stretch (first at 0, last at its end; see
/// `SpeedCurve`); nil, or a curve that is 1x everywhere, removes the curve. The clip's length becomes the time the curve takes to play.
struct SetClipSpeedCurveCommand: EditorCommand {
    let layerId: String
    let points: [V2SpeedPoint]?

    func apply(to project: V2Project) -> V2Project {
        guard let old = project.layers.first(where: { $0.id == layerId }), case .video(let payload) = old.payload, let span = sourceSpanMs(of: old) else { return project }
        guard let points, let curve = SpeedCurve(points: points.map { V2SpeedPoint(sourceMs: $0.sourceMs, rate: SpeedScale.snappedOrExact($0.rate)) }, span: span),
              !curve.points.allSatisfy({ $0.rate == 1 })
        else {
            // No curve: back to a constant 1x.
            guard payload.speedCurve != nil else { return project }
            return SetClipSpeedCommand(layerId: layerId, rate: 1).apply(to: project)
        }
        if payload.speedCurve == curve.points { return project }
        return retimedClip(project, clipId: layerId, newDuration: max(curve.outputDuration, 1000 / max(project.composition.fps, 1))) {
            $0.speedCurve = curve.points
            $0.playbackRate = nil
        }
    }
}

extension RulerMapping {
    /// The Speed ruler: 0.1x ... 9x, one tick per 0.1x, a major tick at every whole number (1x, 2x, ...). Values are exact tenths.
    static var speed: RulerMapping {
        let count = Int(((SpeedScale.maximum - SpeedScale.minimum) * 10).rounded()) + 1
        func clamp(_ i: Int) -> Int { min(max(i, 0), count - 1) }
        return RulerMapping(
            tickCount: count,
            value: { i in SpeedScale.snapped(SpeedScale.minimum + Double(clamp(i)) / 10) },
            index: { v in clamp(Int(((v - SpeedScale.minimum) * 10).rounded())) },
            isMajor: { i in (i + 1) % 10 == 0 }
        )
    }
}
