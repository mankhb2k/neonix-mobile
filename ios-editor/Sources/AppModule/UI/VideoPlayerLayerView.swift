import AVFoundation
import SwiftUI

/// A bare `AVPlayerLayer` host, no native playback controls overlay — this
/// app owns its own Play/Pause/scrub UI. Shown on top of the cached still
/// (`VideoContentView`) while playing, and briefly after a pause.
///
/// Stays fully transparent until the layer reports `isReadyForDisplay`: a
/// fresh `AVPlayerLayer` draws black/nothing until its player has decoded a
/// frame, which used to flash on every Play. While hidden, whatever is
/// underneath (the cached still) shows through instead.
struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = gravity
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        private var readyObservation: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            observeReadiness()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            observeReadiness()
        }

        private func observeReadiness() {
            alpha = 0
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async { self?.alpha = ready ? 1 : 0 }
            }
        }
    }
}
