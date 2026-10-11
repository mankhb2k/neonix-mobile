import AVFoundation
import SwiftUI

/// Crop for a video longer than its slot: drag a window of exactly the slot's length along the clip's filmstrip.
/// The preview loops the chosen window.
struct SlotCropView: View {
    let library: PhotoLibrary
    let media: PickedMedia
    let slotMs: Int
    let onDone: (Double) -> Void
    let onCancel: () -> Void

    @State private var avAsset: AVAsset?
    @State private var frames: [UIImage] = []
    @State private var startMs: Double
    @State private var dragOrigin: Double?
    @State private var player = AVPlayer()
    @State private var timeObserver: Any?

    init(library: PhotoLibrary, media: PickedMedia, slotMs: Int, onDone: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.library = library
        self.media = media
        self.slotMs = slotMs
        self.onDone = onDone
        self.onCancel = onCancel
        _startMs = State(initialValue: media.cropStartMs)
    }

    private var maxStartMs: Double { max(0, media.durationMs - Double(slotMs)) }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Text("Crop").font(.headline)
                Spacer()
                Button("Done") { onDone(startMs) }.fontWeight(.semibold)
            }
            .padding(.horizontal)

            PlayerSurface(player: player)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 40)
                .overlay { if avAsset == nil { ProgressView() } }

            Text("\(timeLabel(startMs)) – \(timeLabel(startMs + Double(slotMs)))  ·  \(String(format: "%.1f", Double(slotMs) / 1000)) s of \(String(format: "%.1f", media.durationMs / 1000)) s")
                .font(.footnote.monospacedDigit()).foregroundColor(.secondary)

            filmstrip
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 12)
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await load() }
        .onChange(of: startMs) { _, _ in restartWindow() }
        .onDisappear { stop() }
    }

    private var filmstrip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let windowWidth = width * min(1, Double(slotMs) / max(media.durationMs, 1))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        Image(uiImage: frame).resizable().scaledToFill()
                            .frame(width: width / CGFloat(max(frames.count, 1)), height: 56).clipped()
                    }
                }
                .frame(width: width, height: 56, alignment: .leading)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: windowWidth, height: 56)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .offset(x: width * startMs / max(media.durationMs, 1))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragOrigin == nil { dragOrigin = startMs }
                                let delta = Double(value.translation.width / max(width, 1)) * media.durationMs
                                startMs = SlotRules.clampedCropStart((dragOrigin ?? 0) + delta, mediaMs: media.durationMs, slotMs: slotMs)
                            }
                            .onEnded { _ in dragOrigin = nil }
                    )
            }
        }
        .frame(height: 56)
    }

    private func timeLabel(_ ms: Double) -> String {
        String(format: "%d:%04.1f", Int(ms / 60000), (ms / 1000).truncatingRemainder(dividingBy: 60))
    }

    // MARK: Loading + preview

    private func load() async {
        guard let asset = await library.avAsset(for: media.asset) else { return }
        avAsset = asset
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        player.isMuted = true
        restartWindow()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let count = 10
        let times = (0..<count).map { CMTime(seconds: media.durationMs / 1000 * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [UIImage] = []
        for await result in generator.images(for: times) {
            if let cgImage = try? result.image { images.append(UIImage(cgImage: cgImage)) }
        }
        frames = images
    }

    /// Plays the chosen window on a loop: seek to its start, jump back when it ends.
    private func restartWindow() {
        guard avAsset != nil else { return }
        stop()
        let start = CMTime(seconds: startMs / 1000, preferredTimescale: 600)
        let end = CMTime(seconds: (startMs + Double(slotMs)) / 1000, preferredTimescale: 600)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        timeObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [player] in
            player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    private func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
    }
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class View: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> View {
        let view = View()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: View, context: Context) { view.playerLayer.player = player }
}
