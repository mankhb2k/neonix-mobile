import AVFoundation
import QuartzCore

/// How much slack a scrub seek may take around its target (the rest seek is
/// always exact). A looser tolerance lets AVFoundation stop at a nearby
/// keyframe (cheap, but the picture can be up to that far from the playhead).
///
/// Two policies exist so they can be A/B-tested on a device — see
/// `PLAYBACK_PIPELINE.md` § 13. Default is the fixed 0.2 s used since the
/// pipeline simplification. Debug builds read `PLAYBACK_SCRUB_TOLERANCE`:
/// `"0.2"` (fixed seconds, `"0"` = always exact) or `"prop:1.5"` (slack equal
/// to 1.5 display frames of playhead motion, capped at 0.2 s).
struct ScrubTolerancePolicy: Equatable {
    enum Kind: Equatable {
        case fixed(seconds: Double)
        case proportional(frames: Double, capSeconds: Double)
    }

    var kind = Kind.fixed(seconds: 0.2)

    static var current: ScrubTolerancePolicy {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["PLAYBACK_SCRUB_TOLERANCE"] {
            return ScrubTolerancePolicy(parsing: raw) ?? ScrubTolerancePolicy()
        }
        #endif
        return ScrubTolerancePolicy()
    }

    init(kind: Kind = .fixed(seconds: 0.2)) { self.kind = kind }

    init?(parsing raw: String) {
        if raw.hasPrefix("prop:"), let frames = Double(raw.dropFirst(5)), frames >= 0 {
            kind = .proportional(frames: frames, capSeconds: 0.2)
        } else if let seconds = Double(raw), seconds >= 0 {
            kind = .fixed(seconds: seconds)
        } else {
            return nil
        }
    }

    /// `speedMsPerSecond` is how fast the playhead is moving in content time.
    func seconds(forSpeedMsPerSecond speed: Double, refreshHz: Double = 60) -> Double {
        switch kind {
        case .fixed(let seconds):
            return seconds
        case .proportional(let frames, let cap):
            return min(cap, frames * (abs(speed) / 1000) / refreshHz)
        }
    }
}

/// Serializes AVPlayer seeks while keeping only the newest requested target.
///
/// A drag can generate many target times before AVFoundation finishes one
/// seek. Starting another seek immediately cancels the previous one, which
/// produces a lot of seeking but very few displayed frames. This coordinator
/// lets one seek finish, then performs only the latest target that arrived in
/// the meantime.
@MainActor
final class PlayerSeekCoordinator {
    private struct Request {
        let id: UInt64
        let time: CMTime
        let toleranceBefore: CMTime
        let toleranceAfter: CMTime
        let completion: ((Bool) -> Void)?
        let requestedAt: CFTimeInterval
    }

    private let player: AVPlayer
    private var nextID: UInt64 = 0
    private var activeID: UInt64?
    private var pending: Request?

    private(set) var isSeekInProgress = false

    /// Where the last completed seek actually put the player (source seconds).
    /// `AVPlayer.currentTime()` already reports a seek's *target* while the
    /// seek is still running, so metrics read this instead to know which frame
    /// is really on screen.
    private(set) var lastLandedSeconds: Double?

    /// For `PlaybackMetrics` only. The display shows the frame of the last
    /// seek that completed; while anything is still unserved, that frame's
    /// request time tells how stale the picture is.
    private var lastDisplayedRequestAt: CFTimeInterval?
    /// When the current stretch of unserved seeks began. Age is measured from
    /// here (or from the last seek that landed inside the stretch), never from
    /// a seek that landed before an idle gap — the first version of this
    /// metric did, and reported the length of the idle gap as "staleness".
    private var unservedSince: CFTimeInterval?

    var hasUnserved: Bool { isSeekInProgress || pending != nil }

    func displayAgeMs(now: CFTimeInterval) -> Double? {
        guard hasUnserved else { return 0 }
        let reference = max(lastDisplayedRequestAt ?? 0, unservedSince ?? 0)
        guard reference > 0 else { return nil }
        return max(0, (now - reference) * 1000)
    }

    init(player: AVPlayer) {
        self.player = player
    }

    /// Queues a seek. If another seek is running, this replaces the previous
    /// pending target instead of interrupting the active AVFoundation seek.
    func request(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completion: ((Bool) -> Void)? = nil
    ) {
        nextID &+= 1
        let request = Request(
            id: nextID,
            time: time,
            toleranceBefore: toleranceBefore,
            toleranceAfter: toleranceAfter,
            completion: completion,
            requestedAt: CACurrentMediaTime()
        )
        if !hasUnserved { unservedSince = request.requestedAt }
        PlaybackMetrics.shared.count(.seekRequested)

        guard !isSeekInProgress else {
            if pending != nil { PlaybackMetrics.shared.count(.seekSuperseded) }
            pending = request
            return
        }
        perform(request)
    }

    func request(
        seconds: Double,
        toleranceSeconds: Double,
        completion: ((Bool) -> Void)? = nil
    ) {
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        let tolerance = CMTime(seconds: max(toleranceSeconds, 0), preferredTimescale: 600)
        request(
            to: time,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance,
            completion: completion
        )
    }

    /// Cancels queued work and invalidates the completion of the active seek.
    /// AVFoundation may still invoke its old completion, but that completion
    /// is ignored by the active request ID check.
    func cancelPendingSeeks() {
        if hasUnserved { PlaybackMetrics.shared.count(.seekCancelled) }
        unservedSince = nil
        pending = nil
        activeID = nil
        isSeekInProgress = false
        player.currentItem?.cancelPendingSeeks()
    }

    private func perform(_ request: Request) {
        activeID = request.id
        isSeekInProgress = true
        let startedAt = CACurrentMediaTime()

        player.seek(
            to: request.time,
            toleranceBefore: request.toleranceBefore,
            toleranceAfter: request.toleranceAfter
        ) { [weak self] finished in
            let finishedAt = CACurrentMediaTime()
            Task { @MainActor in
                guard let self, self.activeID == request.id else { return }
                let metrics = PlaybackMetrics.shared
                metrics.count(.seekCompleted)
                metrics.record(.seekServiceMs, ms: (finishedAt - startedAt) * 1000)
                metrics.record(.seekEndToEndMs, ms: (finishedAt - request.requestedAt) * 1000)
                metrics.record(.seekHopMs, ms: (CACurrentMediaTime() - finishedAt) * 1000)
                self.lastDisplayedRequestAt = request.requestedAt
                if finished {
                    let landed = self.player.currentTime().seconds
                    if landed.isFinite {
                        self.lastLandedSeconds = landed
                        metrics.record(.seekLandingErrorMs, ms: abs(landed - request.time.seconds) * 1000)
                    }
                }

                self.activeID = nil
                self.isSeekInProgress = false

                if let next = self.pending {
                    self.pending = nil
                    self.perform(next)
                } else {
                    self.unservedSince = nil
                    request.completion?(finished)
                }
            }
        }
    }
}
