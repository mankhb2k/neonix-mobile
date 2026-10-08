import AVFoundation
import SwiftUI

/// A bare `AVPlayerLayer` host, no native playback controls overlay — this
/// app owns its own Play/Pause/scrub UI. Used both while actually playing a
/// video and, since 2026-10-08, by `ScrubPlayerView` for the
/// paused/scrubbing preview too (a tolerant-seeked `AVPlayer`, not a
/// `VideoFrameCache`-extracted still image — see that type's doc comment
/// for why).
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
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
