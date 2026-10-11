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
        scale = layer.transform.scale.x
        rotation = layer.transform.rotate.z
        opacity = layer.opacity ?? 1
    }
}

/// Transform (vị trí/tỷ lệ/xoay): sets a layer's `transform` and `opacity`. Everything else on the transform (3D tilt,
/// skew, anchor, perspective, z) is kept as it is; scale is uniform, so a layer that had been stretched is evened out.
/// A no-op for an unknown layer (fails closed, like every command here).
struct SetTransformCommand: EditorCommand {
    let layerId: String
    let values: TransformValues

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let old = layers[index].transform
        layers[index].transform = V2Transform(
            translate: V2Vec3(x: values.x, y: values.y, z: old.translate.z),
            scale: V2Vec3(x: values.scale, y: values.scale, z: old.scale.z),
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
