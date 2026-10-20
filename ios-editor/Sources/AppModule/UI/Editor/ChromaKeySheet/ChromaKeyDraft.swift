import Foundation

/// Editor-tier controls for the atomic Protocol V2 `feChromaKey` primitive.
struct ChromaKeyDraft: Equatable {
    var enabled = false
    var keyColor = "#0ABF47"
    var similarity = 0.30
    var smoothness = 0.25
    var shadow = 0.0
    var edgeCleanup = 0.0

    init() {}

    init(layer: V2Layer, filters: [V2Filter]) {
        guard let filterId = layer.filter, let filter = filters.first(where: { $0.id == filterId }),
              case .feChromaKey(_, let color, let similarity, let smoothness, let shadow, let edgeCleanup)? = filter.primitives.last(where: {
                  if case .feChromaKey = $0 { return true }
                  return false
              })
        else { return }
        enabled = true
        keyColor = color
        self.similarity = similarity
        self.smoothness = smoothness
        self.shadow = shadow
        self.edgeCleanup = edgeCleanup
    }

    var primitive: V2FilterPrimitive? {
        guard enabled else { return nil }
        let base = V2FilterPrimitiveBase(id: "chroma-key", in: "SourceGraphic", result: nil, region: nil, colorInterpolationFilters: nil)
        return .feChromaKey(base, keyColor: keyColor, similarity: similarity, smoothness: smoothness,
                            shadow: shadow, edgeCleanup: edgeCleanup)
    }
}

struct SetChromaKeyCommand: EditorCommand {
    let layerId: String
    let draft: ChromaKeyDraft

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerId }),
              layers[layerIndex].type == "video" || layers[layerIndex].type == "image" else { return project }

        var filters = project.filters ?? []
        let existingId = layers[layerIndex].filter
        if let existingId, let filterIndex = filters.firstIndex(where: { $0.id == existingId }) {
            var filter = filters[filterIndex]
            filter.primitives.removeAll { if case .feChromaKey = $0 { return true }; return false }
            if let primitive = draft.primitive {
                let previousResult = filter.primitives.last?.base.result ?? "SourceGraphic"
                filter.primitives.append(Self.settingInput(previousResult, on: primitive))
            }
            if filter.primitives.isEmpty {
                filters.remove(at: filterIndex)
                layers[layerIndex].filter = nil
            } else {
                filters[filterIndex] = filter
            }
        } else if let primitive = draft.primitive {
            let id = "chroma-\(layerId)"
            let filter = V2Filter(id: id, x: nil, y: nil, width: nil, height: nil, filterUnits: nil,
                                  primitiveUnits: nil, colorInterpolationFilters: nil, primitives: [primitive], tracks: nil)
            filters.removeAll { $0.id == id }
            filters.append(filter)
            layers[layerIndex].filter = id
        }
        let updated = project.withLayers(layers).withFilters(filters.isEmpty ? nil : filters)
        if draft.enabled, let maskId = layers[layerIndex].mask,
           let (prefix, _) = MaskBook.parse(maskId), prefix == "removebg-" {
            return MaskBook.replace(in: updated, layerId: layerId) { _ in nil }
        }
        return updated
    }

    private static func settingInput(_ input: String, on primitive: V2FilterPrimitive) -> V2FilterPrimitive {
        guard case .feChromaKey(let existingBase, let keyColor, let similarity, let smoothness, let shadow, let edgeCleanup) = primitive else { return primitive }
        var base = existingBase
        base.in = input
        return .feChromaKey(base, keyColor: keyColor, similarity: similarity, smoothness: smoothness,
                            shadow: shadow, edgeCleanup: edgeCleanup)
    }
}
