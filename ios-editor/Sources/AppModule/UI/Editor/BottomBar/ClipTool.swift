import Foundation

/// What the Edit row offers for a selected clip. The order each kind shows is written out in `tools(for:)`
/// (user list 2026-10-12): most-used first - Split, Volume, Speed, Animation, then the look tools, then the structural
/// ones, then the rare ones. Delete is the 4th button of every row, styled like the others.
enum ClipTool: String, CaseIterable, Identifiable {
    case editText = "edit-text"
    case split, volume, speed, animation
    case adjust, filter, transform, opacity, crop
    case replace, duplicate, overlay
    case removeBackground = "remove-bg"
    case unlink
    case style
    case mirror
    case graph
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editText: return "Edit text"
        case .removeBackground: return "Remove BG"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var symbol: String {
        switch self {
        case .editText: return "pencil"
        case .split: return "scissors"
        case .volume: return "speaker.wave.2"
        case .speed: return "speedometer"
        case .animation: return "play.rectangle"
        case .adjust: return "slider.horizontal.3"
        case .filter: return "camera.filters"
        case .transform: return "crop.rotate"
        case .opacity: return "circle.lefthalf.striped.horizontal"
        case .crop: return "crop"
        case .replace: return "arrow.triangle.2.circlepath"
        case .duplicate: return "plus.square.on.square"
        case .overlay: return "square.2.layers.3d"
        case .removeBackground: return "person.crop.rectangle"
        case .unlink: return "link"
        case .style: return "textformat.size"
        case .graph: return "chart.xyaxis.line"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .delete: return "trash"
        }
    }

    /// Whether the tool does something yet. The others are only buttons for now: tapping one says it is coming.
    func isBuilt(for kind: ClipKind) -> Bool {
        switch self {
        case .split, .transform, .adjust, .filter, .delete, .editText, .opacity, .mirror, .graph: return true
        case .animation: return kind != .audio
        case .speed: return kind == .video
        case .duplicate: return kind == .video || kind == .image || kind == .text || kind == .sticker
        case .replace, .overlay: return kind == .video || kind == .image
        case .style: return kind == .text
        case .volume: return kind == .audio
        default: return false
        }
    }

    static let deletePosition = 3

    /// The scrolling row for a selection, in display order. 
    static func tools(for kind: ClipKind) -> [ClipTool] {
        // Delete is a normal tool that always sits 4th in the row (user 2026-10-13), so it is reachable without scrolling.
        var row = rowWithoutDelete(for: kind)
        row.insert(.delete, at: min(deletePosition, row.count))
        return row
    }

    private static func rowWithoutDelete(for kind: ClipKind) -> [ClipTool] {
        // User list 2026-10-13: Split, Transform, Volume, Delete (inserted 4th), Animation, Graph, Speed, then the rest.
        // Volume / Unlink are always listed for a video; `SelectionToolbarView` dims them when the file has no sound.
        switch kind {
        case .video:
            return [.split, .transform, .volume, .animation, .graph, .speed, .adjust, .filter, .opacity, .crop, .replace, .duplicate, .overlay, .removeBackground, .unlink]
        case .image:
            return [.split, .transform, .animation, .graph, .adjust, .filter, .opacity, .crop, .replace, .duplicate, .overlay, .removeBackground]
        case .text:
            // Edit text stays first: it is the only way to change the words of a text clip.
            return [.editText, .split, .transform, .style, .animation, .graph, .duplicate]
        case .sticker:
            return [.split, .transform, .animation, .graph, .duplicate, .mirror]
        case .audio:
            return [.split, .volume, .speed, .duplicate]
        case .other:
            return [.split, .transform, .graph, .opacity, .duplicate]
        }
    }
}

/// What kind of thing is selected.
enum ClipKind {
    case video, image, text, sticker, audio, other

    /// A sticker is an image layer in Protocol V2 (atomic) but its own kind in the editor, told by its `sticker-` id.
    init(layer: V2Layer) {
        self = layer.id.hasPrefix(stickerLayerIdPrefix) ? .sticker : ClipKind(layerType: layer.type)
    }

    init(layerType: String) {
        switch layerType {
        case "video": self = .video
        case "image": self = .image
        case "text": self = .text
        default: self = .other
        }
    }
}
