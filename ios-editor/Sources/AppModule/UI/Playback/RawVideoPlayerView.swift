import AVKit
import SwiftUI

/// The rawest possible playback baseline: Apple's own system video player
/// chrome (`AVPlayerViewController` — literally the same player UI Photos,
/// Safari and Messages use for an inline video), wired to nothing this app
/// wrote. No custom clock, no custom decoder path, no
/// `AudioMixEngine`, not even `PlaybackSandboxView`'s own hand-built
/// `AVPlayerLayer` wrapper or scrub slider — this is `AVPlayer` handed
/// straight to `AVPlayerViewController` and nothing else.
///
/// Purpose: a ceiling check. If scrub/play already feels less than perfectly
/// smooth *here*, on this phone, with this video file, through Apple's own
/// unmodified player — then that roughness is coming from the device/
/// simulator/codec itself, not from anything in this app's own pipeline,
/// and no amount of further work on `EditorPlaybackEngine`
/// will fix it. If this feels perfectly smooth, the gap is confirmed to be
/// in this app's own code, not a hardware/OS limit.
struct RawVideoPlayerView: View {
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 12) {
            if let player {
                SystemVideoPlayerView(player: player)
                    .frame(maxHeight: 500)
            } else {
                Color.black.frame(maxHeight: 500)
                    .overlay(Text(TestFootage.missingMessage).font(.caption).foregroundStyle(.red).padding())
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
            load()
        }
    }

    private func load() {
        guard let url = TestFootage.url else { return }
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
