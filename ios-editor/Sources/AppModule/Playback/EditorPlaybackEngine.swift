import AVFoundation
import Observation

/// The editor's one playhead. Owns `currentTimeMs` — nothing else writes it —
/// and everything that moves it: Play/Pause, scrubbing, post-release
/// momentum, and the real `AVPlayer` that drives the clock during playback.
///
/// `EditorShellView` only issues commands (`play`, `beginScrub`, ...) and
/// reads state; `TimelineView`'s drag gesture and the fullscreen scrubber
/// call `beginScrub`/`scrub`/`endScrub`. Before this existed the clock had 6
/// writers spread over 3 files, and the scrub↔play hand-off was coordinated
/// by loose `@State` flags in views (see CLAUDE.md's playback-engine note).
///
/// ```
/// idle ──play──▶ playing ──pause / reached end──▶ idle
///   │              │
///   └─beginScrub◀──┘ (pauses first)
/// scrubbing ──endScrub(fast)──▶ coasting ──friction runs out──▶ idle
///          └──endScrub(slow)──▶ idle        coasting ──beginScrub──▶ scrubbing
/// ```
///
/// Evaluation of what to draw at `currentTimeMs` stays in `Runtime/`
/// (`sampleLayer`); this type knows nothing about layer content beyond which
/// video layer covers a given moment.
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

    // MARK: Live playback session

    private(set) var playbackPlayer: AVPlayer?
    private(set) var playbackAssetId: String?
    /// `false` from the moment a playback session starts until its initial
    /// seek has completed. Until then the player isn't handed to the Stage
    /// (it would show its old frame or black) and its time observer is
    /// ignored (it can still report the *old* position, which used to yank
    /// `currentTimeMs` backward for a moment on Play).
    private(set) var playbackSeekCompleted = false

    /// What `PreviewCanvas` should show live on top of the cached still —
    /// `nil` whenever nothing is playing and until the session's initial seek
    /// has completed.
    var activePlayerInfo: (assetId: String, player: AVPlayer)? {
        guard let playbackPlayer, let playbackAssetId, playbackSeekCompleted else { return nil }
        return (playbackAssetId, playbackPlayer)
    }

    // MARK: Internals

    @ObservationIgnored private var layers: [V2Layer] = []
    @ObservationIgnored private var assets: [V2Asset] = []
    @ObservationIgnored private var scrubStartTimeMs: Double = 0
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var playbackMapping: VideoTimeMapping?
    @ObservationIgnored private var playbackTimeObserver: Any?
    /// One `AVPlayer` created up front per video asset, not lazily on the
    /// first Play, so that first press has nothing left to warm up.
    @ObservationIgnored private var preloadedPlayers: [String: AVPlayer] = [:]

    /// A flick slower than this just stops; faster starts a coast.
    private static let minimumCoastMsPerSecond = 40.0
    /// Fraction of velocity *remaining* after one second of coasting — 0.04
    /// coasts a fast flick for roughly half a second before settling.
    private static let coastFrictionPerSecond = 0.04
    private static let coastStopMsPerSecond = 15.0
    private static let tickNanoseconds: UInt64 = 16_000_000

    init(project: V2Project) {
        update(project: project)
    }

    /// Call whenever the project changes (edit, undo/redo, live trim drag).
    func update(project: V2Project) {
        layers = project.layers
        assets = project.assets
        let layerEnds = project.layers.map { $0.timing.start + $0.timing.duration }
        let audioEnds = project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }
        maxDurationMs = max((layerEnds + audioEnds).max() ?? 1, 1)
    }

    // MARK: Transport

    func play() {
        guard mode != .playing else { return }
        cancelClock()
        mode = .playing
        startPlaybackClock()
    }

    func pause() {
        cancelClock()
        releaseRealPlayer()
        mode = .idle
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
        cancelClock()
        releaseRealPlayer()
        mode = .scrubbing
        scrubStartTimeMs = currentTimeMs
    }

    /// Moves the playhead relative to where `beginScrub()` found it.
    func scrub(deltaMs: Double) {
        guard mode == .scrubbing else { return }
        currentTimeMs = clamped(scrubStartTimeMs + deltaMs)
    }

    /// Moves the playhead to an absolute time (e.g. the fullscreen scrubber).
    func scrub(toMs ms: Double) {
        guard mode == .scrubbing else { return }
        currentTimeMs = clamped(ms)
    }

    /// `velocityMsPerSecond` is in timeline time (positive = moving forward).
    func endScrub(velocityMsPerSecond: Double) {
        guard mode == .scrubbing else { return }
        if abs(velocityMsPerSecond) > Self.minimumCoastMsPerSecond {
            mode = .coasting
            startCoasting(velocityMsPerSecond: velocityMsPerSecond)
        } else {
            mode = .idle
        }
    }

    // MARK: Clock loops

    private func cancelClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func startCoasting(velocityMsPerSecond: Double) {
        var velocity = velocityMsPerSecond
        var lastTick = Date()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
                guard let self, !Task.isCancelled, self.mode == .coasting else { return }
                let now = Date()
                let dt = now.timeIntervalSince(lastTick)
                lastTick = now
                velocity *= pow(Self.coastFrictionPerSecond, dt)
                let next = self.currentTimeMs + velocity * dt
                let bounded = self.clamped(next)
                self.currentTimeMs = bounded
                if bounded != next || abs(velocity) < Self.coastStopMsPerSecond {
                    self.mode = .idle
                    return
                }
            }
        }
    }

    private func startPlaybackClock() {
        var lastTick = Date()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
                guard let self, !Task.isCancelled, self.mode == .playing else { return }
                let now = Date()
                let dt = now.timeIntervalSince(lastTick)
                lastTick = now
                self.playbackTick(elapsedMs: dt * 1000)
            }
        }
    }

    private func playbackTick(elapsedMs: Double) {
        if let active = activeVideoLayer(atMs: currentTimeMs) {
            // A real video covers this instant — its own AVPlayer plays and
            // drives the clock; the software advance below is skipped for as
            // long as this stays true.
            ensureRealPlayerPlaying(for: active)
            return
        }
        releaseRealPlayer()
        let next = currentTimeMs + elapsedMs
        if next >= maxDurationMs {
            currentTimeMs = 0
            pause()
        } else {
            currentTimeMs = next
        }
    }

    private func clamped(_ ms: Double) -> Double {
        min(max(ms, 0), maxDurationMs)
    }

    // MARK: Real AVPlayer playback

    /// Creates (and starts warming up) one `AVPlayer` per distinct video
    /// asset. Idempotent.
    func preloadPlayers() {
        for layer in layers where layer.type == "video" {
            guard case .video(let payload) = layer.payload,
                  preloadedPlayers[payload.assetId] == nil,
                  let asset = assets.first(where: { $0.id == payload.assetId }),
                  case .video(let videoAsset) = asset,
                  let url = bundledURL(filename: videoAsset.uri)
            else { continue }
            let avAsset = AVURLAsset(url: url)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
            player.automaticallyWaitsToMinimizeStalling = false
            preloadedPlayers[payload.assetId] = player
            Task {
                _ = try? await avAsset.load(.duration, .tracks, .isPlayable)
            }
        }
    }

    /// The video layer (if any) whose own time range covers `ms` — at most
    /// one can be active at once, matching `PreviewCanvas.activePlayer`'s
    /// single-asset shape.
    private func activeVideoLayer(atMs ms: Double) -> (layer: V2Layer, assetId: String, url: URL)? {
        guard let layer = layers.first(where: { layer in
            layer.type == "video" && ms >= layer.timing.start && ms < layer.timing.start + layer.timing.duration
        }), case .video(let payload) = layer.payload,
              let asset = assets.first(where: { $0.id == payload.assetId }),
              case .video(let videoAsset) = asset,
              let url = bundledURL(filename: videoAsset.uri)
        else { return nil }
        return (layer, payload.assetId, url)
    }

    /// Makes sure the `AVPlayer` for the active clip is playing, seeking only
    /// when entering a clip whose source mapping differs from the one already
    /// playing (`VideoTimeMapping.isContinuous`) — so e.g. the two halves of
    /// a split play straight through without a re-seek.
    private func ensureRealPlayerPlaying(for active: (layer: V2Layer, assetId: String, url: URL)) {
        guard let mapping = VideoTimeMapping(layer: active.layer) else { return }
        if playbackAssetId == active.assetId, let player = playbackPlayer,
           let current = playbackMapping, current.isContinuous(with: mapping) {
            if player.rate == 0 { player.rate = Float(mapping.rate) }
            return
        }
        releaseRealPlayer()
        let player = preloadedPlayers[active.assetId] ?? AVPlayer(url: active.url)
        player.automaticallyWaitsToMinimizeStalling = false
        playbackPlayer = player
        playbackAssetId = active.assetId
        playbackMapping = mapping
        playbackSeekCompleted = false

        let sourceSeconds = mapping.sourceMs(atTimelineMs: currentTimeMs) / 1000
        player.seek(to: CMTime(seconds: sourceSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, finished, self.playbackPlayer === player else { return }
                self.playbackSeekCompleted = true
            }
        }

        let interval = CMTime(seconds: 1.0 / 60, preferredTimescale: 600)
        playbackTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.playbackSeekCompleted, self.playbackPlayer === player else { return }
                let timelineMs = mapping.timelineMs(atSourceMs: time.seconds * 1000)
                if timelineMs >= self.maxDurationMs {
                    self.currentTimeMs = 0
                    // Deferred: removing a time observer from inside its own
                    // callback is best avoided.
                    Task { @MainActor in self.pause() }
                } else {
                    self.currentTimeMs = timelineMs
                }
            }
        }
        player.rate = Float(mapping.rate)
    }

    /// Pauses and tears down the playback session.
    private func releaseRealPlayer() {
        guard let player = playbackPlayer else { return }
        player.pause()
        if let observer = playbackTimeObserver {
            player.removeTimeObserver(observer)
            playbackTimeObserver = nil
        }
        playbackPlayer = nil
        playbackAssetId = nil
        playbackMapping = nil
        playbackSeekCompleted = false
    }
}
