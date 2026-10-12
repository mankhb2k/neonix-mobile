import Foundation

/// What the Edit row offers for a selected clip. The order each kind shows is written out in `tools(for:hasAudio:)`
/// (user list 2026-10-12): most-used first - Split, Volume, Speed, Animation, then the look tools, then the structural
/// ones, then the rare ones. Delete is not in the scrolling row: it is pinned at the trailing edge so it is always reachable.
enum ClipTool: String, CaseIterable, Identifiable {
    case editText = "edit-text"
    case split, volume, speed, animation
    case adjust, filter, transform, opacity, crop
    case replace, duplicate, overlay
    case removeBackground = "remove-bg"
    case unlink
    case style
    case lastingText = "lasting-text"
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editText: return "Edit text"
        case .removeBackground: return "Remove BG"
        case .lastingText: return "Lasting text"
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
        case .lastingText: return "arrow.right.to.line"
        case .delete: return "trash"
        }
    }

    /// Whether the tool does something yet. The others are only buttons for now: tapping one says it is coming.
    func isBuilt(for kind: ClipKind) -> Bool {
        switch self {
        case .split, .transform, .adjust, .delete, .editText, .opacity: return true
        case .volume: return kind == .audio
        default: return false
        }
    }

    /// The scrolling row for a selection, in display order. `hasAudio` = the video actually has a sound track.
    static func tools(for kind: ClipKind, hasAudio: Bool) -> [ClipTool] {
        switch kind {
        case .video:
            return (hasAudio ? [.split, .volume] : [.split])
                + [.speed, .animation, .adjust, .filter, .transform, .opacity, .crop, .replace, .duplicate, .overlay, .removeBackground]
                + (hasAudio ? [.unlink] : [])
        case .image:
            return [.split, .animation, .adjust, .filter, .transform, .opacity, .crop, .replace, .duplicate, .overlay, .removeBackground]
        case .text:
            // Edit text stays first: it is the only way to change the words of a text clip.
            return [.editText, .split, .style, .animation, .duplicate, .lastingText, .transform]
        case .audio:
            return [.split, .volume, .speed, .duplicate]
        case .other:
            return [.split, .transform, .opacity, .duplicate]
        }
    }
}

/// What kind of thing is selected.
enum ClipKind {
    case video, image, text, audio, other

    init(layerType: String) {
        switch layerType {
        case "video": self = .video
        case "image": self = .image
        case "text": self = .text
        default: self = .other
        }
    }
}
