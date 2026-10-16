import CoreGraphics
import Foundation

/// Where a moved free clip lands: an existing lane, or a new lane inserted at `order` (every lane from there down shifts by one).
enum ClipMoveTarget: Equatable {
    case lane(Int)
    case newLane(at: Int)
}

/// Rules for moving one free clip (text, sticker, overlay) by long-press-and-drag; see CLAUDE.md "Timeline lanes".
enum ClipMove {
    /// Lanes are homogeneous: text with text, stickers with stickers, overlays (video or photo) with overlays.
    static func laneKind(of layer: V2Layer) -> String {
        if layer.id.hasPrefix(stickerLayerIdPrefix) { return "sticker" }
        if layer.id.hasPrefix(overlayLayerIdPrefix) { return "overlay" }
        return layer.type
    }

    /// Free clips only: the main lane's clips reorder instead, and animation wrappers (`group`) follow their clip.
    static func isMovable(_ layer: V2Layer) -> Bool {
        layer.type != "group" && !isPushLane(layer)
    }

    /// True when `moving` can sit in lane `order` from `start`: the lane holds clips of its own kind only and none overlaps it.
    static func fits(_ layers: [V2Layer], moving: V2Layer, order: Int, start: Double) -> Bool {
        let others = layers.filter { $0.order == order && $0.id != moving.id && $0.type != "group" }
        guard others.allSatisfy({ laneKind(of: $0) == laneKind(of: moving) }) else { return false }
        let end = start + moving.timing.duration
        return !others.contains { start < $0.timing.start + $0.timing.duration && $0.timing.start < end }
    }

    /// The lane the clip's centre (`y`, same space as the bands) points at. A lane that fits wins; over a lane that does not
    /// (other kind, or occupied at that time) or between lanes it is a new lane, inserted before the first lane whose middle
    /// is below `y`. Never at or above the main lane.
    static func resolve(layers: [V2Layer], moving: V2Layer, start: Double, bands: [(order: Int, minY: CGFloat, maxY: CGFloat)], y: CGFloat) -> ClipMoveTarget {
        let sorted = bands.sorted { $0.minY < $1.minY }
        if let hit = sorted.first(where: { y >= $0.minY && y <= $0.maxY }), fits(layers, moving: moving, order: hit.order, start: start) {
            return .lane(hit.order)
        }
        var at = sorted.first(where: { y < ($0.minY + $0.maxY) / 2 })?.order ?? ((sorted.map(\.order).max() ?? -1) + 1)
        if let main = primaryVideoLaneOrder(of: layers) { at = max(at, main + 1) }
        return .newLane(at: at)
    }
}

/// Moves one free clip to `start` (ms, not below 0) in `target`. Valid by construction: a clip that cannot move there (not a free
/// clip, a lane of another kind, an overlap, a new lane at or above the main lane) leaves the project unchanged. Keyframes are
/// clip-local and animation wrappers follow the clip (`AnimationWrappers.normalized`), so nothing else changes.
struct MoveClipCommand: EditorCommand {
    let layerId: String
    let start: Double
    let target: ClipMoveTarget

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }), ClipMove.isMovable(layers[index]) else { return project }
        let moving = layers[index]
        let start = max(start, 0)
        switch target {
        case .lane(let order):
            guard ClipMove.fits(layers, moving: moving, order: order, start: start) else { return project }
            layers[index].order = order
        case .newLane(let at):
            if let main = primaryVideoLaneOrder(of: layers), at <= main { return project }
            for i in layers.indices where i != index && layers[i].order >= at { layers[i].order += 1 }
            layers[index].order = at
        }
        layers[index].timing = V2Timing(start: start, duration: moving.timing.duration)
        return project.withLayers(layers)
    }
}
