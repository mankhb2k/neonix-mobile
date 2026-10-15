import Foundation

/// The one place that converts between timeline time (`currentTimeMs`) and a
/// video layer's *source* time (a position inside its asset file).
///
/// A clip shows source `trimStart` at timeline `timing.start`, and advances
/// through the source at `playbackRate`. Everything that picks a frame from
/// the file — Stage scrub, Stage playback, filmstrip tiles, cover image —
/// goes through this instead of using `atMs - timing.start` directly, which
/// silently ignored `trimStart` and showed the wrong frames after a left
/// trim or for any clip not starting at source 0 (e.g. a split's 2nd half).
///
/// Editing commands (`SplitClipCommand`, trim handles) still assume a rate
/// of 1 when they adjust `trimStart`/`trimEnd`; nothing authors a
/// `playbackRate` yet.
struct VideoTimeMapping: Equatable {
    let layerStartMs: Double
    let durationMs: Double
    let trimStartMs: Double
    /// The constant speed - or, for a clip with a speed curve, its average (source stretch / length), which is what the filmstrip lays its tiles by.
    let rate: Double
    /// A speed that changes along the clip (`V2VideoPayload.speedCurve`); nil = constant `rate`.
    let curve: SpeedCurve?

    init?(layer: V2Layer) {
        guard case .video(let payload) = layer.payload else { return nil }
        layerStartMs = layer.timing.start
        durationMs = layer.timing.duration
        trimStartMs = payload.trimStart ?? 0
        if let points = payload.speedCurve, let last = points.last, let curve = SpeedCurve.cached(points: points, span: last.sourceMs) {
            self.curve = curve
            rate = curve.span / max(curve.outputDuration, 1e-6)
        } else {
            self.curve = nil
            let authoredRate = payload.playbackRate ?? 1
            rate = authoredRate > 0 ? authoredRate : 1
        }
    }

    /// Source position shown at timeline time `ms`, clamped to the clip's own
    /// time range.
    func sourceMs(atTimelineMs ms: Double) -> Double {
        let elapsed = min(max(ms - layerStartMs, 0), durationMs)
        if let curve { return trimStartMs + curve.sourceMs(atOutput: elapsed) }
        return trimStartMs + elapsed * rate
    }

    /// Inverse of `sourceMs(atTimelineMs:)`, unclamped (for a curve: clamped into the clip) - used to follow a
    /// playing `AVPlayer`'s source clock back onto the timeline.
    func timelineMs(atSourceMs sourceMs: Double) -> Double {
        if let curve { return layerStartMs + curve.outputMs(atSource: sourceMs - trimStartMs) }
        return layerStartMs + (sourceMs - trimStartMs) / rate
    }

    // MARK: Trim handles (timeline ms <-> source ms at a clip edge)

    /// Source ms the clip's start moves by when its head edge moves `delta` timeline ms later (positive removes footage, negative
    /// reveals earlier footage at the first speed).
    func headSource(forTimeline delta: Double) -> Double {
        guard let curve else { return delta * rate }
        return delta >= 0 ? curve.sourceMs(atOutput: delta) : delta * curve.points[0].rate
    }

    /// Inverse of `headSource(forTimeline:)`.
    func headTimeline(forSource delta: Double) -> Double {
        guard let curve else { return delta / rate }
        return delta >= 0 ? curve.outputMs(atSource: delta) : delta / curve.points[0].rate
    }

    /// Source ms the clip's end moves by when its tail edge moves `delta` timeline ms later (positive reveals later footage at the last
    /// speed, negative removes footage).
    func tailSource(forTimeline delta: Double) -> Double {
        guard let curve else { return delta * rate }
        return delta >= 0 ? delta * curve.points[curve.points.count - 1].rate : curve.sourceMs(atOutput: durationMs + delta) - curve.span
    }

    /// Inverse of `tailSource(forTimeline:)`.
    func tailTimeline(forSource delta: Double) -> Double {
        guard let curve else { return delta / rate }
        return delta >= 0 ? delta / curve.points[curve.points.count - 1].rate : curve.outputMs(atSource: curve.span + delta) - durationMs
    }

    /// The speed at timeline time `ms` (the constant rate unless the clip has a curve).
    func rate(atTimelineMs ms: Double) -> Double {
        guard let curve else { return rate }
        return curve.rate(atSource: curve.sourceMs(atOutput: min(max(ms - layerStartMs, 0), durationMs)))
    }

    /// Two clips of the same asset play as one uninterrupted stretch of the
    /// source (e.g. the two halves of a split) — a playing player can carry
    /// straight across the boundary without re-seeking.
    func isContinuous(with other: VideoTimeMapping) -> Bool {
        curve == nil && other.curve == nil
            && rate == other.rate
            && abs((layerStartMs - trimStartMs / rate) - (other.layerStartMs - other.trimStartMs / other.rate)) < 1
    }
}
