import Foundation

/// The speaker button on the main lane (user 2026-10-18): turns the own sound of every video clip of the main lane off or on (`payload.audio.enabled`,
/// the volume set with Volume is kept). Overlays, stickers and standalone audio are not touched. Undoable like any edit.
struct SetMainLaneSoundCommand: EditorCommand {
    let muted: Bool

    /// The video clips the button speaks for: the main lane's own (not overlays).
    static func mainLaneVideoIds(in project: V2Project) -> [String] {
        guard let main = primaryVideoLaneOrder(of: project.layers) else { return [] }
        return project.layers.filter { $0.order == main && $0.type == "video" && !$0.id.hasPrefix(overlayLayerIdPrefix) }.map(\.id)
    }

    /// True when the main lane has video clips and every one of them has its sound off.
    static func isMuted(_ layers: [V2Layer]) -> Bool {
        guard let main = primaryVideoLaneOrder(of: layers) else { return false }
        let clips = layers.filter { $0.order == main && $0.type == "video" && !$0.id.hasPrefix(overlayLayerIdPrefix) }
        guard !clips.isEmpty else { return false }
        return clips.allSatisfy { layer in
            if case .video(let payload) = layer.payload { return payload.audio?.enabled == false }
            return false
        }
    }

    func apply(to project: V2Project) -> V2Project {
        let ids = Set(Self.mainLaneVideoIds(in: project))
        guard !ids.isEmpty else { return project }
        var layers = project.layers
        for index in layers.indices where ids.contains(layers[index].id) {
            guard case .video(var payload) = layers[index].payload else { continue }
            var audio = payload.audio ?? V2EmbeddedVideoAudio(enabled: true, gainDb: nil, pan: nil, fadeIn: nil, fadeOut: nil)
            audio.enabled = !muted
            payload.audio = audio
            layers[index].payload = .video(payload)
        }
        return project.withLayers(layers)
    }
}
