import Foundation
import Observation

/// The editor's one playhead. Owns `currentTimeMs` — nothing else writes it —
/// and everything that moves it: Play/Pause, scrubbing and post-release
/// momentum, all driven by one display-synced clock (`DisplayLinkClock`).
///
/// Play and scrub are the same pipeline: the engine only moves
/// `currentTimeMs`; every change asks `VideoFrameServer` to have the frames
/// for that moment ready, and the Stage always draws the frame at
/// `currentTimeMs`. There is no `AVPlayer` on the Stage, so there is no
/// player/still hand-off to flash. During Play, if a video frame for the
/// next moment isn't decoded yet the clock holds (like a player buffering)
/// instead of skipping ahead.
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
        let assetId: String
        let url: URL
        let mapping: VideoTimeMapping
    }

    @ObservationIgnored private var videoSources: [VideoSource] = []
    @ObservationIgnored private var scrubStartTimeMs: Double = 0
    @ObservationIgnored private var coastVelocityMsPerSecond: Double = 0
    @ObservationIgnored private var stalledSeconds: Double = 0
    @ObservationIgnored private let clock = DisplayLinkClock()
    /// Test seam: decides whether every video frame needed at a timeline time
    /// is decoded. Defaults to asking `VideoFrameServer`.
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
        update(project: project)
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
            return VideoSource(assetId: payload.assetId, url: url, mapping: mapping)
        }
        let layerEnds = project.layers.map { $0.timing.start + $0.timing.duration }
        let audioEnds = project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }
        maxDurationMs = max((layerEnds + audioEnds).max() ?? 1, 1)
        prefetchFrames()
    }

    /// Starts decoding around the current time — call once when the editor
    /// appears so the first frame is ready before anything moves.
    func prepare() {
        prefetchFrames()
    }

    // MARK: Transport

    func play() {
        guard mode != .playing else { return }
        clock.stop()
        mode = .playing
        stalledSeconds = 0
        clock.start { [weak self] dt in self?.playbackTick(dt) }
    }

    func pause() {
        clock.stop()
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
        clock.stop()
        mode = .scrubbing
        scrubStartTimeMs = currentTimeMs
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
        }
    }

    private func playbackTick(_ dt: Double) {
        guard mode == .playing else { return }
        let next = currentTimeMs + dt * 1000
        if next >= maxDurationMs {
            setTime(0)
            pause()
            return
        }
        if !framesReady(atMs: next), stalledSeconds < Self.maxStallSeconds {
            stalledSeconds += dt
            return
        }
        stalledSeconds = 0
        setTime(next)
    }

    // MARK: Time + frames

    /// The only place `currentTimeMs` is written.
    private func setTime(_ ms: Double) {
        currentTimeMs = clamped(ms)
        prefetchFrames()
    }

    private func clamped(_ ms: Double) -> Double {
        min(max(ms, 0), maxDurationMs)
    }

    /// Every video clip covering the playhead (or starting just ahead of it)
    /// gets its frames positioned around its own source time.
    private func prefetchFrames() {
        for source in videoSources {
            let start = source.mapping.layerStartMs
            let end = start + source.mapping.durationMs
            guard currentTimeMs >= start - Self.upcomingClipLookaheadMs, currentTimeMs < end else { continue }
            let sourceSeconds = source.mapping.sourceMs(atTimelineMs: currentTimeMs) / 1000
            VideoFrameServer.shared.prefetch(assetId: source.assetId, url: source.url, atSeconds: sourceSeconds)
        }
    }

    private func framesReady(atMs ms: Double) -> Bool {
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
}
