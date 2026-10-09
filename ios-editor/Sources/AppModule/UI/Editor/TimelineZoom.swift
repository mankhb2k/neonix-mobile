import Foundation

/// Pure rules for the timeline's pinch-to-zoom: how far it may zoom, and how
/// the ruler picks its tick spacing so it stays readable at any scale.
/// `pxPerMs` is the one number everything in the timeline is laid out from
/// (0.2 px/ms = 200 px per second was the fixed scale before zoom existed).
///
/// The two zoom limits are defined by what the ruler shows there, as the user
/// specified (2026-10-09):
/// - **fully zoomed out:** minor ticks are **5 seconds** apart;
/// - **fully zoomed in:** minor ticks are **one frame** apart.
/// Both at the same minimum on-screen tick spacing (`minorSpacingPx`), so the
/// limits are `minorSpacingPx / 5000 ms` and `minorSpacingPx / one frame`.
enum TimelineZoom {
    static let defaultPxPerMs = 0.2
    /// Closest two minor ticks may sit on screen.
    static let minorSpacingPx = 48.0
    /// Closest two labelled ticks may sit (room for a `mm:ss:ff` label).
    static let majorSpacingPx = 96.0
    /// Minor tick spacing at the farthest zoom-out.
    static let farthestMinorMs = 5000.0

    static let minPxPerMs = minorSpacingPx / farthestMinorMs

    static func frameMs(fps: Double) -> Double {
        1000 / max(fps, 1)
    }

    /// One frame is `minorSpacingPx` wide.
    static func maxPxPerMs(fps: Double) -> Double {
        minorSpacingPx / frameMs(fps: fps)
    }

    static func range(fps: Double) -> ClosedRange<Double> {
        minPxPerMs...maxPxPerMs(fps: fps)
    }

    static func clamped(_ pxPerMs: Double, fps: Double) -> Double {
        let bounds = range(fps: fps)
        return min(max(pxPerMs, bounds.lowerBound), bounds.upperBound)
    }

    // MARK: Ruler

    struct RulerIntervals: Equatable {
        let minorMs: Double
        let majorMs: Double
    }

    /// Candidate tick intervals, finest first: 1/2/5 frames, then round times.
    private static func ladder(fps: Double) -> [Double] {
        let frame = frameMs(fps: fps)
        return [frame, frame * 2, frame * 5, 500, 1000, 2000, 5000, 10_000, 20_000, 30_000, 60_000, 120_000, 300_000]
    }

    static func rulerIntervals(pxPerMs: Double, fps: Double) -> RulerIntervals {
        let candidates = ladder(fps: fps)
        let epsilon = 1e-9
        let minor = candidates.first { $0 * pxPerMs >= minorSpacingPx - epsilon }
            ?? candidates[candidates.count - 1]
        func isMultiple(_ value: Double) -> Bool {
            let ratio = value / minor
            return abs(ratio - ratio.rounded()) < 1e-6
        }
        let major = candidates.first {
            $0 >= minor * 2 - epsilon && $0 * pxPerMs >= majorSpacingPx - epsilon && isMultiple($0)
        } ?? minor * max((majorSpacingPx / (minor * pxPerMs)).rounded(.up), 2)
        return RulerIntervals(minorMs: minor, majorMs: major)
    }

    /// `mm:ss` for whole-second labels; `mm:ss:ff` (frame within the second)
    /// once the label interval is below a second.
    static func rulerLabel(ms: Double, majorMs: Double, fps: Double) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        if majorMs >= 1000 {
            return String(format: "%02d:%02d", minutes, seconds)
        }
        let fraction = totalSeconds - totalSeconds.rounded(.down)
        let frame = min(Int((fraction * fps).rounded()), Int(fps.rounded()) - 1)
        return String(format: "%02d:%02d:%02d", minutes, seconds, frame)
    }

    // MARK: Visible window

    /// The slice of the timeline (in ms) that gets drawn: the playhead's
    /// position padded by a whole viewport each side, snapped outward to
    /// viewport-wide steps. Snapping means the value only changes when the
    /// playhead travels a full viewport, not on every scrub tick — so views
    /// that take it as input (filmstrip tiles, ruler) aren't re-planned per
    /// frame. At full zoom-in the timeline is ~45 000 pt wide; only this
    /// window of it is ever built.
    static func visibleWindowMs(currentTimeMs: Double, viewportWidth: Double, pxPerMs: Double) -> ClosedRange<Double> {
        let step = max(viewportWidth / pxPerMs, 1)
        let lower = ((currentTimeMs - step) / step).rounded(.down) * step
        let upper = ((currentTimeMs + step) / step).rounded(.up) * step
        return lower...upper
    }
}

/// Vertical scrolling of the lanes below the main (primary video) lane, which
/// stays pinned like in CapCut. The timeline has one drag gesture for both
/// scrubbing (horizontal) and lane scrolling (vertical); the axis is locked
/// from the first few points of movement. Pure, so it is unit-tested.
enum LaneScroll {
    enum Axis: Equatable {
        case horizontal, vertical
    }

    /// Movement needed before a drag commits to an axis when the lanes can scroll.
    static let directionLockPx: CGFloat = 4

    static func maxOffset(contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    static func clamped(_ offset: CGFloat, maxOffset: CGFloat) -> CGFloat {
        min(max(offset, 0), maxOffset)
    }

    /// nil = not decided yet. With nothing to scroll the drag is always a
    /// scrub, immediately, so the common case has no dead zone.
    static func axis(forTranslation translation: CGSize, canScrollVertically: Bool) -> Axis? {
        guard canScrollVertically else { return .horizontal }
        guard max(abs(translation.width), abs(translation.height)) >= directionLockPx else { return nil }
        return abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
    }
}
