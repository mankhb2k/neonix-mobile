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

/// How far a release glides, tuned on a real iPhone (2026-10-09; gain raised 2 → 4, then set to 3.5
/// the same day at the user's request): with the
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
/// - `brakeFrictionScale` multiplies the *coasting* decay constant while a finger
///   touches down on a coast: it keeps the current speed but loses it ~20× faster,
///   so the glide stops in about 0.1–0.25 s (the time grows only with the log of the
///   speed) instead of cutting dead. Also picked by feel.
///
/// Distance travelled ≈ `velocityGain · v / (frictionScale · k)`.
struct CoastTuning: Equatable {
    var velocityGain = 3.3
    var frictionScale = 0.7
    var brakeFrictionScale = 20.0

    var decay: MomentumDecay { MomentumDecay.iosNormal.scalingFriction(by: frictionScale) }
    var brakeDecay: MomentumDecay { decay.scalingFriction(by: brakeFrictionScale) }
}

/// Debug-only log of every timeline release (finger speed, hold before lift, whether it
/// coasted) to `Documents/release_log.csv` + `NSLog`, so the "no glide when held" threshold
/// is picked from real-device numbers (`PLAYBACK_PIPELINE.md` § 10). Independent of the HUD.
enum ReleaseLog {
    static func append(fingerPxPerSecond: Double, estimatedPxPerSecond: Double?, holdMs: Double?,
                       pxPerMs: Double, coasted: Bool) {
        #if DEBUG
        func f(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "" }
        let line = "\(Date().timeIntervalSince1970),\(f(fingerPxPerSecond)),\(f(estimatedPxPerSecond)),\(f(holdMs)),"
            + "\(String(format: "%.4f", pxPerMs)),\(coasted ? 1 : 0)\n"
        NSLog("release_log finger=%@ est=%@ hold=%@ pxPerMs=%.4f coasted=%d",
              f(fingerPxPerSecond), f(estimatedPxPerSecond), f(holdMs), pxPerMs, coasted ? 1 : 0)
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("release_log.csv")
        let header = "unix_time,finger_px_s,est_px_s,hold_ms,px_per_ms,coasted\n"
        if !FileManager.default.fileExists(atPath: url.path) { try? header.write(to: url, atomically: true, encoding: .utf8) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
        #endif
    }
}

/// Whether a timeline release glides at all. Thresholds come from the iPhone 13 release log of
/// 2026-10-11 (`PLAYBACK_PIPELINE.md` § 10): slow or held releases were 3-85 pt/s, real flicks
/// 427-1517 pt/s, nothing in between. The old gate (40 ms/s ≈ 3.8 pt/s at the default zoom) let
/// a 5 pt/s lift glide ~12 pt, and it changed with zoom; this one is in screen points.
enum ReleaseGate {
    /// Below this finger speed (pt/s) a lift does not glide.
    static let minimumFlickPxPerSecond = 120.0
    /// A finger that sat still this long before lifting is a hold, not a flick
    /// (`DragGesture.velocity` alone does not decay to 0: 32 pt/s was reported after 409 ms).
    static let maximumHoldSeconds = 0.1

    static func shouldCoast(fingerPxPerSecond: Double, holdSeconds: Double?) -> Bool {
        guard abs(fingerPxPerSecond) >= minimumFlickPxPerSecond else { return false }
        if let hold = holdSeconds, hold > maximumHoldSeconds { return false }
        return true
    }
}
