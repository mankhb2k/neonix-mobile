import Foundation

/// The Speed tool's range and its ruler (user 2026-10-15, after the iPhone 13 measurement in PLAYBACK_PIPELINE.md §9): **0.1x ... 9x**.
/// At 10x and above the system plays a 1080p60 HEVC clip from its key frames only (10 distinct frames a second), at 9.5x it still shows
/// 60, so 9x is the highest speed that stays smooth. The ruler is **linear, one tick = 0.1x** (user 2026-10-15): it opens on 1x, a drag to
/// the left reads 0.9x, 0.8x ... 0.1x and to the right 1.1x, 1.2x ... 9x.
enum SpeedScale {
    static let minimum = 0.1
    static let maximum = 9.0
    /// One notch of the ruler.
    static let step = 0.1

    /// Rounded to a 0.1x notch and kept inside the range.
    static func snapped(_ rate: Double) -> Double {
        clamped((rate * 10).rounded() / 10)   // tenths / 10 is exact where tenths x 0.1 is not (12 x 0.1 = 1.2000000000000002)
    }

    /// A curve's own speeds are continuous (not notched), only kept inside the range.
    static func snappedOrExact(_ rate: Double) -> Double { clamped(rate) }

    static func clamped(_ rate: Double) -> Double { min(max(rate, minimum), maximum) }

    /// "1x", "0.5x", "2.5x".
    static func label(_ rate: Double) -> String {
        let r = (rate * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))x" : String(format: "%.1fx", r)
    }

    /// The length a clip gets at `rate` (never under one frame at the project's frame rate).
    static func duration(sourceMs: Double, rate: Double, fps: Double) -> Double {
        max(sourceMs / clamped(rate), 1000 / max(fps, 1))
    }
}
