import SwiftUI

/// The 7 bottom-toolbar tools kept from the CapCut nav scope audit (see
/// CLAUDE.md / the conversation this was scoped in): "Bộ lọc" (LUT presets),
/// "Chú thích" (AI auto-caption), "Lớp phủ", and "Nhãn dán" were explicitly
/// deferred — the first needs a new Protocol V2 primitive, the rest need
/// either an AI backend or a content library this app doesn't have yet.
/// "Tuỳ chỉnh" (manual brightness/contrast/saturation/hue) is kept in place
/// of "Bộ lọc" since it's atomic today (`feColorMatrix`/`feComponentTransfer`,
/// no LUT needed).
///
/// Case order matches CapCut's own bottom nav order for the tools this app
/// kept (confirmed with the user 2026-10-07 when the nav was redesigned) —
/// `adjust` sits last since it's standing in for "Bộ lọc"'s slot, which in
/// CapCut's real nav comes later than the other 6 kept tools.
enum EditorTool: String, CaseIterable, Identifiable {
    case edit, audio, text, effects, aspectRatio, background, adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return "Chỉnh sửa"
        case .audio: return "Âm thanh"
        case .text: return "Văn bản"
        case .effects: return "Hiệu ứng"
        case .aspectRatio: return "Tỷ lệ khung hình"
        case .background: return "Phông nền"
        case .adjust: return "Tuỳ chỉnh"
        }
    }

    var systemImage: String {
        switch self {
        case .edit: return "scissors"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .effects: return "wand.and.stars"
        case .aspectRatio: return "aspectratio"
        case .background: return "photo.on.rectangle"
        case .adjust: return "slider.horizontal.3"
        }
    }
}
