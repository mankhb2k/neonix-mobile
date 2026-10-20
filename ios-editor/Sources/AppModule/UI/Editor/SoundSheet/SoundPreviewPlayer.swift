import AVFoundation
import Foundation
import Observation

/// Plays one sound at a time for the Sound FX list (not the project's audio engine). A tap on a sound that is not downloaded
/// downloads it first (`loadingId`), then plays; the sound ends by itself, `start` lets rows draw the progress.
@MainActor
@Observable
final class SoundPreviewPlayer {
    private(set) var playingId: String?
    private(set) var loadingId: String?
    private(set) var start: Date?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var task: Task<Void, Never>?

    func toggle(_ sound: APISoundCatalogue.Sound, store: SoundStore) {
        if playingId == sound.id || loadingId == sound.id { stop(); return }
        stop()
        loadingId = sound.id
        task = Task {
            let url = await store.localURL(for: sound)
            guard !Task.isCancelled, loadingId == sound.id else { return }
            loadingId = nil
            guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            self.player = player
            player.play()
            playingId = sound.id
            start = Date()
            try? await Task.sleep(for: .seconds(player.duration))
            if !Task.isCancelled, playingId == sound.id { stop() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        playingId = nil
        loadingId = nil
        start = nil
    }
}
