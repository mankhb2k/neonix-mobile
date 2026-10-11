import AVFoundation
import SwiftUI

/// Muted-by-default looping video. `onReady` fires once the first frame is on screen, so the poster underneath
/// can stay until then.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var isMuted = true
    var onReady: () -> Void = {}

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var readyObservation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        let player = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        context.coordinator.player = player
        player.isMuted = isMuted
        view.playerLayer.player = player
        context.coordinator.readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { _, change in
            if change.newValue == true { DispatchQueue.main.async { onReady() } }
        }
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        context.coordinator.player?.isMuted = isMuted
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.readyObservation = nil
        coordinator.looper = nil
        view.playerLayer.player = nil
    }
}

func isVideoURL(_ url: URL?) -> Bool {
    guard let ext = url?.pathExtension.lowercased() else { return false }
    return ext == "mp4" || ext == "mov" || ext == "m4v"
}
