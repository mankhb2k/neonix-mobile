import AVFoundation

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
        seekCoordinator.request(
            seconds: seconds,
            toleranceSeconds: toleranceSeconds,
            completion: completion
        )
    }

    func play(rate: Float = 1) {
        player.rate = rate
    }

    /// Keeps a playing clip on its speed curve: the rate is only touched when it is off by more than 3 % (each change costs the system ~150-300 ms
    /// to show in the clock, PLAYBACK_PIPELINE.md §9 2026-10-15), so a gentle curve changes it a few times a second at most.
    func follow(rate: Float) {
        guard player.rate != 0, rate > 0, abs(player.rate - rate) / rate > 0.03 else { return }
        player.rate = rate
    }

    func pause() {
        player.pause()
    }

    func cancelPendingSeeks() {
        seekCoordinator.cancelPendingSeeks()
    }
}
