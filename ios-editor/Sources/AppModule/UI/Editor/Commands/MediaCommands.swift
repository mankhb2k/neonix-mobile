import Foundation

/// Layer ids of overlays (a video or photo placed above the clip, picture-in-picture) start with this; like stickers they are free overlays
/// (gaps allowed, trimming never pushes a neighbour).
let overlayLayerIdPrefix = "overlay-"

/// The asset's own size and (video) length, or nil for anything that is not a picture or a video.
private func mediaFacts(_ asset: V2Asset) -> (width: Double, height: Double, durationMs: Double?)? {
    switch asset {
    case .image(let image): return (image.width, image.height, nil)
    case .video(let video): return (video.width, video.height, video.duration)
    default: return nil
    }
}

/// Overlay (user 2026-10-16): copies the selected video or photo clip into an **overlay layer** - the same footage and speed, at the same place on
/// the timeline, half the canvas wide in the middle, on top of everything - so it can be moved and sized as a picture-in-picture. The original stays
/// where it is; the copy starts clean (no keyframes, no animations, transform reset) and keeps the clip's look (opacity, filter). It goes in a lane of
/// overlays that is free for that stretch of time, else a new lane above everything (never the main lane). No-op (fail closed) for anything but a
/// video or photo clip.
struct CopyToOverlayCommand: EditorCommand {
    let layerId: String
    let newLayerId: String
    /// How big the copy starts, as a fraction of the original.
    static let scale = 0.5

    func apply(to project: V2Project) -> V2Project {
        guard let original = project.layers.first(where: { $0.id == layerId }), original.type == "video" || original.type == "image" else { return project }
        var layer = original
        layer.id = newLayerId
        layer.parentLayerId = nil
        layer.tracks = nil
        layer.transform = V2Transform(
            translate: V2Vec3(x: 0, y: 0, z: 0), scale: V2Vec3(x: Self.scale, y: Self.scale, z: 1), rotate: V2Vec3(x: 0, y: 0, z: 0),
            skew: V2Vec2(x: 0, y: 0), anchor: V2Vec3(x: 0, y: 0, z: 0), perspective: nil
        )
        let overlays = project.layers.filter { $0.id.hasPrefix(overlayLayerIdPrefix) && $0.type != "group" }
        func overlaps(_ order: Int) -> Bool {
            overlays.contains { other in
                other.order == order && layer.timing.start < other.timing.start + other.timing.duration
                    && other.timing.start < layer.timing.start + layer.timing.duration
            }
        }
        layer.order = Set(overlays.map(\.order)).sorted().first(where: { !overlaps($0) }) ?? ((project.layers.map(\.order).max() ?? -1) + 1)
        return project.withLayers(project.layers + [layer])
    }
}

/// Replace: swaps the picture or footage of a video or photo clip for another one and keeps everything else - its place and length on the timeline,
/// transform, keyframes, filter, animations. A video stays at its speed (rate or curve); a video turned into a photo (or the other way round)
/// loses what only the other kind has (speed, trim). The new footage starts from its beginning. No-op (fail closed) for any other layer or asset.
struct ReplaceClipCommand: EditorCommand {
    let layerId: String
    let asset: V2Asset

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }), mediaFacts(asset) != nil else { return project }
        var layer = layers[index]
        switch (layer.payload, asset) {
        case (.video(var old), .video(let video)):
            old.assetId = video.id
            old.trimStart = 0; old.trimEnd = nil
            layer.payload = .video(old)
        case (.image(var old), .image(let image)):
            old.assetId = image.id
            layer.payload = .image(old)
        case (.video(let old), .image(let image)):
            layer.payload = .image(V2ImagePayload(assetId: image.id, fit: old.fit))
        case (.image(let old), .video(let video)):
            layer.payload = .video(V2VideoPayload(assetId: video.id, fit: old.fit, trimStart: 0))
        default: return project
        }
        layers[index] = layer
        let assets = project.assets.contains { $0.id == asset.id } ? project.assets : project.assets + [asset]
        return project.withAssets(assets).withLayers(layers)
    }
}

/// Duplicate (video, photo, text, sticker): a copy that starts where the original ends, with the same look, keyframes, speed and animations. A
/// clip of a push lane (video, photo) goes right after the original in the same lane and the clips after it move later by its length, so the lane
/// keeps having no gap; a free overlay (text, sticker, overlay) goes to the same lane when it is free there, else to a new one
/// (`DuplicateOverlayCommand`). No-op (fail closed) for an unknown layer.
struct DuplicateClipCommand: EditorCommand {
    let layerId: String
    let newLayerId: String

    func apply(to project: V2Project) -> V2Project {
        guard let original = project.layers.first(where: { $0.id == layerId }), original.type != "group" else { return project }
        var result: V2Project
        if isPushLane(original) {
            var layers = project.layers
            guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
            let end = original.timing.start + original.timing.duration
            var copy = original
            copy.id = newLayerId
            copy.timing = V2Timing(start: end, duration: original.timing.duration)
            copy.parentLayerId = AnimationWrappers.baseParent(of: original, in: layers)
            // The lane makes room: everything that started at or after the original's end moves later by the copy's length.
            layers = layers.map { layer in
                guard layer.order == original.order, layer.type != "group", layer.id != original.id, layer.timing.start >= end - 0.5 else { return layer }
                var moved = layer
                moved.timing = V2Timing(start: layer.timing.start + copy.timing.duration, duration: layer.timing.duration)
                return moved
            }
            let animations = AnimationWrappers.applied(for: layerId, in: layers)
            let at = layers.firstIndex(where: { $0.id == layerId }) ?? index
            layers.insert(copy, at: at + 1)
            result = project.withLayers(layers)
            if !animations.isEmpty { result = AnimationWrappers.rebuilt(result, clipId: newLayerId, animations: Array(animations.values)) }
        } else {
            result = DuplicateOverlayCommand(layerId: layerId, newLayerId: newLayerId).apply(to: project)
        }
        // A text clip keeps what V2 only remembers as geometry (label padding, curve): the copy gets the original's entry.
        if original.textPayload != nil, let values = TextIntentCache.shared.values(for: original),
           let copy = result.layers.first(where: { $0.id == newLayerId }) { TextIntentCache.shared.remember(values, for: copy) }
        return result
    }
}
