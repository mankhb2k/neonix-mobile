import CoreGraphics
import Foundation

/// How Remove BG picks the subject: the platform's own choice (`auto`) or the subject the person tapped (`point`).
enum RemoveBackgroundMode: String, CaseIterable, Identifiable {
    case none, auto, point
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .auto: return "Auto removal"
        case .point: return "Choose subject"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "nosign"
        case .auto: return "person.crop.rectangle"
        case .point: return "hand.tap"
        }
    }
}

/// Remove BG as the editor works with it: the mode, the tapped point (fractions of the picture, top-left origin) and the two common mask options. Stored as a
/// segmentation `V2Mask` (`v2Mask`), read back by `init(layer:masks:)` - the mode is told by the mask's id (`removebg-<layer>~<mode>`).
struct RemoveBackgroundDraft: Equatable {
    var mode: RemoveBackgroundMode = .none
    var at = CGPoint(x: 0.5, y: 0.5)
    /// 0...1, like the Mask tool's (1 = a blur of a tenth of the shorter side).
    var feather = 0.0
    var invert = false

    var isChanged: Bool { self != RemoveBackgroundDraft() }

    static func maskId(layerId: String, mode: RemoveBackgroundMode) -> String { "removebg-\(layerId)~\(mode.rawValue)" }

    func v2Mask(id: String, frame: CGSize) -> V2Mask? {
        guard mode != .none, frame.width > 0, frame.height > 0 else { return nil }
        let short = Double(min(frame.width, frame.height))
        let segmentation = V2MaskSegmentation(mode: mode == .point ? "point" : "auto", at: mode == .point ? V2Vec2(x: Double(at.x), y: Double(at.y)) : nil)
        return V2Mask(id: id, maskType: "alpha", feather: feather == 0 ? nil : feather * MaskDraft.maxFeather * short, invert: invert ? true : nil, segmentation: segmentation)
    }

    init() {}

    /// The draft of `layer`'s own segmentation mask (none when it has none).
    init(layer: V2Layer, masks: [V2Mask]) {
        let frame = CGSize(width: layer.frame.width, height: layer.frame.height)
        guard let id = layer.mask, let (prefix, kind) = MaskBook.parse(id), prefix == "removebg-", let mode = RemoveBackgroundMode(rawValue: kind),
              let mask = masks.first(where: { $0.id == id }), let segmentation = mask.segmentation, frame.width > 0, frame.height > 0
        else { self = RemoveBackgroundDraft(); return }
        let short = Double(min(frame.width, frame.height))
        var draft = RemoveBackgroundDraft()
        draft.mode = mode
        if let point = segmentation.at { draft.at = CGPoint(x: point.x, y: point.y) }
        draft.feather = (mask.feather ?? 0) / (MaskDraft.maxFeather * short)
        draft.invert = mask.invert ?? false
        self = draft
    }
}

/// Remove BG (photo): gives a picture clip the segmentation mask in `draft`, or none. Same bookkeeping as the Mask tool (`MaskBook`): a layer names one mask, so
/// this replaces a shape mask and the other way round.
struct SetLayerSegmentationCommand: EditorCommand {
    let layerId: String
    let draft: RemoveBackgroundDraft

    func apply(to project: V2Project) -> V2Project {
        MaskBook.replace(in: project, layerId: layerId) { frame in
            draft.v2Mask(id: RemoveBackgroundDraft.maskId(layerId: layerId, mode: draft.mode), frame: frame)
        }
    }
}

/// Switching between segmentation Remove BG and chroma key is one mutually exclusive edit and one undo step.
struct SetRemoveBackgroundOptionCommand: EditorCommand {
    let layerId: String
    let draft: RemoveBackgroundDraft

    func apply(to project: V2Project) -> V2Project {
        let withoutChromaKey = SetChromaKeyCommand(layerId: layerId, draft: ChromaKeyDraft()).apply(to: project)
        return SetLayerSegmentationCommand(layerId: layerId, draft: draft).apply(to: withoutChromaKey)
    }
}
