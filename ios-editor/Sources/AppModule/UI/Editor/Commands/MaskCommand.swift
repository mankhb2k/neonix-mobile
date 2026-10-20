import CoreGraphics
import Foundation

extension V2Project {
    func withMasks(_ masks: [V2Mask]?) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }
}

/// The bookkeeping both mask tools (shapes and Remove BG) share. A layer names one mask (`layer.mask`); a tool's mask has an id `<prefix><layerId>~<kind>`, so the
/// kind can be read back after a reload. Replacing a layer's mask (with the other tool's, or none) drops the old one, a split half / copy that still names it first
/// gets a copy of its own, and masks no layer names any more are pruned.
enum MaskBook {
    static let prefixes = ["mask-", "removebg-"]

    /// `id` as (prefix, kind) when a tool wrote it.
    static func parse(_ id: String) -> (prefix: String, kind: String)? {
        guard let prefix = prefixes.first(where: { id.hasPrefix($0) }), let tilde = id.lastIndex(of: "~") else { return nil }
        return (prefix, String(id[id.index(after: tilde)...]))
    }

    /// `makeMask` gets the layer's own box and returns the new mask (nil = no mask). No-op for a layer that is not a picture or video.
    static func replace(in project: V2Project, layerId: String, with makeMask: (CGSize) -> V2Mask?) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }), layers[index].type == "video" || layers[index].type == "image" else { return project }
        let frame = CGSize(width: layers[index].frame.width, height: layers[index].frame.height)
        var masks = project.masks ?? []

        if let old = layers[index].mask, let (prefix, kind) = parse(old), let oldMask = masks.first(where: { $0.id == old }) {
            for other in layers.indices where other != index && layers[other].mask == old {
                var copy = oldMask
                copy.id = "\(prefix)\(layers[other].id)~\(kind)"
                masks.removeAll { $0.id == copy.id }
                masks.append(copy)
                layers[other].mask = copy.id
            }
        }

        var newId: String?
        if let mask = makeMask(frame) {
            masks.removeAll { $0.id == mask.id }
            masks.append(mask)
            newId = mask.id
        }
        layers[index].mask = newId
        let named = Set(layers.compactMap(\.mask))
        masks.removeAll { parse($0.id) != nil && !named.contains($0.id) }
        return project.withLayers(layers).withMasks(masks.isEmpty ? nil : masks)
    }
}

/// Mask tool (user 2026-10-18): gives a picture or video clip - overlays too, they are the same kinds - the mask in `draft`, or none (`.none`). The mask is a
/// `V2Mask` in `project.masks` that the layer names in `layer.mask`; its id carries the shape (`mask-<layer>~<shape>`, like an animation wrapper's id carries its
/// pick), so `MaskDraft(layer:masks:)` can read the intent back after a reload. See `MaskBook` for what replacing a mask does. No-op (fail closed) for any other layer.
struct SetLayerMaskCommand: EditorCommand {
    let layerId: String
    let draft: MaskDraft

    static func maskId(layerId: String, shape: MaskShape) -> String { "mask-\(layerId)~\(shape.rawValue)" }

    /// The shape a mask of this tool's id names.
    static func shape(ofMaskId id: String) -> MaskShape? {
        guard let (prefix, kind) = MaskBook.parse(id), prefix == "mask-" else { return nil }
        return MaskShape(rawValue: kind)
    }

    func apply(to project: V2Project) -> V2Project {
        MaskBook.replace(in: project, layerId: layerId) { frame in
            draft.v2Mask(id: Self.maskId(layerId: layerId, shape: draft.shape), frame: frame)
        }
    }
}
