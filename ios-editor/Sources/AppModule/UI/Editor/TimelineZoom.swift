import Foundation

/// Pure rules for the timeline's pinch-to-zoom: how far it may zoom, and how
/// the ruler picks its dot spacing so it stays readable at any scale.
/// `pxPerMs` is the one number everything in the timeline is laid out from.
/// Zoom is continuous; the ruler snaps to round times (it does not follow the
/// filmstrip tiles — they may or may not line up with a dot, user 2026-10-10).
///
/// The two zoom limits are defined by what the ruler shows there, as the user
/// specified (2026-10-09):
/// - **fully zoomed out:** dots are **5 seconds** apart;
/// - **fully zoomed in:** dots are **one frame** apart.
/// Both at the same minimum on-screen dot spacing (`minorSpacingPx`), so the
/// limits are `minorSpacingPx / 5000 ms` and `minorSpacingPx / one frame`.
enum TimelineZoom {
    /// Half a second per 48 pt — close to CapCut's default zoom.
    static let defaultPxPerMs = minorSpacingPx / 500
    /// Closest two dots may sit on screen.
    static let minorSpacingPx = 48.0
    /// Dot spacing at the farthest zoom-out.
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

    /// Candidate dot spacings, finest first. Dense (neighbours at most ~2.5× apart)
    /// so dots stay about 48–120 pt apart at every zoom, and chosen so that twice
    /// each one is a round label time (6f, 10f, 15f → 0.5 s, 1 s, 4 s, 10 s…).
    private static func ladder(fps: Double) -> [Double] {
        let frame = frameMs(fps: fps)
        // 10 frames only where it is shorter than 250 ms (60 fps): at 30 fps it would put
        // labels on 20f/40f, which read badly.
        let tenFrames = frame * 10 < 250 ? [frame * 10] : []
        return Array(Set([frame, frame * 2, frame * 3, frame * 5, 250, 500, 1000, 2000, 5000] + tenFrames))
            .filter { $0 <= farthestMinorMs }
            .sorted()
    }

    /// Exactly one dot between two labels, at every zoom: labels sit on every second dot.
    static func rulerIntervals(pxPerMs: Double, fps: Double) -> RulerIntervals {
        let minors = ladder(fps: fps)
        let minor = minors.first { $0 * pxPerMs >= minorSpacingPx - 1e-9 } ?? minors[minors.count - 1]
        return RulerIntervals(minorMs: minor, majorMs: minor * 2)
    }

    /// `mm:ss` on a whole second, otherwise the frame within the second (`2f`, `15f`),
    /// as CapCut labels the ruler once ticks are closer than a second.
    static func rulerLabel(ms: Double, majorMs: Double, fps: Double) -> String {
        let totalFrames = Int((max(ms, 0) / 1000 * fps).rounded())
        let framesPerSecond = max(Int(fps.rounded()), 1)
        let frame = totalFrames % framesPerSecond
        if frame == 0 || majorMs >= 1000 {
            let seconds = totalFrames / framesPerSecond
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        return "\(frame)f"
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

/// Rules for the lanes below the main (primary video) lane, which stays pinned
/// like in CapCut. Those lanes sit in a native vertical `ScrollView`; the
/// timeline's own drag gesture only scrubs, so it locks the drag's axis from
/// the first few points and ignores vertical ones. Pure, so it is unit-tested.
enum LaneScroll {
    enum Axis: Equatable {
        case horizontal, vertical
    }

    /// Movement needed before a drag commits to an axis when the lanes can scroll.
    static let directionLockPx: CGFloat = 4

    /// How far the lanes can scroll: 0 when everything fits (then nothing
    /// scrolls, like a browser), otherwise the overflow.
    static func maxOffset(contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    /// nil = not decided yet. With nothing to scroll the drag is always a
    /// scrub, immediately, so the common case has no dead zone.
    static func axis(forTranslation translation: CGSize, canScrollVertically: Bool) -> Axis? {
        guard canScrollVertically else { return .horizontal }
        guard max(abs(translation.width), abs(translation.height)) >= directionLockPx else { return nil }
        return abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
    }
}
