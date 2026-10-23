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
    /// The editor and renderer use the same timeline coordinate.
    private(set) var currentTimeMs: Double = 0
    private(set) var mode: Mode = .idle
    private(set) var maxDurationMs: Double = 1
    private(set) var previewLayers: [V2Layer] = []
    private(set) var transitionFramePlan: TransitionFramePlan

    var editorTimeMs: Double { min(currentTimeMs, maxDurationMs) }

    var isPlaying: Bool { mode == .playing }

    // MARK: Internals

    private struct VideoSource {
        let layerId: String
        let assetId: String
        let url: URL
        let mapping: VideoTimeMapping
        let durationMs: Double
    }

    @ObservationIgnored private var videoSources: [VideoSource] = []
    @ObservationIgnored private var sourceLayers: [String: V2Layer] = [:]
    @ObservationIgnored private var heldNativeLayerIds = Set<String>()
    @ObservationIgnored private var renderDurationMs: Double = 1
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
    /// Timeline offset established when a pre-playing transition source
    /// becomes the master. AVPlayer can report a frame behind the display
    /// clock at that instant; rebasing prevents the playhead from rewinding.
    @ObservationIgnored private var nativeMasterClockOffsetMs: Double = 0
    @ObservationIgnored private var transitionHandoffPendingId: String?
    @ObservationIgnored private var activeNativeLayerIds = Set<String>()
    @ObservationIgnored private var lastTransitionLogPoint: String?
    @ObservationIgnored private var nativeStartGeneration = 0
    @ObservationIgnored private var prewarmGeneration = 0
    @ObservationIgnored private var prewarmingLayerId: String?
    @ObservationIgnored private var prewarmedLayerId: String?
    @ObservationIgnored private var scheduledLayerId: String?
    @ObservationIgnored private var scrubStartTimeMs: Double = 0
    /// State of the coast in flight (see `MomentumDecay`): position is
    /// computed from these and the elapsed time, never integrated per frame.
    @ObservationIgnored private var coastInitialVelocity: Double = 0
    @ObservationIgnored private var coastStartTimeMs: Double = 0
    @ObservationIgnored private var coastElapsedSeconds: Double = 0
    /// A touch landed on the coast: same speed, much heavier friction (`brake()`).
    @ObservationIgnored private var isBraking = false
    @ObservationIgnored private let clock = DisplayLinkClock()
    @ObservationIgnored private let glideClock = DisplayLinkClock()
    @ObservationIgnored private var glideCompletion: (() -> Void)?
    /// Lowest time the playhead may take. 0, except while a main-lane trim is dragged: the lane may then go before t0
    /// (main-lane magnet) and the playhead follows it; the drag's end puts it back to 0 (`glide(toMs:)`).
    @ObservationIgnored private(set) var timeFloorMs = 0.0
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

    convenience init(project: V2Project) {
        self.init(project: project, transitions: nil)
    }

    init(project: V2Project, transitions: [EditorTransitionIntent]?) {
        let renderProject = transitions.map { TransitionWrappers.compiling($0, into: project) } ?? project
        transitionFramePlan = TransitionFramePlan(project: renderProject)
        PlaybackMetrics.shared.track(.engine, 1)
        update(project: project, transitions: transitions)
    }

    deinit {
        PlaybackMetrics.shared.track(.engine, -1)
    }

    /// Call whenever the project changes (edit, undo/redo, live trim drag).
    func update(project: V2Project) {
        update(project: project, transitions: nil)
    }

    func update(project: V2Project, transitions: [EditorTransitionIntent]?) {
        invalidatePrewarm()
        let renderProject = transitions.map { TransitionWrappers.compiling($0, into: project) }
            ?? TransitionRenderPlan.compile(project)
        transitionFramePlan = TransitionFramePlan(project: renderProject)
        TransitionDiagnostics.logProject(project, stage: "engine.source-v2")
        TransitionDiagnostics.logCompiledPlan(source: project, render: renderProject, plan: transitionFramePlan)
        latestProject = renderProject
        previewLayers = renderProject.layers
        sourceLayers = Dictionary(uniqueKeysWithValues: project.layers.filter { $0.type == "video" }.map { ($0.id, $0) })
        videoSources = project.layers.compactMap { layer in
            guard case .video(let payload) = layer.payload,
                  let mapping = VideoTimeMapping(layer: layer),
                  let asset = renderProject.assets.first(where: { $0.id == payload.assetId }),
                  case .video(let videoAsset) = asset,
                  let url = bundledURL(filename: videoAsset.uri)
            else { return nil }
            return VideoSource(
                layerId: layer.id,
                assetId: payload.assetId,
                url: url,
                mapping: mapping,
                durationMs: videoAsset.duration
            )
        }
        if isPrepared { reconcileStageSessions() }
        mediaGeneration &+= 1
        let layerEnds = project.layers.map { $0.timing.start + $0.timing.duration }
        let audioEnds = project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }
        maxDurationMs = max((layerEnds + audioEnds).max() ?? 1, 1)
        renderDurationMs = maxDurationMs
        if isPrepared { audioMixEngine.update(project: renderProject) }
        if isPrepared, mode == .playing,
           let source = sourceCovering(timeMs: currentTimeMs) {
            prewarmNextSource(after: source, atMs: currentTimeMs)
        }
    }

    /// Creates the players and the audio mix and positions them at the current
    /// time — call once when the editor appears, so the first frame is ready
    /// before anything moves.
    func prepare() {
        invalidatePrewarm()
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

    /// Shows the frame under the playhead again: a clip that just got new footage (Replace, Overlay) has a player that was never positioned.
    func refreshFrames() {
        guard mode == .idle else { return }
        seekStageSessions(atMs: currentTimeMs, toleranceSeconds: 0)
    }

    // MARK: Transport

    func play() {
        guard mode != .playing else { return }
        lastTransitionLogPoint = nil
        nativeMasterClockOffsetMs = 0
        transitionHandoffPendingId = nil
        TransitionDiagnostics.log("play.start project=\(latestProject?.id ?? "unknown") t=\(String(format: "%.1f", currentTimeMs)) cuts=\(transitionFramePlan.windows.count)")
        clock.stop()
        mode = .playing

        if hasVideoAtCurrentTime {
            nativeStartGeneration &+= 1
            let generation = nativeStartGeneration
            nativeMasterLayerId = sourceCovering(timeMs: currentTimeMs)?.layerId
            if let source = sourceCovering(timeMs: currentTimeMs) {
                prewarmNextSource(after: source, atMs: currentTimeMs)
            }
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
        transitionHandoffPendingId = nil
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
        cancelGlide()
        guard mode != .scrubbing else { return }
        if mode == .coasting { recordCoastEnd(.interrupted) }
        clock.stop()
        nativeStartGeneration &+= 1
        pauseNativeSessions()
        mode = .scrubbing
        scrubStartTimeMs = editorTimeMs
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
        isBraking = false
        coastInitialVelocity = velocityMsPerSecond * coastTuning.velocityGain
        coastStartTimeMs = currentTimeMs
        coastElapsedSeconds = 0
        PlaybackMetrics.shared.record(.coastReleaseSpeed, ms: abs(velocityMsPerSecond))
        PlaybackMetrics.shared.gauge(.coastGain, coastTuning.velocityGain)
        PlaybackMetrics.shared.gauge(.coastFriction, coastTuning.frictionScale)
        clock.start { [weak self] dt in self?.coastTick(dt) }
    }

    /// A finger touching down on a coast brakes it: the live speed is kept and the
    /// friction is multiplied (`CoastTuning.brakeFrictionScale`), so the glide stops
    /// in a fraction of a second. Call on touch-down, before any drag distance;
    /// idempotent, and a no-op unless a coast is in flight. A drag that follows
    /// takes over from the live position through `beginScrub()`.
    func brake() {
        guard mode == .coasting, !isBraking else { return }
        coastInitialVelocity = coastTuning.decay.velocity(initial: coastInitialVelocity, after: coastElapsedSeconds)
        coastStartTimeMs = currentTimeMs
        coastElapsedSeconds = 0
        isBraking = true
    }

    // MARK: Ticks

    private func coastTick(_ dt: Double) {
        guard mode == .coasting else { return }
        PlaybackMetrics.shared.record(.coastTickMs, ms: dt * 1000)
        coastElapsedSeconds += dt
        let decay = isBraking ? coastTuning.brakeDecay : coastTuning.decay
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

        // Follow the visible moving source's media clock. Advancing the render
        // clock by display-link deltas can get ~100 ms ahead while AVPlayer is
        // starting, so the transition cuts before the outgoing frames arrive.
        if let window = transitionFramePlan.activeWindow(at: currentTimeMs) {
            transitionHandoffPendingId = window.incomingId
            let clockLayerId = currentTimeMs < window.cutMs ? window.outgoingId : window.incomingId
            let next: Double
            if let source = videoSources.first(where: { $0.layerId == clockLayerId }),
               let seconds = stageSessions[clockLayerId]?.currentSourceSeconds {
                next = max(currentTimeMs,
                           source.mapping.timelineMs(atSourceMs: seconds * 1000) + nativeMasterClockOffsetMs)
            } else {
                next = currentTimeMs + dt * 1000
            }
            if currentTimeMs < window.cutMs,
               let outgoing = videoSources.first(where: { $0.layerId == window.outgoingId }) {
                schedulePrewarmedNext(after: outgoing, atMs: next)
            }
            if next >= renderDurationMs {
                setTime(0)
                pause()
            } else {
                setTimeFromNativeClock(next)
                syncNativeSessions(atMs: next)
                audioMixEngine.advance(toMs: next)
                logTransitionPlayback(atMs: next)
            }
            return
        }

        if hasVideoAtCurrentTime {
            guard let source = sourceCovering(timeMs: currentTimeMs) ?? nativeMasterSource() else {
                let next = currentTimeMs + dt * 1000
                if next >= renderDurationMs {
                    setTime(0)
                    pause()
                } else {
                    setTimeFromNativeClock(next)
                    syncNativeSessions(atMs: next)
                    audioMixEngine.advance(toMs: next)
                }
                return
            }

            if nativeMasterLayerId != source.layerId || transitionHandoffPendingId == source.layerId {
                transitionHandoffPendingId = nil
                switchNativeMaster(to: source, atMs: currentTimeMs)
                return
            }

            guard let sourceSeconds = stageSessions[source.layerId]?.currentSourceSeconds else { return }
            let next = max(source.mapping.timelineMs(atSourceMs: sourceSeconds * 1000)
                           + nativeMasterClockOffsetMs, currentTimeMs)
            prewarmNextSource(after: source, atMs: next)
            schedulePrewarmedNext(after: source, atMs: next)
            followSpeedCurves(atMs: next)
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
                syncNativeSessions(atMs: next)
                audioMixEngine.advance(toMs: next)
            }
            return
        }

        let next = currentTimeMs + dt * 1000
        if next >= renderDurationMs {
            setTime(0)
            pause()
            return
        }
        setTime(next)
        audioMixEngine.advance(toMs: next)
    }

    private func logTransitionPlayback(atMs timeMs: Double) {
        guard let window = transitionFramePlan.activeWindow(at: timeMs), let latestProject else { return }
        let progress = window.progress(at: timeMs)
        PlaybackMetrics.shared.count(.transitionActiveTicks)
        PlaybackMetrics.shared.gauge(.transitionProgress, progress)

        // A handful of representative samples keeps the Console useful and
        // lets us compare player readiness against the V2 sampler's values.
        let bucket = min(Int(progress * 4), 3)
        let checkpoint = "\(window.incomingId):\(bucket)"
        guard checkpoint != lastTransitionLogPoint else { return }
        lastTransitionLogPoint = checkpoint
        let playerState = [window.outgoingId, window.incomingId].map { id -> String in
            guard let session = stageSessions[id] else { return "\(id):missing" }
            let status = session.player.currentItem.map { String($0.status.rawValue) } ?? "noItem"
            let sourceSeconds = session.currentSourceSeconds.map { String(format: "%.3f", $0) } ?? "nan"
            return "\(id):status=\(status),src=\(sourceSeconds),rate=\(String(format: "%.2f", session.player.rate))"
        }.joined(separator: ";")
        TransitionDiagnostics.logPlayback(plan: transitionFramePlan, project: latestProject,
                                          timeMs: timeMs, playerState: playerState)
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
        if mode == .playing, ms < currentTimeMs - 50 {
            PlaybackMetrics.shared.count(.playbackRegressions)
            TransitionDiagnostics.log("play.regress from=\(String(format: "%.1f", currentTimeMs)) to=\(String(format: "%.1f", ms)) master=\(nativeMasterLayerId ?? "none")")
        }
        currentTimeMs = clamped(ms)
    }

    private func clamped(_ ms: Double) -> Double {
        min(max(ms, timeFloorMs), renderDurationMs)
    }

    func setTimeFloor(_ ms: Double) {
        timeFloorMs = min(ms, 0)
    }

    /// Slides the playhead to `target` (ease-out, `duration` seconds) as a scrub, then calls `completion`. A touch that
    /// starts a scrub cancels it (the completion still runs, so a lowered time floor is always restored).
    func glide(toMs target: Double, duration: Double = 0.2, completion: (() -> Void)? = nil) {
        cancelGlide()
        let from = currentTimeMs
        let goal = clamped(target)
        guard abs(goal - from) > 0.5 else { completion?(); return }
        beginScrub()
        glideCompletion = completion
        var elapsed = 0.0
        glideClock.start { [weak self] dt in
            guard let self else { return }
            elapsed += dt
            let progress = min(elapsed / duration, 1)
            let eased = 1 - pow(1 - progress, 3)
            self.scrub(toMs: from + (goal - from) * eased)
            if progress >= 1 {
                self.glideClock.stop()
                let done = self.glideCompletion
                self.glideCompletion = nil
                self.endScrub(velocityMsPerSecond: 0)
                done?()
            }
        }
    }

    private func cancelGlide() {
        guard glideClock.isRunning else { return }
        glideClock.stop()
        let done = glideCompletion
        glideCompletion = nil
        done?()
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
        let wasAlreadyPlaying = activeNativeLayerIds.contains(source.layerId)
        let previousSource = nativeMasterLayerId.flatMap { id in videoSources.first { $0.layerId == id } }
        let isSplitContinuation = previousSource.map {
            $0.assetId == source.assetId && $0.url == source.url && $0.mapping.isContinuous(with: source.mapping)
        } ?? false
        let actualMs = stageSessions[source.layerId]?.currentSourceSeconds.map { source.mapping.timelineMs(atSourceMs: $0 * 1000) } ?? .nan
        let wasPrewarmed = prewarmedLayerId == source.layerId
            && stageSessions[source.layerId]?.seekCoordinator.hasUnserved == false
            && actualMs.isFinite && abs(actualMs - ms) < 50
        TransitionDiagnostics.log("master.switch id=\(source.layerId) t=\(String(format: "%.1f", ms)) sourceTimeline=\(String(format: "%.1f", actualMs)) drift=\(String(format: "%.1f", actualMs - ms)) active=\(wasAlreadyPlaying)")
        SplitPlaybackDiagnostics.log("master.switch from=\(previousSource?.layerId ?? "none") to=\(source.layerId) splitContinuation=\(isSplitContinuation) t=\(String(format: "%.1f", ms)) incomingSource=\(String(format: "%.3f", stageSessions[source.layerId]?.currentSourceSeconds ?? .nan)) incomingRate=\(String(format: "%.2f", stageSessions[source.layerId]?.player.rate ?? 0)) incomingStatus=\(stageSessions[source.layerId]?.player.currentItem?.status.rawValue ?? -1) incomingActive=\(wasAlreadyPlaying) prewarmed=\(wasPrewarmed)")
        nativeMasterLayerId = source.layerId
        activeNativeLayerIds.insert(source.layerId)
        nativeMasterClockOffsetMs = (wasAlreadyPlaying || wasPrewarmed) && actualMs.isFinite ? ms - actualMs : 0
        // The incoming player has already been running underneath the
        // transition overlay. Seeking it again at the seam stalls its decoder
        // for a frame (or longer); promote its existing clock instead.
        if (wasAlreadyPlaying || wasPrewarmed), let session = stageSessions[source.layerId] {
            prewarmedLayerId = nil
            if scheduledLayerId == source.layerId { scheduledLayerId = nil }
            session.play(rate: Float(source.mapping.rate(atTimelineMs: ms)))
            prewarmNextSource(after: source, atMs: ms)
            return
        }
        stageSessions[source.layerId]?.seek(
            toSourceSeconds: source.mapping.sourceMs(atTimelineMs: ms) / 1000,
            toleranceSeconds: 0
        ) { [weak self] finished in
            guard let self,
                  finished,
                  self.mode == .playing,
                  self.nativeMasterLayerId == source.layerId
            else { return }
            self.stageSessions[source.layerId]?.play(rate: Float(source.mapping.rate(atTimelineMs: ms)))
            self.prewarmNextSource(after: source, atMs: self.currentTimeMs)
        }
    }

    /// Keep the next adjacent clip paused at its first exact frame. This moves
    /// decoder setup off the cut; transition pairs use their overlap path.
    private func prewarmNextSource(after source: VideoSource, atMs ms: Double) {
        let cutMs = source.mapping.layerStartMs + source.mapping.durationMs
        let leadMs = max(3_000, source.mapping.rate(atTimelineMs: ms) * 500)
        guard cutMs > ms, cutMs - ms <= leadMs else { return }
        guard let next = videoSources.first(where: {
            $0.layerId != source.layerId && abs($0.mapping.layerStartMs - cutMs) < 1
                && sourceLayers[$0.layerId]?.order == sourceLayers[source.layerId]?.order
        }),
        !transitionFramePlan.windows.contains(where: {
            $0.outgoingId == source.layerId && $0.incomingId == next.layerId
        }),
        prewarmedLayerId != next.layerId,
        prewarmingLayerId != next.layerId,
        let session = stageSessions[next.layerId]
        else { return }

        prewarmingLayerId = next.layerId
        let generation = prewarmGeneration
        let target = sourceSeconds(for: next, timelineTimeMs: cutMs)
        SplitPlaybackDiagnostics.log("prewarm.start layer=\(next.layerId) cutMs=\(String(format: "%.1f", cutMs)) target=\(String(format: "%.3f", target))")
        session.seek(toSourceSeconds: target, toleranceSeconds: 0) { [weak self] finished in
            guard let self, self.prewarmGeneration == generation,
                  self.prewarmingLayerId == next.layerId else { return }
            guard finished else {
                self.prewarmingLayerId = nil
                return
            }
            session.preroll(atRate: Float(next.mapping.rate(atTimelineMs: cutMs))) { [weak self] primed in
                guard let self, self.prewarmGeneration == generation,
                      self.prewarmingLayerId == next.layerId else { return }
                self.prewarmingLayerId = nil
                if primed { self.prewarmedLayerId = next.layerId }
                SplitPlaybackDiagnostics.log("prewarm.ready layer=\(next.layerId) primed=\(primed)")
            }
        }
    }

    /// Schedule the prepared player on the same host clock shortly before the
    /// cut, so AVPlayerLayer has already begun presenting when it becomes visible.
    private func schedulePrewarmedNext(after source: VideoSource, atMs ms: Double) {
        let cutMs = source.mapping.layerStartMs + source.mapping.durationMs
        guard let nextId = prewarmedLayerId,
              nextId != scheduledLayerId,
              let next = videoSources.first(where: { $0.layerId == nextId }),
              abs(next.mapping.layerStartMs - cutMs) < 1,
              source.mapping.curve == nil, next.mapping.curve == nil,
              let session = stageSessions[nextId],
              let outgoingTimebase = stageSessions[source.layerId]?.player.currentItem?.timebase,
              session.player.rate == 0,
              cutMs - ms > 25, cutMs - ms <= 250
        else { return }
        let cutSourceSeconds = source.mapping.sourceMs(atTimelineMs: cutMs) / 1000
        let hostTime = CMSyncConvertTime(
            CMTime(seconds: cutSourceSeconds, preferredTimescale: 60_000),
            from: outgoingTimebase, to: CMClockGetHostTimeClock()
        )
        let hostLeadSeconds = CMTimeGetSeconds(hostTime - CMClockGetTime(CMClockGetHostTimeClock()))
        guard hostLeadSeconds.isFinite, hostLeadSeconds > 0.025,
              hostLeadSeconds <= 0.3 else { return }
        scheduledLayerId = nextId
        session.startSynchronized(
            rate: Float(next.mapping.rate(atTimelineMs: cutMs)),
            sourceSeconds: sourceSeconds(for: next, timelineTimeMs: cutMs),
            atHostTime: hostTime
        )
    }

    private func invalidatePrewarm() {
        prewarmGeneration &+= 1
        if let scheduledLayerId,
           !activeNativeLayerIds.contains(scheduledLayerId) || heldNativeLayerIds.contains(scheduledLayerId) {
            stageSessions[scheduledLayerId]?.pause()
        }
        prewarmingLayerId = nil
        prewarmedLayerId = nil
        scheduledLayerId = nil
        for session in stageSessions.values { session.cancelPendingPrerolls() }
    }

    /// Clips with a speed curve: every playing player gets the speed the curve has at this moment.
    private func followSpeedCurves(atMs ms: Double) {
        for source in videoSources where source.mapping.curve != nil
            && ms >= source.mapping.layerStartMs && ms < source.mapping.layerStartMs + source.mapping.durationMs {
            stageSessions[source.layerId]?.follow(rate: Float(source.mapping.rate(atTimelineMs: ms)))
        }
    }

    private func seekStageSessions(
        atMs ms: Double,
        toleranceSeconds: Double,
        completion: ((Bool) -> Void)? = nil
    ) {
        let targets = activeVideoSources(atMs: ms)

        guard !targets.isEmpty else {
            completion?(true)
            return
        }

        var remaining = targets.count
        var allFinished = true
        for source in targets {
            let sourceTimelineMs = sourceTimelineTime(for: source, atMs: ms)
            stageSessions[source.layerId]?.seek(
                toSourceSeconds: sourceSeconds(for: source, timelineTimeMs: sourceTimelineMs),
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
        let active = activeVideoSources(atMs: ms)
        activeNativeLayerIds = Set(active.map(\.layerId))
        heldNativeLayerIds.removeAll()
        for source in active {
            let sourceTime = sourceTimelineTime(for: source, atMs: ms)
            if sourceTime == ms {
                stageSessions[source.layerId]?.play(rate: Float(source.mapping.rate(atTimelineMs: ms)))
            } else {
                heldNativeLayerIds.insert(source.layerId)
                stageSessions[source.layerId]?.pause()
                prewarmHeldTransitionSource(source, atMs: ms)
            }
        }
    }

    /// Starts an additional decoder when playback enters an overlap (a transition), without seeking the already-playing source.
    private func syncNativeSessions(atMs ms: Double) {
        let active = activeVideoSources(atMs: ms)
        let desired = Dictionary(uniqueKeysWithValues: active.map { ($0.layerId, $0) })
        for id in activeNativeLayerIds.subtracting(desired.keys) { stageSessions[id]?.pause() }
        let newlyActive = Set(desired.keys).subtracting(activeNativeLayerIds)
        let nextHeld = Set(active.compactMap { source -> String? in
            sourceTimelineTime(for: source, atMs: ms) == ms ? nil : source.layerId
        })
        let changedHoldState = nextHeld.symmetricDifference(heldNativeLayerIds)
        if !newlyActive.isEmpty || !changedHoldState.isEmpty {
            TransitionDiagnostics.log("sessions.change t=\(String(format: "%.1f", ms)) new=\(newlyActive.sorted().joined(separator: ",")) holdChange=\(changedHoldState.sorted().joined(separator: ",")) held=\(nextHeld.sorted().joined(separator: ","))")
        }
        activeNativeLayerIds = Set(desired.keys)
        heldNativeLayerIds = nextHeld
        for id in newlyActive.union(changedHoldState) {
            guard let source = desired[id], let session = stageSessions[id] else { continue }
            let sourceTime = sourceTimelineTime(for: source, atMs: ms)
            if !newlyActive.contains(id), !nextHeld.contains(id) {
                // The incoming player was already pre-seeked to its first frame
                // during the first half of the transition. Seeking it again at
                // the cut delays its clock and sends the playhead backwards
                // when that player becomes the native master.
                session.play(rate: Float(source.mapping.rate(atTimelineMs: ms)))
                continue
            }
            if nextHeld.contains(id) {
                // The outgoing player is already showing its last decoded
                // frame. A sample-accurate seek at the cut blocks the decoder
                // shared with the incoming player and cannot improve cadence.
                session.pause()
                if !newlyActive.contains(id) { continue }
            }
            session.seek(toSourceSeconds: sourceSeconds(for: source, timelineTimeMs: sourceTime), toleranceSeconds: 0) { [weak self] finished in
                guard let self, finished, self.mode == .playing,
                      self.activeVideoSources(atMs: self.currentTimeMs).contains(where: { $0.layerId == source.layerId }) else { return }
                let currentSourceTime = self.sourceTimelineTime(for: source, atMs: self.currentTimeMs)
                if currentSourceTime == self.currentTimeMs {
                    session.play(rate: Float(source.mapping.rate(atTimelineMs: currentSourceTime)))
                } else {
                    session.pause()
                    self.prewarmHeldTransitionSource(source, atMs: self.currentTimeMs)
                }
            }
        }
        for source in active where !newlyActive.contains(source.layerId) && !changedHoldState.contains(source.layerId) {
            if sourceTimelineTime(for: source, atMs: ms) == ms {
                stageSessions[source.layerId]?.play(rate: Float(source.mapping.rate(atTimelineMs: ms)))
            }
        }
    }

    private func prewarmHeldTransitionSource(_ source: VideoSource, atMs ms: Double) {
        guard source.mapping.layerStartMs > ms,
              transitionFramePlan.isVisible(source.layerId, at: ms),
              prewarmingLayerId != source.layerId,
              prewarmedLayerId != source.layerId,
              let session = stageSessions[source.layerId]
        else { return }
        prewarmingLayerId = source.layerId
        let generation = prewarmGeneration
        session.preroll(atRate: Float(source.mapping.rate(atTimelineMs: source.mapping.layerStartMs))) { [weak self] primed in
            guard let self, self.prewarmGeneration == generation,
                  self.prewarmingLayerId == source.layerId else { return }
            self.prewarmingLayerId = nil
            if primed { self.prewarmedLayerId = source.layerId }
            SplitPlaybackDiagnostics.log("transition.prewarm layer=\(source.layerId) primed=\(primed)")
        }
    }

    private func activeVideoSources(atMs ms: Double) -> [VideoSource] {
        videoSources.filter { source in
            let inClip = ms >= source.mapping.layerStartMs
                && ms < source.mapping.layerStartMs + source.mapping.durationMs
            return inClip || transitionFramePlan.isVisible(source.layerId, at: ms)
        }
    }

    private func sourceTimelineTime(for source: VideoSource, atMs ms: Double) -> Double {
        guard let layer = sourceLayers[source.layerId] else { return ms }
        return transitionFramePlan.sourceTimelineTime(for: layer, at: ms)
    }

    private func sourceSeconds(for source: VideoSource, timelineTimeMs: Double) -> Double {
        let frameMs = 1000 / max(latestProject?.composition.fps ?? 30, 1)
        let lastClipFrameMs = source.mapping.layerStartMs + max(0, source.mapping.durationMs - frameMs)
        let sourceMs = source.mapping.sourceMs(atTimelineMs: min(timelineTimeMs, lastClipFrameMs))
        return min(max(sourceMs, 0), max(0, source.durationMs - frameMs)) / 1000
    }

    private func pauseNativeSessions() {
        invalidatePrewarm()
        activeNativeLayerIds.removeAll()
        heldNativeLayerIds.removeAll()
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
