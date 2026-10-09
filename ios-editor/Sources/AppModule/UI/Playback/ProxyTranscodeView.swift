import AVFoundation
import SwiftUI

/// Tests the proxy-transcode idea directly: re-encode a bundled sample
/// video into a downscaled, short-GOP proxy (`ProxyTranscoder`), then
/// measure zero-tolerance seek latency at the same random points on both
/// the original and the proxy — a number, not a feeling, for whether a
/// short keyframe interval actually removes the keyframe-walk cost this
/// app measured and documented (source clips here have a keyframe every
/// 250 frames / ~8.3s).
struct ProxyTranscodeView: View {
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
    @State private var maxKeyFrameInterval: Double = 1
    @State private var isTranscoding = false
    @State private var progress: Double = 0
    @State private var result: ProxyTranscoder.Result?
    @State private var errorText: String?
    @State private var isMeasuring = false
    @State private var originalLatencies: [Double] = []
    @State private var proxyLatencies: [Double] = []
    @State private var showingProxy = false
    @State private var player = AVPlayer()
    @State private var previewDurationSeconds: Double = 1
    @State private var sliderSeconds: Double = 0
    @State private var isScrubbingPreview = false
    @State private var isPreviewPlaying = false
    @State private var previewTimeObserver: Any?
    @State private var scrubDirectionLog = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Clip", selection: $clip) {
                    ForEach(SampleClip.allCases) { clip in
                        Text(clip.label).tag(clip)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: clip) { _, _ in reset() }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max keyframe interval: \(Int(maxKeyFrameInterval)) frame\(Int(maxKeyFrameInterval) == 1 ? " (all-intra)" : "")")
                        .font(.caption)
                    Slider(value: $maxKeyFrameInterval, in: 1...60, step: 1)
                }

                Button {
                    runTranscode()
                } label: {
                    if isTranscoding {
                        HStack { ProgressView(); Text("Transcoding… \(Int(progress * 100))%") }
                    } else {
                        Text("Generate proxy")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTranscoding)

                if let errorText {
                    Text("Error: \(errorText)").font(.caption).foregroundStyle(.red)
                }

                if let result {
                    resultSummary(result)

                    Button {
                        runLatencyMeasurement(result: result)
                    } label: {
                        if isMeasuring {
                            HStack { ProgressView(); Text("Measuring seeks…") }
                        } else {
                            Text("Measure seek latency (6 points)")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isMeasuring)

                    if !originalLatencies.isEmpty {
                        latencyComparison
                    }

                    previewSection(result)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("Proxy Test")
        .onDisappear {
            if let previewTimeObserver { player.removeTimeObserver(previewTimeObserver) }
            previewTimeObserver = nil
            player.pause()
        }
    }

    @ViewBuilder
    private func resultSummary(_ result: ProxyTranscoder.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transcode: \(String(format: "%.2f", result.transcodeSeconds))s").font(.caption.monospaced())
            Text("Original: \(formattedBytes(result.originalBytes))  →  Proxy: \(formattedBytes(result.proxyBytes))")
                .font(.caption.monospaced())
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var latencyComparison: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zero-tolerance seek latency, same 6 random points:").font(.caption.bold())
            ForEach(0..<originalLatencies.count, id: \.self) { index in
                Text(String(format: "point %d:  original %5.0fms   proxy %5.0fms", index, originalLatencies[index] * 1000, proxyLatencies[safe: index].map { $0 * 1000 } ?? 0))
                    .font(.caption2.monospaced())
            }
            let avgOriginal = originalLatencies.reduce(0, +) / Double(originalLatencies.count)
            let avgProxy = proxyLatencies.isEmpty ? 0 : proxyLatencies.reduce(0, +) / Double(proxyLatencies.count)
            Text(String(format: "AVERAGE:  original %.0fms   proxy %.0fms   (%.1fx faster)", avgOriginal * 1000, avgProxy * 1000, avgProxy > 0 ? avgOriginal / avgProxy : 0))
                .font(.caption.bold().monospaced())
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func previewSection(_ result: ProxyTranscoder.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual scrub — drag back and forth and feel the difference yourself, same as Playback Sandbox.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Source", selection: $showingProxy) {
                Text("Original").tag(false)
                Text("Proxy").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: showingProxy) { _, newValue in
                loadPreview(proxy: newValue, result: result)
            }

            PlayerPreview(player: player)
                .frame(height: 300)
                .background(Color.black)
                .onAppear { loadPreview(proxy: showingProxy, result: result) }

            Text(scrubDirectionLog)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(height: 14)

            Slider(
                value: $sliderSeconds,
                in: 0...max(previewDurationSeconds, 0.01),
                onEditingChanged: { editing in
                    isScrubbingPreview = editing
                    if editing {
                        player.pause()
                    } else {
                        seekPreview(to: sliderSeconds, precise: true)
                        if isPreviewPlaying { player.play() }
                    }
                }
            )
            .onChange(of: sliderSeconds) { old, new in
                guard isScrubbingPreview else { return }
                scrubDirectionLog = new >= old ? "→ forward" : "← backward"
                seekPreview(to: new, precise: false)
            }

            HStack {
                Text(formattedTime(sliderSeconds))
                Spacer()
                Button {
                    isPreviewPlaying.toggle()
                    isPreviewPlaying ? player.play() : player.pause()
                } label: {
                    Image(systemName: isPreviewPlaying ? "pause.fill" : "play.fill")
                }
                Spacer()
                Text(formattedTime(previewDurationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func reset() {
        result = nil
        errorText = nil
        originalLatencies = []
        proxyLatencies = []
        showingProxy = false
        sliderSeconds = 0
        isPreviewPlaying = false
        player.pause()
    }

    private func runTranscode() {
        guard let sourceURL = bundledURL(filename: clip.rawValue) else {
            errorText = "bundled file not found"
            return
        }
        reset()
        isTranscoding = true
        progress = 0
        Task {
            do {
                let result = try await ProxyTranscoder.makeProxy(
                    sourceURL: sourceURL,
                    targetLongEdge: 960,
                    maxKeyFrameInterval: Int(maxKeyFrameInterval)
                ) { value in
                    progress = value
                }
                self.result = result
            } catch {
                errorText = "\(error)"
            }
            isTranscoding = false
        }
    }

    private func runLatencyMeasurement(result: ProxyTranscoder.Result) {
        guard let sourceURL = bundledURL(filename: clip.rawValue) else { return }
        isMeasuring = true
        Task {
            let duration = (try? await AVURLAsset(url: sourceURL).load(.duration))?.seconds ?? 10
            let points = (0..<6).map { _ in Double.random(in: 0.5...(max(duration - 0.5, 1))) }
            async let originalResult = ProxyTranscoder.measureSeekLatency(url: sourceURL, atSeconds: points)
            async let proxyResult = ProxyTranscoder.measureSeekLatency(url: result.outputURL, atSeconds: points)
            originalLatencies = await originalResult
            proxyLatencies = await proxyResult
            isMeasuring = false
        }
    }

    private func loadPreview(proxy: Bool, result: ProxyTranscoder.Result) {
        guard let sourceURL = bundledURL(filename: clip.rawValue) else { return }
        let url = proxy ? result.outputURL : sourceURL
        if let previewTimeObserver { player.removeTimeObserver(previewTimeObserver) }
        isPreviewPlaying = false
        player.pause()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        Task {
            guard let duration = try? await item.asset.load(.duration), duration.isValid, !duration.isIndefinite else { return }
            previewDurationSeconds = max(duration.seconds, 0.01)
        }
        previewTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { time in
            guard !isScrubbingPreview else { return }
            sliderSeconds = time.seconds
        }
    }

    private func seekPreview(to seconds: Double, precise: Bool) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 0.2, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = max(seconds, 0)
        let m = Int(total) / 60
        let s = Int(total) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct PlayerPreview: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class ContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

#Preview {
    NavigationStack { ProxyTranscodeView() }
}
