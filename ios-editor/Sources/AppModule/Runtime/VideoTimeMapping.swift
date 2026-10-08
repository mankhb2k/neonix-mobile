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
    let rate: Double

    init?(layer: V2Layer) {
        guard case .video(let payload) = layer.payload else { return nil }
        layerStartMs = layer.timing.start
        durationMs = layer.timing.duration
        trimStartMs = payload.trimStart ?? 0
        let authoredRate = payload.playbackRate ?? 1
        rate = authoredRate > 0 ? authoredRate : 1
    }

    /// Source position shown at timeline time `ms`, clamped to the clip's own
    /// time range.
    func sourceMs(atTimelineMs ms: Double) -> Double {
        trimStartMs + min(max(ms - layerStartMs, 0), durationMs) * rate
    }

    /// Inverse of `sourceMs(atTimelineMs:)`, unclamped — used to follow a
    /// playing `AVPlayer`'s source clock back onto the timeline.
    func timelineMs(atSourceMs sourceMs: Double) -> Double {
        layerStartMs + (sourceMs - trimStartMs) / rate
    }

    /// Two clips of the same asset play as one uninterrupted stretch of the
    /// source (e.g. the two halves of a split) — a playing player can carry
    /// straight across the boundary without re-seeking.
    func isContinuous(with other: VideoTimeMapping) -> Bool {
        rate == other.rate
            && abs((layerStartMs - trimStartMs / rate) - (other.layerStartMs - other.trimStartMs / other.rate)) < 1
    }
}
