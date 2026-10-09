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
/// filtered layers pull CVPixelBuffers into the Metal preview. The old
/// AVAssetReader/CGImage path remains only as a compatibility fallback for
/// previews without an engine. During playback, the player itself is the
/// decode clock rather than a SwiftUI/CGImage frame loop.
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
        let originalURL: URL
        var url: URL
        let mapping: VideoTimeMapping
        let usesNativePlayer: Bool
    }

    @ObservationIgnored private var videoSources: [VideoSource] = []
    private(set) var mediaGeneration = 0
    @ObservationIgnored private var stageSessions: [String: StagePlayerSession] = [:]
    @ObservationIgnored private var nativeMasterLayerId: String?
    @ObservationIgnored private var nativeStartGeneration = 0
    /// True while `prepare()` is awaiting a proxy encode — reported to
    /// `PlaybackMetrics` because the encoder competes with scrub for CPU.
    @ObservationIgnored private var isEncodingProxy = false
    @ObservationIgnored private var scrubStartTimeMs: Double = 0
    @ObservationIgnored private var coastVelocityMsPerSecond: Double = 0
    @ObservationIgnored private var stalledSeconds: Double = 0
    @ObservationIgnored private let clock = DisplayLinkClock()
    /// Real sound — see `AudioMixEngine`'s own doc comment for the sync
    /// model. Only ever told to play from `playbackTick`/`play()`, never
    /// from scrubbing/coasting.
    @ObservationIgnored private let audioMixEngine = AudioMixEngine()
    /// Test seam: decides whether every video frame needed at a timeline time
    /// is available. Native AVPlayer-backed layers are always considered ready;
    /// the callback is used only by the compatibility frame-server path.
    @ObservationIgnored private let frameReadiness: ((Double) -> Bool)?

    /// A flick slower than this just stops; faster starts a coast.
    private static let minimumCoastMsPerSecond = 40.0
    /// Fraction of velocity *remaining* after one second of coasting — 0.04
    /// coasts a fast flick for roughly half a second before settling.
    private static let coastFrictionPerSecond = 0.04
    private static let coastStopMsPerSecond = 15.0
    /// How close a decoded frame must be to count as "the frame for now".
    private static let frameToleranceSeconds = 0.05
    /// Upper bound on holding the clock for frames, so a file that never
    /// decodes can't freeze playback forever.
    private static let maxStallSeconds = 2.0
    /// Clips starting within this window ahead of the playhead are already
    /// prefetched, so crossing a cut doesn't wait for a reader to spin up.
    private static let upcomingClipLookaheadMs = 1000.0

    init(project: V2Project, frameReadiness: ((Double) -> Bool)? = nil) {
        self.frameReadiness = frameReadiness
        PlaybackMetrics.shared.track(.engine, 1)
        update(project: project)
    }

    deinit {
        PlaybackMetrics.shared.track(.engine, -1)
    }

    /// Call whenever the project changes (edit, undo/redo, live trim drag).
    func update(project: V2Project) {
        videoSources = project.layers.compactMap { layer in
            guard case .video(let payload) = layer.payload,
                  let mapping = VideoTimeMapping(layer: layer),
                  let asset = project.assets.first(where: { $0.id == payload.assetId }),
                  case .video(let videoAsset) = asset,
                  let url = bundledURL(filename: videoAsset.uri)
            else { return nil }
            let previewURL = VideoProxyService.proxyURLIfPresent(assetId: payload.assetId, sourceURL: url) ?? url
            return VideoSource(
                layerId: layer.id,
                assetId: payload.assetId,
                originalURL: url,
                url: previewURL,
                mapping: mapping,
                usesNativePlayer: true
            )
        }
        reconcileStageSessions()
        mediaGeneration &+= 1
        let layerEnds = project.layers.map { $0.timing.start + $0.timing.duration }
        let audioEnds = project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }
        maxDurationMs = max((layerEnds + audioEnds).max() ?? 1, 1)
        prefetchFrames()
        audioMixEngine.update(project: project)
    }

    /// Starts decoding around the current time — call once when the editor
    /// appears so the first frame is ready before anything moves.
    func prepare() async {
        // Registered here, not in `init`: `EditorShellView.init` builds a
        // throwaway engine every time the view struct is re-created, and
        // only the one SwiftUI keeps ever gets `prepare()` called.
        PlaybackMetrics.shared.probe = { [weak self] in self?.metricsProbe() ?? PlaybackMetrics.Probe() }
        // Keep a stable snapshot while proxy encoding suspends this actor. A
        // project edit can arrive during that await; writing by an old array
        // index would then attach the proxy to the wrong clip or trap.
        let sources = videoSources
        for source in sources {
            let existingProxy = VideoProxyService.proxyURLIfPresent(
                assetId: source.assetId,
                sourceURL: source.originalURL
            )
            let proxy: URL?
            if let existingProxy {
                proxy = existingProxy
            } else {
                isEncodingProxy = true
                proxy = await VideoProxyService.makeProxy(
                    assetId: source.assetId,
                    sourceURL: source.originalURL
                )
                isEncodingProxy = false
            }
            guard let proxy,
                  let index = videoSources.firstIndex(where: {
                      $0.layerId == source.layerId && $0.originalURL == source.originalURL
                  })
            else { continue }
            videoSources[index].url = proxy
        }
        reconcileStageSessions()
        mediaGeneration &+= 1
        seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0) { [weak self] finished in
            guard let self, finished, self.mode == .playing else { return }
            // Proxy generation may finish after the user has pressed Play.
            // Re-arm the replacement session without starting playback from
            // a background prepare when the editor is still idle.
            self.playNativeSessions(atMs: self.currentTimeMs)
        }
    }

    // MARK: Transport

    func play() {
        guard mode != .playing else { return }
        clock.stop()
        mode = .playing
        stalledSeconds = 0

        if usesNativePlayerAtCurrentTime {
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
        coastVelocityMsPerSecond = velocityMsPerSecond
        clock.start { [weak self] dt in self?.coastTick(dt) }
    }

    // MARK: Ticks

    private func coastTick(_ dt: Double) {
        guard mode == .coasting else { return }
        coastVelocityMsPerSecond *= pow(Self.coastFrictionPerSecond, dt)
        let next = currentTimeMs + coastVelocityMsPerSecond * dt
        let bounded = clamped(next)
        setTime(bounded)
        if bounded != next || abs(coastVelocityMsPerSecond) < Self.coastStopMsPerSecond {
            clock.stop()
            mode = .idle
            settleNativeAtCurrentTime()
        }
    }

    private func playbackTick(_ dt: Double) {
        guard mode == .playing else { return }

        if usesNativePlayerAtCurrentTime {
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
        if !framesReady(atMs: next), stalledSeconds < Self.maxStallSeconds {
            stalledSeconds += dt
            // Holds audio too, so it never runs ahead of a frozen Stage —
            // the next successful tick's `advance(toMs:)` resumes it fresh.
            audioMixEngine.pause()
            return
        }
        stalledSeconds = 0
        setTime(next)
        audioMixEngine.advance(toMs: next)
    }

    // MARK: Time + frames

    /// The only place `currentTimeMs` is written.
    private func setTime(_ ms: Double) {
        PlaybackMetrics.shared.count(.setTimeCalls)
        currentTimeMs = clamped(ms)
        if usesNativePlayerAtCurrentTime {
            if mode == .scrubbing || mode == .coasting {
                seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0.2)
            }
        } else {
            prefetchFrames()
        }
    }

    private func setTimeFromNativeClock(_ ms: Double) {
        currentTimeMs = clamped(ms)
    }

    private func clamped(_ ms: Double) -> Double {
        min(max(ms, 0), maxDurationMs)
    }

    /// Every video clip covering the playhead (or starting just ahead of it)
    /// gets its frames positioned around its own source time.
    private func prefetchFrames() {
        let covering = videoSources.first {
            currentTimeMs >= $0.mapping.layerStartMs && currentTimeMs < $0.mapping.layerStartMs + $0.mapping.durationMs
        }
        for source in videoSources {
            guard !source.usesNativePlayer else { continue }
            let start = source.mapping.layerStartMs
            let end = start + source.mapping.durationMs
            guard currentTimeMs >= start - Self.upcomingClipLookaheadMs, currentTimeMs < end else { continue }
            // An upcoming clip that's really just the covering clip's own
            // continuation (e.g. a split's second half) shares one
            // continuous source stream with it — the covering clip's own
            // forward decode is already heading toward this clip's starting
            // point. Prefetching it separately would send `VideoFrameServer`
            // two different target times for the same asset's one reader on
            // every tick of this lookahead window, fighting over it right
            // until the cut arrives.
            if let covering, covering.layerId != source.layerId, covering.assetId == source.assetId,
               source.mapping.isContinuous(with: covering.mapping) {
                continue
            }
            let sourceSeconds = source.mapping.sourceMs(atTimelineMs: currentTimeMs) / 1000
            VideoFrameServer.shared.prefetch(assetId: source.assetId, url: source.url, atSeconds: sourceSeconds)
        }
    }

    private func framesReady(atMs ms: Double) -> Bool {
        if usesNativePlayerAtTime(ms) { return true }
        if let frameReadiness { return frameReadiness(ms) }
        for source in videoSources {
            let start = source.mapping.layerStartMs
            guard ms >= start, ms < start + source.mapping.durationMs else { continue }
            let sourceSeconds = source.mapping.sourceMs(atTimelineMs: ms) / 1000
            if !VideoFrameServer.shared.hasFrame(assetId: source.assetId, near: sourceSeconds, tolerance: Self.frameToleranceSeconds) {
                return false
            }
        }
        return true
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
        probe.playerSessions = stageSessions.count
        probe.sourcesTotal = videoSources.count
        probe.sourcesOnProxy = videoSources.filter { $0.url != $0.originalURL }.count
        probe.proxyEncoding = isEncodingProxy
        return probe
    }

    // MARK: Native player path

    private var usesNativePlayerAtCurrentTime: Bool {
        usesNativePlayerAtTime(currentTimeMs)
    }

    private func usesNativePlayerAtTime(_ ms: Double) -> Bool {
        videoSources.contains {
            $0.usesNativePlayer
                && ms >= $0.mapping.layerStartMs
                && ms < $0.mapping.layerStartMs + $0.mapping.durationMs
        }
    }

    func player(for layerId: String) -> AVPlayer? {
        _ = mediaGeneration
        return stageSessions[layerId]?.player
    }

    /// URL currently used by the preview. It is the short-GOP proxy after
    /// `prepare()` completes, and the original asset while the proxy is being
    /// generated.
    func previewURL(for layerId: String) -> URL? {
        _ = mediaGeneration
        return videoSources.first(where: { $0.layerId == layerId })?.url
    }

    private func reconcileStageSessions() {
        let wanted = Dictionary(uniqueKeysWithValues: videoSources.filter(\.usesNativePlayer).map { ($0.layerId, $0) })
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
        for source in videoSources where source.usesNativePlayer {
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
            $0.usesNativePlayer
                &&
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
        guard usesNativePlayerAtCurrentTime else { return }
        seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0)
    }
}
