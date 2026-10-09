import AVFoundation
import QuartzCore

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

    /// For `PlaybackMetrics` only. The display shows the frame of the last
    /// seek that completed; while anything is still unserved, that frame's
    /// request time tells how stale the picture is.
    private var lastRequestAt: CFTimeInterval?
    private var lastDisplayedRequestAt: CFTimeInterval?

    var hasUnserved: Bool { isSeekInProgress || pending != nil }

    func displayAgeMs(now: CFTimeInterval) -> Double? {
        guard hasUnserved else { return 0 }
        guard let reference = lastDisplayedRequestAt ?? lastRequestAt else { return nil }
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
        lastRequestAt = request.requestedAt
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

                self.activeID = nil
                self.isSeekInProgress = false

                if let next = self.pending {
                    self.pending = nil
                    self.perform(next)
                } else {
                    request.completion?(finished)
                }
            }
        }
    }
}
