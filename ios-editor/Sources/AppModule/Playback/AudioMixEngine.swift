import AVFoundation

/// Real audio playback — the "step 3" gap CLAUDE.md's `EditorPlaybackEngine`
/// doc comment already named ("real audio must later follow `currentTimeMs`").
/// Before this, nothing in the app ever produced sound: the Stage draws
/// decoded `CGImage` frames, not an `AVPlayer`, and no `AVAudioEngine`/
/// `AVAudioPlayerNode` existed anywhere.
///
/// This owns decode + mixing; `EditorPlaybackEngine` stays the one clock and
/// tells this *when* to be at a given `currentTimeMs`, the same way it
/// already tells the video players
/// when to have frames ready.
///
/// **Sync model, deliberately simple for this pass**: audio only ever plays
/// during real Play (`mode == .playing`), never while scrubbing/coasting —
/// `EditorPlaybackEngine` only calls `play(atMs:)`/`advance(toMs:)` from its
/// own `play()`/`playbackTick`. Every `play(atMs:)` call fully stops and
/// reschedules every active node from scratch at the given time (no
/// `AVAudioPlayerNode.pause()`/resume bookkeeping), which is also the resync
/// point. This bounds drift between the video player's clock
/// and the audio hardware clock to "however long one uninterrupted Play run
/// has lasted since the last resync", not true sample-accurate master-clock
/// sync — closing that further is the same deferred "real audio clock" work
/// CLAUDE.md already flags, not new scope this pass.
@MainActor
final class AudioMixEngine {
    struct AudioSource {
        let id: String
        let url: URL
        let startMs: Double
        let durationMs: Double
        let trimStartMs: Double
        let gainDb: Double
        let pan: Double
        let fadeIn: V2AudioFade?
        let fadeOut: V2AudioFade?
    }

    private let engine = AVAudioEngine()
    /// `private(set)` rather than fully `private` — `AudioMixEngineTests`
    /// reads this to verify `update(project:)` builds the right source list
    /// without needing a real `AVAudioEngine` render pass.
    private(set) var sources: [AudioSource] = []
    private var activeNodes: [String: AVAudioPlayerNode] = [:]
    /// One gain stage per playing node, after it: a player node's own `volume` stops at 1 (0 dB), the boost above that (up to +12 dB, the Volume
    /// tool) is `AVAudioUnitEQ.globalGain`.
    private var activeBoosts: [String: AVAudioUnitEQ] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]
    private var unreadable: Set<String> = []

    /// Call whenever the project changes — rebuilds the source list from
    /// `project.audio`'s standalone clips plus every video layer's embedded
    /// audio derivative (`V2VideoAudioDerivative`), same two places
    /// `TimelineView` already reads for waveform display.
    func update(project: V2Project) {
        var next: [AudioSource] = []

        for track in project.audio.tracks where !track.muted {
            for clip in track.clips where clip.enabled ?? true {
                guard let asset = project.assets.first(where: { $0.id == clip.assetId }),
                      case .audio(let audioAsset) = asset,
                      let url = bundledURL(filename: audioAsset.uri)
                else { continue }
                next.append(AudioSource(
                    id: clip.id, url: url,
                    startMs: clip.timing.start, durationMs: clip.timing.duration,
                    trimStartMs: clip.trim.start,
                    gainDb: (clip.gainDb ?? 0) + (track.gainDb ?? 0),
                    pan: clip.pan ?? track.pan,
                    fadeIn: clip.fadeIn, fadeOut: clip.fadeOut
                ))
            }
        }

        // A video clip's own sound: on unless switched off (`audio.enabled == false`), read straight from the video file (or its audio derivative),
        // at the clip's gain. Only at normal speed: this engine never retimes, so a sped-up or curved clip stays silent rather than play at the wrong pitch.
        for layer in project.layers {
            guard case .video(let payload) = layer.payload,
                  payload.audio?.enabled ?? true,
                  (payload.playbackRate ?? 1) == 1, payload.speedCurve == nil,
                  let asset = project.assets.first(where: { $0.id == payload.assetId }),
                  case .video(let videoAsset) = asset,
                  let url = bundledURL(filename: videoAsset.audio?.uri ?? videoAsset.uri)
            else { continue }
            let embedded = payload.audio
            next.append(AudioSource(
                id: layer.id, url: url,
                startMs: layer.timing.start, durationMs: layer.timing.duration,
                trimStartMs: payload.trimStart ?? 0,
                gainDb: embedded?.gainDb ?? 0,
                pan: embedded?.pan ?? 0,
                fadeIn: embedded?.fadeIn, fadeOut: embedded?.fadeOut
            ))
        }

        sources = next
        let validIds = Set(next.map(\.id))
        for (id, node) in activeNodes where !validIds.contains(id) {
            stopNode(node, id: id)
        }
    }

    /// Fully resyncs: stops everything currently playing, then starts every
    /// source that covers `atMs`. Called once when Play begins/resumes.
    /// Deliberately does **not** start `AVAudioEngine` itself when there's
    /// nothing to play — most projects/tests have no audio at all, and
    /// touching real audio hardware/session for no reason is both wasted
    /// work and (confirmed the hard way: it hung `EditorPlaybackEngineTests`
    /// for 600s in the test runner, which has no audio session configured)
    /// a real source of flakiness outside a real app process. `startNode`
    /// is the one place that actually calls `engine.start()`, lazily, only
    /// once a node is about to play.
    func play(atMs: Double) {
        for (id, node) in activeNodes { stopNode(node, id: id) }
        activate(atMs: atMs)
    }

    /// Stops all sound immediately — Pause, scrub start and end-of-timeline.
    func pause() {
        for (id, node) in activeNodes { stopNode(node, id: id) }
    }

    /// Called every `playbackTick` while actually playing: starts any
    /// source that just came into range, stops any whose range just ended,
    /// and updates each still-active node's volume for its fade curve.
    func advance(toMs ms: Double) {
        activate(atMs: ms)
        for (id, node) in activeNodes {
            guard let source = sources.first(where: { $0.id == id }) else { continue }
            if ms >= source.startMs + source.durationMs {
                stopNode(node, id: id)
            } else {
                setGain(volume(for: source, atMs: ms), node: node, boost: activeBoosts[id])
            }
        }
    }

    private func activate(atMs: Double) {
        for source in sources {
            guard atMs >= source.startMs, atMs < source.startMs + source.durationMs else { continue }
            guard activeNodes[source.id] == nil else { continue }
            startNode(for: source, atMs: atMs)
        }
    }

    private func startNode(for source: AudioSource, atMs: Double) {
        guard let file = audioFile(for: source.url) else { return }
        let sampleRate = file.processingFormat.sampleRate
        let elapsedMs = atMs - source.startMs
        let fileSeconds = max(source.trimStartMs + elapsedMs, 0) / 1000
        let startFrame = AVAudioFramePosition(fileSeconds * sampleRate)
        guard startFrame < file.length else { return }

        let remainingMs = source.durationMs - elapsedMs
        let requestedFrames = AVAudioFrameCount(max(remainingMs, 0) / 1000 * sampleRate)
        let availableFrames = AVAudioFrameCount(file.length - startFrame)
        let frameCount = min(requestedFrames, availableFrames)
        guard frameCount > 0 else { return }

        let node = AVAudioPlayerNode()
        let boost = AVAudioUnitEQ(numberOfBands: 0)   // no bands: only its global gain is used
        engine.attach(node)
        engine.attach(boost)
        engine.connect(node, to: boost, format: file.processingFormat)
        engine.connect(boost, to: engine.mainMixerNode, format: file.processingFormat)
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
        setGain(volume(for: source, atMs: atMs), node: node, boost: boost)
        node.pan = Float(min(max(source.pan, -1), 1))
        if !engine.isRunning {
            Self.activatePlaybackSession()
            guard (try? engine.start()) != nil else {
                engine.detach(node)
                engine.detach(boost)
                return
            }
        }
        node.play()
        activeNodes[source.id] = node
        activeBoosts[source.id] = boost
    }

    /// Playback must not depend on whatever session state the app was left in: `.playback` plays through the speaker and ignores the
    /// silent switch (a video editor's sound is the point), and undoes the recorder's `.playAndRecord` (earpiece, quiet).
    private static func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func stopNode(_ node: AVAudioPlayerNode, id: String) {
        node.stop()
        engine.detach(node)
        if let boost = activeBoosts.removeValue(forKey: id) { engine.detach(boost) }
        activeNodes.removeValue(forKey: id)
    }

    /// Up to 1 (0 dB) the node's own volume does it; above that the node stays at full and the boost stage adds the rest in dB.
    private func setGain(_ gain: Float, node: AVAudioPlayerNode, boost: AVAudioUnitEQ?) {
        node.volume = min(gain, 1)
        boost?.globalGain = gain > 1 ? 20 * log10(gain) : 0
    }

    private func audioFile(for url: URL) -> AVAudioFile? {
        if let cached = audioFiles[url.path] { return cached }
        if unreadable.contains(url.path) { return nil }   // a video with no sound track: asked once, not on every tick
        guard let file = try? AVAudioFile(forReading: url) else { unreadable.insert(url.path); return nil }
        audioFiles[url.path] = file
        return file
    }

    /// `gainDb` converted to linear, scaled down by however far into a
    /// fade-in/fade-out window `atMs` currently sits (1.0 outside either
    /// window). Equal-power uses `sin`/`cos` of a quarter turn — the
    /// standard constant-perceived-loudness curve; linear fades blend
    /// value, not power, matching `V2AudioFadeCurve`'s own two cases.
    /// Internal, not `private` — `AudioMixEngineTests` exercises the fade
    /// curve math directly, pure function, no engine state involved.
    func volume(for source: AudioSource, atMs: Double) -> Float {
        // Mute (-60 dB and below) is silence, +20 dB is 10x; the fades are `AudioFadeEnvelope`, the same curve the timeline draws.
        let gain = VolumeScale.linearGain(source.gainDb)
            * AudioFadeEnvelope.gain(elapsedMs: atMs - source.startMs, durationMs: source.durationMs, fadeIn: source.fadeIn, fadeOut: source.fadeOut)
        return Float(gain)
    }
}
