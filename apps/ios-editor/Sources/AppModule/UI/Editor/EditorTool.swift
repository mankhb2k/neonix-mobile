import SwiftUI

/// The 7 bottom-toolbar tools kept from the CapCut nav scope audit (see
/// CLAUDE.md / the conversation this was scoped in): "Bộ lọc" (LUT presets),
/// "Chú thích" (AI auto-caption), "Lớp phủ", and "Nhãn dán" were explicitly
/// deferred — the first needs a new Protocol V2 primitive, the rest need
/// either an AI backend or a content library this app doesn't have yet.
/// "Tuỳ chỉnh" (manual brightness/contrast/saturation/hue) is kept in place
/// of "Bộ lọc" since it's atomic today (`feColorMatrix`/`feComponentTransfer`,
/// no LUT needed).
enum EditorTool: String, CaseIterable, Identifiable {
    case edit, text, adjust, effects, audio, aspectRatio, background

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return "Chỉnh sửa"
        case .text: return "Văn bản"
        case .adjust: return "Tuỳ chỉnh"
        case .effects: return "Hiệu ứng"
        case .audio: return "Âm thanh"
        case .aspectRatio: return "Tỷ lệ khung hình"
        case .background: return "Phông nền"
        }
    }

    var systemImage: String {
        switch self {
        case .edit: return "scissors"
        case .text: return "textformat"
        case .adjust: return "slider.horizontal.3"
        case .effects: return "wand.and.stars"
        case .audio: return "music.note"
        case .aspectRatio: return "aspectratio"
        case .background: return "photo.on.rectangle"
        }
    }
}
