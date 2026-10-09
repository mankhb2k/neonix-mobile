import Foundation
import AVFoundation
import QuartzCore
import Observation

/// The editor's one playhead. Owns `currentTimeMs` — nothing else writes it —
/// and everything that moves it: Play/Pause, scrubbing and post-release
/// momentum, all driven by one display-synced clock (`DisplayLinkClock`).
///
/// Play and scrub are the same timeline state machine. Every video layer owns
/// a persistent AVPlayer session; raw layers render through AVPlayerLayer and
/// filtered layers pull CVPixelBuffers into the Metal preview. There is no
/// other decode path (the old `AVAssetReader`/`CGImage` frame server was
/// removed 2026-10-09: it was dead code in the editor). During playback, the
/// player itself is the decode clock.
///
/// ```
/// idle ──play──▶ playing ──pause / reached end──▶ idle
///   │              │
///   └─beginScrub◀──┘ (pauses first)
/// scrubbing ──endScrub(fast)──▶ coasting ──friction runs out──▶ idle
///          └──endScrub(slow)──▶ idle        coasting ──beginScrub──▶ scrubbing
/// ```
@MainActor
@Observable
final class EditorPlaybackEngine {
    enum Mode: Equatable {
        case idle
        case scrubbing
        case coasting
        case playing
    }

    /// The single source of truth for the playhead.
    private(set) var currentTimeMs: Double = 0
    private(set) var mode: Mode = .idle
    private(set) var maxDurationMs: Double = 1

    var isPlaying: Bool { mode == .playing }

    // MARK: Internals

    private struct VideoSource {
        let layerId: String
        let assetId: String
        let url: URL
        let mapping: VideoTimeMapping
    }

    @ObservationIgnored private var videoSources: [VideoSource] = []
    /// `init` only reads the project; the `AVPlayer`s and the audio mix are
    /// created by `prepare()`. `EditorShellView.init` builds an engine every
    /// time the view struct is re-created and SwiftUI keeps only the first, so
    /// an `init` that created players made a second, unused `AVPlayer` per
    /// editor (measured: `sessions_alive` = 2 for one video layer).
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var latestProject: V2Project?
    private(set) var mediaGeneration = 0
    @ObservationIgnored private var stageSessions: [String: StagePlayerSession] = [:]
    @ObservationIgnored private var nativeMasterLayerId: String?
    @ObservationIgnored private var nativeStartGeneration = 0
    @ObservationIgnored private var scrubStartTimeMs: Double = 0
    /// State of the coast in flight (see `MomentumDecay`): position is
    /// computed from these and the elapsed time, never integrated per frame.
    @ObservationIgnored private var coastInitialVelocity: Double = 0
    @ObservationIgnored private var coastStartTimeMs: Double = 0
    @ObservationIgnored private var coastElapsedSeconds: Double = 0
    @ObservationIgnored private let clock = DisplayLinkClock()
    /// Real sound — see `AudioMixEngine`'s own doc comment for the sync
    /// model. Only ever told to play from `playbackTick`/`play()`, never
    /// from scrubbing/coasting.
    @ObservationIgnored private lazy var audioMixEngine = AudioMixEngine()

    /// How far from the requested time a scrub seek may land. Fixed 0.2 s (half
    /// the 0.5 s keyframe spacing of camera footage) unless a Debug env var
    /// selects another policy — see `ScrubTolerancePolicy` and
    /// `PLAYBACK_PIPELINE.md` § 13. At rest the seek is exact (0).
    private let scrubTolerance = ScrubTolerancePolicy.current
    /// A flick slower than this just stops; faster starts a coast.
    private static let minimumCoastMsPerSecond = 40.0
    /// Native scroll-view curve, retuned for glide distance — see `CoastTuning`.
    private let coastTuning = CoastTuning()
    /// The coast ends once it is crawling slower than this (10 px/s at the
    /// timeline's 0.2 px/ms, i.e. ~0.17 px per frame — imperceptible).
    private static let coastStopMsPerSecond = 50.0

    init(project: V2Project) {
        PlaybackMetrics.shared.track(.engine, 1)
        update(project: project)
    }

    deinit {
        PlaybackMetrics.shared.track(.engine, -1)
    }

    /// Call whenever the project changes (edit, undo/redo, live trim drag).
    func update(project: V2Project) {
        latestProject = project
        videoSources = project.layers.compactMap { layer in
            guard case .video(let payload) = layer.payload,
                  let mapping = VideoTimeMapping(layer: layer),
                  let asset = project.assets.first(where: { $0.id == payload.assetId }),
                  case .video(let videoAsset) = asset,
                  let url = bundledURL(filename: videoAsset.uri)
            else { return nil }
            return VideoSource(
                layerId: layer.id,
                assetId: payload.assetId,
                url: url,
                mapping: mapping
            )
        }
        if isPrepared { reconcileStageSessions() }
        mediaGeneration &+= 1
        let layerEnds = project.layers.map { $0.timing.start + $0.timing.duration }
        let audioEnds = project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }
        maxDurationMs = max((layerEnds + audioEnds).max() ?? 1, 1)
        if isPrepared { audioMixEngine.update(project: project) }
    }

    /// Creates the players and the audio mix and positions them at the current
    /// time — call once when the editor appears, so the first frame is ready
    /// before anything moves.
    func prepare() {
        // Registered here, not in `init`: `EditorShellView.init` builds a
        // throwaway engine every time the view struct is re-created, and
        // only the one SwiftUI keeps ever gets `prepare()` called.
        PlaybackMetrics.shared.probe = { [weak self] in self?.metricsProbe() ?? PlaybackMetrics.Probe() }
        isPrepared = true
        if let latestProject { audioMixEngine.update(project: latestProject) }
        reconcileStageSessions()
        mediaGeneration &+= 1
        seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0)
    }

    // MARK: Transport

    func play() {
        guard mode != .playing else { return }
        clock.stop()
        mode = .playing

        if hasVideoAtCurrentTime {
            nativeStartGeneration &+= 1
            let generation = nativeStartGeneration
            nativeMasterLayerId = sourceCovering(timeMs: currentTimeMs)?.layerId
            seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0) { [weak self] finished in
                guard let self,
                      self.mode == .playing,
                      self.nativeStartGeneration == generation,
                      finished
                else { return }
                self.playNativeSessions(atMs: self.currentTimeMs)
                self.audioMixEngine.play(atMs: self.currentTimeMs)
                self.clock.start { [weak self] dt in self?.playbackTick(dt) }
            }
            return
        }

        audioMixEngine.play(atMs: currentTimeMs)
        clock.start { [weak self] dt in self?.playbackTick(dt) }
    }

    func pause() {
        clock.stop()
        nativeStartGeneration &+= 1
        pauseNativeSessions()
        mode = .idle
        audioMixEngine.pause()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    // MARK: Scrubbing

    /// A fresh touch always wins over playback and over a coast still in
    /// flight; `currentTimeMs` is already the true live position, so the new
    /// drag starts exactly where the playhead visibly is. Safe to call on
    /// every drag tick — only the first one in a gesture does anything.
    func beginScrub() {
        guard mode != .scrubbing else { return }
        if mode == .coasting { recordCoastEnd(.interrupted) }
        clock.stop()
        nativeStartGeneration &+= 1
        pauseNativeSessions()
        mode = .scrubbing
        scrubStartTimeMs = currentTimeMs
        // Scrubbing stays silent in this pass (see `AudioMixEngine`'s doc
        // comment) — if Play was already running, stop its audio too.
        audioMixEngine.pause()
    }

    /// Moves the playhead relative to where `beginScrub()` found it.
    func scrub(deltaMs: Double) {
        guard mode == .scrubbing else { return }
        setTime(scrubStartTimeMs + deltaMs)
    }

    /// Moves the playhead to an absolute time (e.g. the fullscreen scrubber).
    func scrub(toMs ms: Double) {
        guard mode == .scrubbing else { return }
        setTime(ms)
    }

    /// `velocityMsPerSecond` is in timeline time (positive = moving forward).
    func endScrub(velocityMsPerSecond: Double) {
        guard mode == .scrubbing else { return }
        guard abs(velocityMsPerSecond) > Self.minimumCoastMsPerSecond else {
            mode = .idle
            settleNativeAtCurrentTime()
            return
        }
        mode = .coasting
        coastInitialVelocity = velocityMsPerSecond * coastTuning.velocityGain
        coastStartTimeMs = currentTimeMs
        coastElapsedSeconds = 0
        PlaybackMetrics.shared.record(.coastReleaseSpeed, ms: abs(velocityMsPerSecond))
        PlaybackMetrics.shared.gauge(.coastGain, coastTuning.velocityGain)
        PlaybackMetrics.shared.gauge(.coastFriction, coastTuning.frictionScale)
        clock.start { [weak self] dt in self?.coastTick(dt) }
    }

    // MARK: Ticks

    private func coastTick(_ dt: Double) {
        guard mode == .coasting else { return }
        PlaybackMetrics.shared.record(.coastTickMs, ms: dt * 1000)
        coastElapsedSeconds += dt
        let decay = coastTuning.decay
        let target = coastStartTimeMs + decay.distance(initial: coastInitialVelocity, after: coastElapsedSeconds)
        let bounded = clamped(target)
        setTime(bounded)
        let speed = abs(decay.velocity(initial: coastInitialVelocity, after: coastElapsedSeconds))
        let hitEdge = bounded != target
        if hitEdge || speed < Self.coastStopMsPerSecond {
            recordCoastEnd(hitEdge ? .edge : .friction)
            clock.stop()
            mode = .idle
            settleNativeAtCurrentTime()
        }
    }

    private enum CoastEnd { case friction, edge, interrupted }

    private func recordCoastEnd(_ reason: CoastEnd) {
        let metrics = PlaybackMetrics.shared
        switch reason {
        case .friction: metrics.count(.coastEndedFriction)
        case .edge: metrics.count(.coastEndedEdge)
        case .interrupted: metrics.count(.coastInterrupted)
        }
        metrics.record(.coastDurationMs, ms: coastElapsedSeconds * 1000)
        metrics.record(.coastDistanceMs, ms: abs(currentTimeMs - coastStartTimeMs))
    }

    private func playbackTick(_ dt: Double) {
        guard mode == .playing else { return }

        if hasVideoAtCurrentTime {
            guard let source = sourceCovering(timeMs: currentTimeMs) ?? nativeMasterSource() else {
                let next = currentTimeMs + dt * 1000
                if next >= maxDurationMs {
                    setTime(0)
                    pause()
                } else {
                    setTimeFromNativeClock(next)
                    audioMixEngine.advance(toMs: next)
                }
                return
            }

            if nativeMasterLayerId != source.layerId {
                switchNativeMaster(to: source, atMs: currentTimeMs)
                return
            }

            guard let sourceSeconds = stageSessions[source.layerId]?.currentSourceSeconds else { return }
            let next = source.mapping.timelineMs(atSourceMs: sourceSeconds * 1000)
            let sourceEnd = source.mapping.layerStartMs + source.mapping.durationMs
            if next >= sourceEnd {
                if let nextSource = sourceCovering(timeMs: sourceEnd + 0.001) {
                    setTimeFromNativeClock(sourceEnd)
                    switchNativeMaster(to: nextSource, atMs: sourceEnd)
                    audioMixEngine.advance(toMs: sourceEnd)
                    return
                }
                setTime(0)
                pause()
            } else {
                setTimeFromNativeClock(next)
                audioMixEngine.advance(toMs: next)
            }
            return
        }

        let next = currentTimeMs + dt * 1000
        if next >= maxDurationMs {
            setTime(0)
            pause()
            return
        }
        setTime(next)
        audioMixEngine.advance(toMs: next)
    }

    // MARK: Time + frames

    /// The only place `currentTimeMs` is written.
    private func setTime(_ ms: Double) {
        PlaybackMetrics.shared.count(.setTimeCalls)
        currentTimeMs = clamped(ms)
        updatePlayheadSpeed()
        if hasVideoAtCurrentTime, mode == .scrubbing || mode == .coasting {
            let tolerance = scrubTolerance.seconds(forSpeedMsPerSecond: playheadSpeedMsPerSecond)
            PlaybackMetrics.shared.gauge(.scrubToleranceMs, tolerance * 1000)
            seekStageSessions(atMs: currentTimeMs, toleranceSeconds: tolerance)
        }
    }

    /// Playhead speed in content ms/s, re-estimated over windows of at least
    /// 40 ms so bursts of touch events (which arrive microseconds apart)
    /// can't produce absurd instantaneous speeds. Reads as 0 once the playhead
    /// has been still for 100 ms.
    private var playheadSpeedMsPerSecond: Double {
        CACurrentMediaTime() - speedUpdatedAt > 0.1 ? 0 : speedEstimate
    }

    private func updatePlayheadSpeed() {
        let now = CACurrentMediaTime()
        let elapsed = now - speedWindowStartAt
        guard elapsed >= 0.04 else { return }
        if elapsed < 0.25 {
            speedEstimate = abs(currentTimeMs - speedWindowStartMs) / elapsed
            speedUpdatedAt = now
        }
        speedWindowStartAt = now
        speedWindowStartMs = currentTimeMs
    }
    @ObservationIgnored private var speedEstimate = 0.0
    @ObservationIgnored private var speedUpdatedAt: CFTimeInterval = 0
    @ObservationIgnored private var speedWindowStartAt: CFTimeInterval = 0
    @ObservationIgnored private var speedWindowStartMs = 0.0

    private func setTimeFromNativeClock(_ ms: Double) {
        currentTimeMs = clamped(ms)
    }

    private func clamped(_ ms: Double) -> Double {
        min(max(ms, 0), maxDurationMs)
    }

    // MARK: Metrics

    private func metricsProbe() -> PlaybackMetrics.Probe {
        let now = CACurrentMediaTime()
        var probe = PlaybackMetrics.Probe()
        switch mode {
        case .idle: probe.mode = "idle"
        case .scrubbing: probe.mode = "scrubbing"
        case .coasting: probe.mode = "coasting"
        case .playing: probe.mode = "playing"
        }
        var worstAge: Double?
        for session in stageSessions.values {
            let coordinator = session.seekCoordinator
            if coordinator.hasUnserved { probe.hasUnserved = true }
            if let age = coordinator.displayAgeMs(now: now) {
                worstAge = max(worstAge ?? 0, age)
            }
        }
        probe.displayAgeMs = worstAge
        if mode == .scrubbing || mode == .coasting {
            var worstError: Double?
            for source in videoSources {
                guard currentTimeMs >= source.mapping.layerStartMs,
                      currentTimeMs < source.mapping.layerStartMs + source.mapping.durationMs,
                      let landed = stageSessions[source.layerId]?.seekCoordinator.lastLandedSeconds
                else { continue }
                let shown = source.mapping.timelineMs(atSourceMs: landed * 1000)
                worstError = max(worstError ?? 0, abs(currentTimeMs - shown))
            }
            probe.displayErrorMs = worstError
            probe.playheadSpeedMsPerSecond = playheadSpeedMsPerSecond
        }
        probe.playerSessions = stageSessions.count
        probe.sourcesTotal = videoSources.count
        return probe
    }

    // MARK: Native player path

    private var hasVideoAtCurrentTime: Bool {
        videoSources.contains {
            currentTimeMs >= $0.mapping.layerStartMs
                && currentTimeMs < $0.mapping.layerStartMs + $0.mapping.durationMs
        }
    }

    func player(for layerId: String) -> AVPlayer? {
        _ = mediaGeneration
        return stageSessions[layerId]?.player
    }

    private func reconcileStageSessions() {
        let wanted = Dictionary(uniqueKeysWithValues: videoSources.map { ($0.layerId, $0) })
        for (layerId, session) in stageSessions {
            if let source = videoSources.first(where: { $0.layerId == layerId }),
               wanted[layerId] != nil,
               source.url == session.url {
                continue
            } else {
                session.pause()
                session.cancelPendingSeeks()
            }
        }

        var next: [String: StagePlayerSession] = [:]
        for source in videoSources {
            if let existing = stageSessions[source.layerId],
               existing.assetId == source.assetId,
               existing.url == source.url {
                next[source.layerId] = existing
            } else {
                next[source.layerId] = StagePlayerSession(
                    layerId: source.layerId,
                    assetId: source.assetId,
                    url: source.url
                )
            }
        }
        stageSessions = next
        if nativeMasterLayerId != nil, stageSessions[nativeMasterLayerId!] == nil {
            nativeMasterLayerId = nil
        }
    }

    private func sourceCovering(timeMs: Double) -> VideoSource? {
        videoSources.first {
            timeMs >= $0.mapping.layerStartMs
                && timeMs < $0.mapping.layerStartMs + $0.mapping.durationMs
        }
    }

    private func nativeMasterSource() -> VideoSource? {
        if let covering = sourceCovering(timeMs: currentTimeMs) {
            return covering
        }
        if let nativeMasterLayerId,
           let source = videoSources.first(where: { $0.layerId == nativeMasterLayerId }) {
            return source
        }
        return sourceCovering(timeMs: currentTimeMs)
    }

    private func switchNativeMaster(to source: VideoSource, atMs ms: Double) {
        nativeMasterLayerId = source.layerId
        stageSessions[source.layerId]?.seek(
            toSourceSeconds: source.mapping.sourceMs(atTimelineMs: ms) / 1000,
            toleranceSeconds: 0
        ) { [weak self] finished in
            guard let self,
                  finished,
                  self.mode == .playing,
                  self.nativeMasterLayerId == source.layerId
            else { return }
            self.stageSessions[source.layerId]?.play(rate: Float(source.mapping.rate))
        }
    }

    private func seekStageSessions(
        atMs ms: Double,
        toleranceSeconds: Double,
        completion: ((Bool) -> Void)? = nil
    ) {
        let targets = videoSources.filter {
            ms >= $0.mapping.layerStartMs
                && ms < $0.mapping.layerStartMs + $0.mapping.durationMs
        }

        guard !targets.isEmpty else {
            completion?(true)
            return
        }

        var remaining = targets.count
        var allFinished = true
        for source in targets {
            stageSessions[source.layerId]?.seek(
                toSourceSeconds: source.mapping.sourceMs(atTimelineMs: ms) / 1000,
                toleranceSeconds: toleranceSeconds
            ) { finished in
                remaining -= 1
                allFinished = allFinished && finished
                if remaining == 0 {
                    completion?(allFinished)
                }
            }
        }
    }

    private func playNativeSessions(atMs ms: Double) {
        for source in videoSources where
            ms >= source.mapping.layerStartMs
                && ms < source.mapping.layerStartMs + source.mapping.durationMs {
            stageSessions[source.layerId]?.play(rate: Float(source.mapping.rate))
        }
    }

    private func pauseNativeSessions() {
        for session in stageSessions.values {
            session.pause()
            session.cancelPendingSeeks()
        }
    }

    private func settleNativeAtCurrentTime() {
        guard hasVideoAtCurrentTime else { return }
        seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0)
    }
}
