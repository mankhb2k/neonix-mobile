import SwiftUI

/// What the Transform tool edits on one layer, in composition units (like `V2Transform`): the offset from the canvas
/// centre, a uniform scale, the rotation in degrees (clockwise) and the opacity.
struct TransformValues: Equatable {
    var x = 0.0
    var y = 0.0
    var scale = 1.0
    var rotation = 0.0
    var opacity = 1.0

    init() {}

    init(layer: V2Layer) {
        x = layer.transform.translate.x
        y = layer.transform.translate.y
        scale = abs(layer.transform.scale.x)
        rotation = layer.transform.rotate.z
        opacity = layer.opacity ?? 1
    }

    /// The values at the playhead: a keyframed layer is sampled, any other is its static transform.
    init(layer: V2Layer, atMs: Double) {
        self.init(layer: layer)
        guard TransformKeyframes.isKeyframed(layer) else { return }
        let frame = sampleLayer(layer, atMs: atMs)
        x = frame.translateX
        y = frame.translateY
        scale = abs(frame.scaleX)
        rotation = frame.rotateZ
        opacity = frame.opacity
    }
}

/// Transform (vị trí/tỷ lệ/xoay): sets a layer's `transform` and `opacity`. Everything else on the transform (3D tilt,
/// skew, anchor, perspective, z) is kept as it is; scale is uniform, so a layer that had been stretched is evened out.
/// A no-op for an unknown layer (fails closed, like every command here).
struct SetTransformCommand: EditorCommand {
    let layerId: String
    let values: TransformValues
    /// The playhead (timeline ms). On a keyframed layer the values become a keyframe there (created if needed, like
    /// CapCut's auto-keyframe) instead of the static transform, which the tracks would override anyway.
    var atMs: Double? = nil

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        if let atMs, TransformKeyframes.isKeyframed(layers[index]) {
            let layer = layers[index]
            let local = min(max(atMs - layer.timing.start, 0), layer.timing.duration)
            let mirrored = sampleLayer(layer, atMs: atMs).scaleX < 0 ? -1.0 : 1.0
            layers[index] = TransformKeyframes.upserting(layer, local: local, overrides: [
                "transform.translate.x": values.x, "transform.translate.y": values.y,
                "transform.scale.x": values.scale * mirrored, "transform.scale.y": values.scale,
                "transform.rotate.z": values.rotation, "opacity": values.opacity,
            ])
            return project.withLayers(layers)
        }
        let old = layers[index].transform
        layers[index].transform = V2Transform(
            translate: V2Vec3(x: values.x, y: values.y, z: old.translate.z),
            scale: V2Vec3(x: values.scale * (old.scale.x < 0 ? -1 : 1), y: values.scale, z: old.scale.z),   // a mirrored layer stays mirrored
            rotate: V2Vec3(x: old.rotate.x, y: old.rotate.y, z: values.rotation),
            skew: old.skew, anchor: old.anchor, perspective: old.perspective
        )
        layers[index].opacity = values.opacity
        return project.withLayers(layers)
    }
}

/// The Transform tool's controls: one ruler each. Same buttons, ranges and readouts as the Design Lab's Transform lab.
enum TransformControl: String, CaseIterable, Identifiable {
    case x, y, scale, rotation, opacity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .x: return "Position X"
        case .y: return "Position Y"
        case .scale: return "Scale"
        case .rotation: return "Rotate"
        case .opacity: return "Opacity"
        }
    }

    var symbol: String {
        switch self {
        case .x: return "arrow.left.and.right"
        case .y: return "arrow.up.and.down"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .rotation: return "rotate.right"
        case .opacity: return "circle.lefthalf.filled"
        }
    }

    var keyPath: WritableKeyPath<TransformValues, Double> {
        switch self {
        case .x: return \.x
        case .y: return \.y
        case .scale: return \.scale
        case .rotation: return \.rotation
        case .opacity: return \.opacity
        }
    }

    var neutral: Double {
        switch self {
        case .x, .y, .rotation: return 0
        case .scale, .opacity: return 1
        }
    }

    /// Positions run across the composition (±its width/height), in steps that suit its size.
    func mapping(for composition: V2Composition) -> RulerMapping {
        func step(_ length: Double) -> Double { length >= 720 ? 10 : (length >= 300 ? 5 : 2) }
        switch self {
        case .x: return .linear(-composition.width...composition.width, step: step(composition.width), majorEvery: 10)
        case .y: return .linear(-composition.height...composition.height, step: step(composition.height), majorEvery: 10)
        case .scale: return .logarithmic(0.25...4, ticksPerDoubling: 12)
        case .rotation: return .linear(-180...180, step: 1, majorEvery: 15)
        case .opacity: return .linear(0...1, step: 0.01, majorEvery: 10)
        }
    }

    /// Values with a firmer haptic tick: centre, 100 %, upright and the quarter turns.
    var detents: [Double] {
        switch self {
        case .x, .y: return [0]
        case .scale, .opacity: return [1]
        case .rotation: return [-90, -45, 0, 45, 90]
        }
    }

    func display(_ value: Double) -> String {
        switch self {
        case .x, .y: return value == 0 ? "0" : String(format: "%+.0f", value)
        case .scale, .opacity: return String(format: "%.0f%%", value * 100)
        case .rotation: return String(format: "%.0f°", value == 0 ? 0 : value)
        }
    }
}

extension TransformValues {
    func isChanged(_ control: TransformControl) -> Bool { abs(self[keyPath: control.keyPath] - control.neutral) > 0.0001 }
}
