import Foundation

/// Volume of a video clip's own sound (user 2026-10-18): writes `payload.audio.gainDb` (absent = 0 dB, as recorded; the popup's scale is `VolumeScale`).
/// The sound stays on (`enabled` is kept, or true when the clip had no `audio` yet). No fades for video. No-op (fail closed) for any other layer.
struct SetVideoClipVolumeCommand: EditorCommand {
    let layerId: String
    let gainDb: Double

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }), case .video(var payload) = layers[index].payload else { return project }
        var audio = payload.audio ?? V2EmbeddedVideoAudio(enabled: true, gainDb: nil, pan: nil, fadeIn: nil, fadeOut: nil)
        audio.gainDb = gainDb == 0 ? nil : gainDb
        payload.audio = audio
        layers[index].payload = .video(payload)
        return project.withLayers(layers)
    }
}
