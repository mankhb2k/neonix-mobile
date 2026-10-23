import AVFoundation
import QuartzCore

/// A long-lived player for one video layer. The player is deliberately kept
/// alive while the playhead moves so AVFoundation can reuse its decoder and
/// buffered state instead of rebuilding an item for every scrub tick.
@MainActor
final class StagePlayerSession {
    let layerId: String
    let assetId: String
    let url: URL
    let player: AVPlayer
    let seekCoordinator: PlayerSeekCoordinator

    init(layerId: String, assetId: String, url: URL) {
        self.layerId = layerId
        self.assetId = assetId
        self.url = url
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = false
        // Video audio is represented by the project's extracted derivative
        // and mixed by AudioMixEngine. Muting the visual player prevents the
        // native item from bypassing timeline trims/gain/fades and playing a
        // second, unsynchronised copy underneath the editor mix.
        player.volume = 0
        self.player = player
        self.seekCoordinator = PlayerSeekCoordinator(player: player)
        PlaybackMetrics.shared.track(.stageSession, 1)
    }

    deinit {
        PlaybackMetrics.shared.track(.stageSession, -1)
    }

    var currentSourceSeconds: Double? {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return nil }
        return seconds
    }

    func seek(
        toSourceSeconds seconds: Double,
        toleranceSeconds: Double,
        completion: ((Bool) -> Void)? = nil
    ) {
        let requestedAt = CACurrentMediaTime()
        seekCoordinator.request(
            seconds: seconds,
            toleranceSeconds: toleranceSeconds,
            completion: { [weak self] finished in
                guard let self else { completion?(finished); return }
                SplitPlaybackDiagnostics.log(
                    "seek.complete layer=\(self.layerId) asset=\(self.assetId) target=\(String(format: "%.4f", seconds)) landed=\(String(format: "%.4f", self.currentSourceSeconds ?? .nan)) finished=\(finished) elapsedMs=\(String(format: "%.1f", (CACurrentMediaTime() - requestedAt) * 1000)) item=\(self.player.currentItem?.status.rawValue ?? -1) timeControl=\(self.player.timeControlStatus.rawValue) waiting=\(self.player.reasonForWaitingToPlay?.rawValue ?? "none") bufferEmpty=\(self.player.currentItem?.isPlaybackBufferEmpty ?? false) likelyToKeepUp=\(self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false)"
                )
                completion?(finished)
            }
        )
        SplitPlaybackDiagnostics.log(
            "seek.request layer=\(layerId) asset=\(assetId) target=\(String(format: "%.4f", seconds)) tolerance=\(String(format: "%.4f", toleranceSeconds)) item=\(player.currentItem?.status.rawValue ?? -1)"
        )
    }

    func play(rate: Float = 1) {
        PlaybackMetrics.shared.count(.playerRateSetCalls)
        guard player.rate != rate else { return }
        PlaybackMetrics.shared.count(.playerRateWrites)
        player.rate = rate
    }

    func startSynchronized(rate: Float, sourceSeconds: Double, atHostTime hostTime: CMTime) {
        let leadMs = CMTimeGetSeconds(hostTime - CMClockGetTime(CMClockGetHostTimeClock())) * 1000
        PlaybackMetrics.shared.count(.playerRateSetCalls)
        PlaybackMetrics.shared.count(.playerRateWrites)
        player.setRate(rate,
                       time: CMTime(seconds: sourceSeconds, preferredTimescale: 60_000),
                       atHostTime: hostTime)
        SplitPlaybackDiagnostics.log(
            "scheduled.start layer=\(layerId) source=\(String(format: "%.4f", sourceSeconds)) leadMs=\(String(format: "%.1f", leadMs))"
        )
    }

    /// Keeps a playing clip on its speed curve: the rate is only touched when it is off by more than 3 % (each change costs the system ~150-300 ms
    /// to show in the clock, PLAYBACK_PIPELINE.md §9 2026-10-15), so a gentle curve changes it a few times a second at most.
    func follow(rate: Float) {
        guard player.rate != 0, rate > 0, abs(player.rate - rate) / rate > 0.03 else { return }
        PlaybackMetrics.shared.count(.playerRateWrites)
        player.rate = rate
    }

    func pause() {
        player.pause()
    }

    /// Prime a paused, already positioned item before its timeline cut.
    /// AVPlayer throws if preroll is requested before it is ready to play.
    func preroll(atRate rate: Float, completion: @escaping (Bool) -> Void) {
        guard player.status == .readyToPlay, player.rate == 0 else {
            completion(false)
            return
        }
        let requestedAt = CACurrentMediaTime()
        player.preroll(atRate: rate) { [weak self] finished in
            Task { @MainActor in
                guard let self else { completion(false); return }
                SplitPlaybackDiagnostics.log(
                    "preroll.complete layer=\(self.layerId) finished=\(finished) elapsedMs=\(String(format: "%.1f", (CACurrentMediaTime() - requestedAt) * 1000))"
                )
                completion(finished)
            }
        }
    }

    func cancelPendingPrerolls() {
        player.cancelPendingPrerolls()
    }

    func cancelPendingSeeks() {
        seekCoordinator.cancelPendingSeeks()
    }
}

/// Opt-in player trace for reproducing split seams. Launch Debug with
/// `PLAYBACK_SPLIT_DIAGNOSTICS=1`; it logs only seek and master handoff events.
enum SplitPlaybackDiagnostics {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["PLAYBACK_SPLIT_DIAGNOSTICS"] == "1"
        #else
        false
        #endif
    }

    static func log(_ message: String) {
        guard enabled else { return }
        NSLog("[SplitPreview] %@", message as NSString)
    }
}
