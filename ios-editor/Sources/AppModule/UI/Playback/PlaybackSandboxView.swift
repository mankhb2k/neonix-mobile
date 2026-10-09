import AVFoundation
import SwiftUI

/// A playback test bed that answers one question in isolation: does scrub +
/// Play feel right using nothing but stock `AVPlayer`/`AVPlayerLayer`, with
/// no `V2Project`, no Runtime (`KeyframeSampler`), no `EditorPlaybackEngine`,
/// no `VideoFrameServer`/`AVAssetReader`, no `AudioMixEngine`?
///
/// This exists because debugging the real Editor's playback pipeline kept
/// conflating variables: a stuck black Stage could be the custom decoder,
/// the custom clock, SwiftUI's own Observation overhead, *or* (confirmed
/// once, on the simulator — see this session's own investigation) the
/// audio engine wedging the main actor. Reproducing a symptom here first
/// tells you whether it's inherent to this phone/OS/video file at all, or
/// specific to one of this app's own custom layers — add pieces back
/// (a custom clock, a custom decoder, audio) one at a time from here,
/// rather than guessing inside the fully-assembled Editor.
///
/// Deliberately not reusing any of `Playback/` or `Runtime/` — if those
/// have a bug, this view must not inherit it.
struct PlaybackSandboxView: View {
    private enum SampleClip: String, CaseIterable, Identifiable {
        case portrait = "13792197_1080_1920_30fps.mp4"
        case landscape = "12253998_1920_1080_30fps.mp4"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .portrait: return "Portrait (9:16)"
            case .landscape: return "Landscape (16:9)"
            }
        }
    }

    @State private var clip: SampleClip = .portrait
    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var durationSeconds: Double = 1
    @State private var sliderSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserver: Any?
    @State private var seekCoordinator: PlayerSeekCoordinator?
    @State private var lastDirectionLog: String = ""
    @State private var audioHarness = AudioStressHarness()

    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            Picker("Clip", selection: $clip) {
                ForEach(SampleClip.allCases) { clip in
                    Text(clip.label).tag(clip)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: clip) { _, newValue in load(newValue) }

            PlayerLayerView(player: player)
                .background(Color.black)
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 420)
                .padding(.horizontal)

            Text(lastDirectionLog)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(height: 16)

            VStack(spacing: 4) {
                Slider(
                    value: $sliderSeconds,
                    in: 0...max(durationSeconds, 0.01),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing {
                            // Scrubbing is preview-only. It must never resume
                            // playback implicitly; the user explicitly taps
                            // Play after choosing a new position.
                            if isPlaying {
                                player.pause()
                                isPlaying = false
                            }
                        } else {
                            // Settle on the exact released frame, but remain
                            // paused regardless of the state before the drag.
                            seek(to: sliderSeconds, precise: true)
                        }
                    }
                )
                .onChange(of: sliderSeconds) { old, new in
                    guard isScrubbing else { return }
                    lastDirectionLog = new >= old ? "→ forward" : "← backward"
                    seek(to: new, precise: false)
                }
                HStack {
                    Text(formatted(sliderSeconds))
                    Spacer()
                    Text(formatted(durationSeconds))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
            }

            Text("Native AVPlayer only — no custom clock, no custom decoder, no Runtime, no audio engine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider().padding(.vertical, 4)

            audioStressSection
        }
        .padding(.top)
        }
        .navigationTitle("Playback Sandbox")
        .onAppear { load(clip) }
        .onDisappear {
            removeTimeObserver()
            audioHarness.stop()
        }
    }

    /// Isolated repro for the hang this session's own investigation traced
    /// to `AudioMixEngine`: a bare `AVAudioEngine` driven through the exact
    /// same attach→connect→start→play→stop→detach sequence, in a tight
    /// loop, with no `V2Project`/Editor/Runtime in the way. The heartbeat
    /// counter is the diagnostic — it's driven by its own independent Task,
    /// so if it keeps climbing while the log stalls, only the audio call
    /// itself is stuck; if it freezes too, the audio call wedged the whole
    /// MainActor (matching what this session saw with NSLog + `simctl`).
    private var audioStressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio stress test").font(.headline)
                Spacer()
                Text("heartbeat: \(audioHarness.heartbeat)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(audioHarness.isRunning ? .primary : .secondary)
            }
            Text("Rapid attach → connect → start → play → stop → detach on a bare AVAudioEngine, isolated from video/Runtime/Editor. If the heartbeat above stops advancing too, the audio call itself is wedging the whole MainActor.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(audioHarness.isRunning ? "Stop" : "Run 20 cycles") {
                if audioHarness.isRunning {
                    audioHarness.stop()
                } else {
                    audioHarness.start(cycles: 20)
                }
            }
            .buttonStyle(.bordered)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(audioHarness.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 180)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .onChange(of: audioHarness.logLines.count) { _, newCount in
                    guard newCount > 0 else { return }
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
        .padding(.horizontal)
    }

    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to seconds: Double, precise: Bool, completion: ((Bool) -> Void)? = nil) {
        guard let seekCoordinator else { return }
        seekCoordinator.request(
            seconds: seconds,
            toleranceSeconds: precise ? 0 : 0.2,
            completion: completion
        )
    }

    private func load(_ clip: SampleClip) {
        removeTimeObserver()
        isPlaying = false
        seekCoordinator?.cancelPendingSeeks()
        guard let url = bundledURL(filename: clip.rawValue) else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        seekCoordinator = PlayerSeekCoordinator(player: player)
        Task {
            guard let duration = try? await item.asset.load(.duration), duration.isValid, !duration.isIndefinite else { return }
            durationSeconds = max(duration.seconds, 0.01)
        }
        let observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { time in
            guard !isScrubbing else { return }
            sliderSeconds = time.seconds
        }
        timeObserver = observer
    }

    private func removeTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func formatted(_ seconds: Double) -> String {
        let total = max(seconds, 0)
        let m = Int(total) / 60
        let s = Int(total) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// Thinnest possible bridge to a real `AVPlayerLayer` — no still-frame
/// fallback, no decoded-frame cache, nothing but what `AVPlayerLayer`
/// itself draws.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

/// Drives a bare `AVAudioEngine` through the same attach/connect/start/
/// play/stop/detach sequence `AudioMixEngine.startNode`/`stopNode` use —
/// copied by hand, not by importing that type, so a bug in `AudioMixEngine`
/// itself can never leak into this control group. `heartbeat` is the point:
/// it only proves anything because it's driven by a *separate* `Task`, so a
/// MainActor wedge inside the audio call stops it too, same as it would
/// stop everything else on screen.
@MainActor
@Observable
final class AudioStressHarness {
    private(set) var logLines: [String] = []
    private(set) var heartbeat = 0
    private(set) var isRunning = false

    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var stressTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private let engine = AVAudioEngine()

    func start(cycles: Int) {
        guard !isRunning else { return }
        isRunning = true
        logLines.removeAll()
        heartbeat = 0
        startedAt = Date()
        log("start, cycles=\(cycles)")

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.heartbeat += 1
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        stressTask = Task { [weak self] in
            await self?.runCycles(cycles)
            self?.isRunning = false
            self?.log("done")
        }
    }

    func stop() {
        stressTask?.cancel()
        heartbeatTask?.cancel()
        isRunning = false
    }

    private func runCycles(_ cycles: Int) async {
        guard let url = bundledURL(filename: "audio-demo.mp3") else {
            log("ERROR: audio-demo.mp3 not found in bundle")
            return
        }
        for cycle in 0..<cycles {
            guard !Task.isCancelled else {
                log("cancelled at cycle \(cycle)")
                return
            }
            guard let audioFile = try? AVAudioFile(forReading: url) else {
                log("cycle \(cycle): AVAudioFile init failed")
                continue
            }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: audioFile.processingFormat)
            // Matches `AudioMixEngine.startNode`'s call exactly — except
            // this function is itself `async`, and this SDK apparently
            // added an `async` overload of `scheduleSegment` with an
            // otherwise-identical signature: inside an async context, Swift
            // silently prefers *that* one over the classic fire-and-forget
            // version `AudioMixEngine`'s (non-async) call site resolves to.
            // That async overload is what hung in the first version of this
            // test — passing the completion-handler parameters explicitly
            // forces the classic, non-blocking overload instead.
            node.scheduleSegment(
                audioFile, startingFrame: 0, frameCount: AVAudioFrameCount(audioFile.length), at: nil,
                completionCallbackType: .dataConsumed, completionHandler: nil
            )

            if !engine.isRunning {
                log("cycle \(cycle): engine.start() calling")
                do {
                    try engine.start()
                    log("cycle \(cycle): engine.start() OK")
                } catch {
                    log("cycle \(cycle): engine.start() threw \(error)")
                    engine.detach(node)
                    continue
                }
            }

            log("cycle \(cycle): node.play() calling")
            node.play()
            log("cycle \(cycle): node.play() returned")

            try? await Task.sleep(nanoseconds: 200_000_000)

            log("cycle \(cycle): stop+detach calling")
            node.stop()
            engine.detach(node)
            log("cycle \(cycle): stop+detach done")
        }
    }

    private func log(_ message: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        logLines.append(String(format: "[%6.2fs] %@", elapsed, message))
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }
}

#Preview {
    NavigationStack { PlaybackSandboxView() }
}
