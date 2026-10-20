import Foundation

/// Crop tool (user 2026-10-18, layout B of the Crop lab): sets or clears the region of a picture or video clip that shows (`V2Crop`: region, straighten,
/// flip). A crop that changes nothing is stored as none. The layer's frame, timing, transform and keyframes are untouched - the region is shown inside the
/// frame by `CropLayout`. No-op (fail closed) for any other layer, or a region that is not inside the picture or is smaller than 2 % of it.
struct SetClipCropCommand: EditorCommand {
    let layerId: String
    let crop: V2Crop?

    static let minimumFraction = 0.02

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        var value: V2Crop?
        if let crop, !crop.isIdentity {
            let epsilon = 0.0005
            guard crop.width >= Self.minimumFraction, crop.height >= Self.minimumFraction,
                  crop.x >= -epsilon, crop.y >= -epsilon, crop.x + crop.width <= 1 + epsilon, crop.y + crop.height <= 1 + epsilon
            else { return project }
            value = crop
        }
        switch layers[index].payload {
        case .image(var payload):
            payload.crop = value
            layers[index].payload = .image(payload)
        case .video(var payload):
            payload.crop = value
            layers[index].payload = .video(payload)
        default:
            return project
        }
        return project.withLayers(layers)
    }
}
