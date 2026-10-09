import Foundation
import UIKit

/// Release-momentum curve for the timeline, shaped like `UIScrollView`'s.
///
/// `UIScrollView` multiplies its velocity by `decelerationRate` every
/// *millisecond* (`.normal` ≈ 0.998, `.fast` ≈ 0.99). That is an exponential
/// decay with continuous rate `k = -1000·ln(rate)` per second, which has a
/// closed form for both speed and distance travelled, so the position at any
/// instant is computed directly from elapsed time instead of integrating frame
/// by frame (no drift when a frame is late).
///
/// The per-millisecond reading of the constant is the community's
/// reverse-engineering of UIKit, not something Apple documents — but the
/// constant itself is taken from the live `UIScrollView.DecelerationRate`
/// value, so if Apple retunes it this follows.
///
/// The previous hand-tuned curve (`0.04` of the speed left after one second,
/// `k ≈ 3.2`/s) lost 96% of the release speed in the first second; `.normal`
/// (`k ≈ 2.0`/s) loses 86% and travels about 1.6× as far for the same flick —
/// the difference between "gets braked" and "keeps gliding".
struct MomentumDecay: Equatable {
    /// Fraction of velocity kept after one millisecond.
    let retentionPerMillisecond: Double

    static var iosNormal: MomentumDecay {
        MomentumDecay(retentionPerMillisecond: Double(UIScrollView.DecelerationRate.normal.rawValue))
    }

    /// The same curve with its decay constant multiplied by `scale`
    /// (`< 1` glides longer, `> 1` brakes sooner): retention^scale.
    func scalingFriction(by scale: Double) -> MomentumDecay {
        MomentumDecay(retentionPerMillisecond: pow(retentionPerMillisecond, scale))
    }

    /// Continuous decay constant, per second.
    var rate: Double { -1000 * log(retentionPerMillisecond) }

    func velocity(initial: Double, after seconds: Double) -> Double {
        initial * exp(-rate * seconds)
    }

    /// Signed distance travelled `seconds` after release.
    func distance(initial: Double, after seconds: Double) -> Double {
        initial * (1 - exp(-rate * seconds)) / rate
    }

    /// Where a release at `initial` would come to rest if nothing stopped it.
    func totalDistance(initial: Double) -> Double {
        initial / rate
    }

    /// Seconds until the speed falls to `speed`; 0 if it starts at or below it.
    func duration(initial: Double, until speed: Double) -> Double {
        let start = abs(initial)
        guard start > speed, speed > 0 else { return 0 }
        return log(start / speed) / rate
    }
}

/// Re-derives a drag's release speed from its own recent samples, so a log can
/// show whether `DragGesture.Value.velocity` agrees with what the finger
/// actually did (see `release_est_px_s` in `PLAYBACK_PIPELINE.md`). Pure.
struct ReleaseVelocityEstimator {
    struct Sample {
        let time: Double
        let x: Double
    }

    /// Only the last `window` seconds before the final sample count.
    static let window = 0.1
    private static let capacity = 16
    private(set) var samples: [Sample] = []

    mutating func add(time: Double, x: Double) {
        samples.append(Sample(time: time, x: x))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    mutating func reset() { samples.removeAll(keepingCapacity: true) }

    /// Points/sec over the last `window` seconds; nil with fewer than two
    /// samples in range (a single event carries no speed).
    var pointsPerSecond: Double? {
        guard let last = samples.last else { return nil }
        guard let first = samples.first(where: { last.time - $0.time <= Self.window }),
              last.time > first.time else { return nil }
        return (last.x - first.x) / (last.time - first.time)
    }

    /// Seconds from the last sample to `now` — how long the finger sat still
    /// before lifting.
    func holdSeconds(now: Double) -> Double? {
        samples.last.map { now - $0.time }
    }
}

/// How far a release glides, tuned on a real iPhone (2026-10-09): with the
/// plain `UIScrollView` curve a finger flick (~900 pt/s median) travelled only
/// ~1.2 screen widths while a simulator mouse flick (~3200 pt/s) travelled ~4,
/// which felt "slow" on the device. These two values were picked by feel, not
/// derived from a benchmark — see `PLAYBACK_PIPELINE.md` § 9/§ 10.
///
/// - `velocityGain` multiplies the speed at lift (2 = twice as far, and
///   twice as fast the instant the finger leaves).
/// - `frictionScale` multiplies the decay constant (0.7 = glides longer
///   without adding release speed).
///
/// Distance travelled ≈ `velocityGain · v / (frictionScale · k)`.
struct CoastTuning: Equatable {
    var velocityGain = 2.0
    var frictionScale = 0.7

    var decay: MomentumDecay { MomentumDecay.iosNormal.scalingFriction(by: frictionScale) }
}
