import Foundation

/// The user's media for one media slot, already imported into the app's media folder.
struct SlotFill {
    let slotId: String
    let kind: MediaKind
    let asset: V2Asset
    /// Where the crop window starts in a video, ms. 0 for photos.
    let trimStartMs: Double
}

struct FilledTemplate {
    let document: EditorDocument
    /// layer id -> `trimStart` (ms) for video layers.
    let trims: [String: Double]
}

enum TemplateFillError: LocalizedError {
    case missing(String)
    case unknownSlot(String)

    var errorDescription: String? {
        switch self {
        case .missing(let id): return "Slot \(id) needs a photo or video"
        case .unknownSlot(let id): return "Unknown slot \(id)"
        }
    }
}

/// Swaps the user's media into a template's media slots. Everything else in the document (timing, presets,
/// effects, text, music) is left exactly as the creator made it.
enum TemplateFiller {
    /// `texts`: text slot id -> the text the user typed (slots not in it keep the creator's text).
    static func fill(_ package: TemplatePackage, with fills: [SlotFill], texts: [String: String] = [:]) throws -> FilledTemplate {
        var document = package.document
        var trims: [String: Double] = [:]
        let mediaSlots = package.manifest.slots.filter { $0.kind == "media" }
        for fill in fills where !mediaSlots.contains(where: { $0.id == fill.slotId }) { throw TemplateFillError.unknownSlot(fill.slotId) }
        let fillBySlot = Dictionary(fills.map { ($0.slotId, $0) }, uniquingKeysWith: { _, last in last })

        var removed = Set<String>()
        for slot in mediaSlots {
            guard let index = document.layers.firstIndex(where: { $0.id == slot.layerId }) else { throw TemplateFillError.unknownSlot(slot.id) }
            if let fill = fillBySlot[slot.id] {
                document.layers[index].kind = fill.kind == .photo ? "image" : "video"
                document.layers[index].assetId = fill.asset.id
                if !document.assets.contains(where: { $0.id == fill.asset.id }) { document.assets.append(fill.asset) }
                if fill.kind == .video { trims[slot.layerId] = fill.trimStartMs }
            } else if slot.required {
                throw TemplateFillError.missing(slot.id)
            } else {
                removed.insert(slot.layerId)   // an optional slot left empty: drop the layer rather than show the sample media
            }
        }
        document.layers.removeAll { removed.contains($0.id) }

        for slot in package.manifest.slots where slot.kind == "text" {
            guard let text = texts[slot.id], let index = document.layers.firstIndex(where: { $0.id == slot.layerId }),
                  var intent = document.layers[index].text else { continue }
            intent.text = text
            document.layers[index].text = intent
        }

        // The creator's placeholder media (sample photo/video) goes away once nothing points at it.
        let used = Set(document.layers.compactMap(\.assetId))
        document.assets.removeAll { ($0.kind == "image" || $0.kind == "video") && !used.contains($0.id) }
        return FilledTemplate(document: document, trims: trims)
    }
}
