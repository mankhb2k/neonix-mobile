import AVKit
import SwiftUI

/// The rawest possible playback baseline: Apple's own system video player
/// chrome (`AVPlayerViewController` — literally the same player UI Photos,
/// Safari and Messages use for an inline video), wired to nothing this app
/// wrote. No custom clock, no custom decoder (`VideoFrameServer`), no
/// `AudioMixEngine`, not even `PlaybackSandboxView`'s own hand-built
/// `AVPlayerLayer` wrapper or scrub slider — this is `AVPlayer` handed
/// straight to `AVPlayerViewController` and nothing else.
///
/// Purpose: a ceiling check. If scrub/play already feels less than perfectly
/// smooth *here*, on this phone, with this video file, through Apple's own
/// unmodified player — then that roughness is coming from the device/
/// simulator/codec itself, not from anything in this app's own pipeline,
/// and no amount of further work on `VideoFrameServer`/`EditorPlaybackEngine`
/// will fix it. If this feels perfectly smooth, the gap is confirmed to be
/// in this app's own code, not a hardware/OS limit.
struct RawVideoPlayerView: View {
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
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 12) {
            Picker("Clip", selection: $clip) {
                ForEach(SampleClip.allCases) { clip in
                    Text(clip.label).tag(clip)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: clip) { _, newValue in load(newValue) }

            if let player {
                SystemVideoPlayerView(player: player)
                    .frame(maxHeight: 500)
            } else {
                Color.black.frame(maxHeight: 500)
            }

            Text("System AVPlayerViewController only — zero lines of this app's own playback code run on this screen. Scrub the system scrubber and compare the feel against the Playback Sandbox tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .navigationTitle("Video Raw")
        .onAppear {
            guard player == nil else { return }
            load(clip)
        }
    }

    private func load(_ clip: SampleClip) {
        guard let url = bundledURL(filename: clip.rawValue) else { return }
        player = AVPlayer(url: url)
    }
}

/// Thinnest possible bridge to `AVPlayerViewController` — no option touched
/// beyond handing it a player, so every control (scrub bar, play/pause,
/// AirPlay) is exactly what the system draws for any ordinary video.
private struct SystemVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

#Preview {
    NavigationStack { RawVideoPlayerView() }
}
