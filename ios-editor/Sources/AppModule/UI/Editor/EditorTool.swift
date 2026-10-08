import SwiftUI

/// The 8 bottom-toolbar tools kept from the CapCut nav scope audit (see
/// CLAUDE.md / the conversation this was scoped in): "Chú thích" (AI
/// auto-caption), "Lớp phủ", and "Nhãn dán" are still explicitly deferred —
/// they need either an AI backend or a content library this app doesn't
/// have yet. "Tuỳ chỉnh" (manual brightness/contrast/saturation/hue) stays
/// alongside "Bộ lọc" rather than standing in for it — they're genuinely
/// different tools in real CapCut (one is a LUT color-grade preset picker,
/// the other is manual sliders), not two names for the same feature.
///
/// **`filter` ("Bộ lọc") was added 2026-10-08, UI-only** — the
/// `feColorLUT`/`V2LutAsset` Protocol V2 primitives it will eventually
/// drive already exist (`Protocol/V2Filter.swift`/`V2Types.swift`, see
/// CLAUDE.md), but nothing wires this tool to them yet: no LUT picker
/// screen, no bundled `.cube` presets, no import flow. Tapping it only
/// highlights it, identical to every other tool here — see
/// `EditorToolbarView.swift`'s own doc comment.
///
/// Case order matches CapCut's own bottom nav order for the tools this app
/// kept (confirmed with the user 2026-10-07 when the nav was redesigned).
enum EditorTool: String, CaseIterable, Identifiable {
    case edit, audio, text, effects, filter, aspectRatio, background, adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return "Chỉnh sửa"
        case .audio: return "Âm thanh"
        case .text: return "Văn bản"
        case .effects: return "Hiệu ứng"
        case .filter: return "Bộ lọc"
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
        case .filter: return "camera.filters"
        case .aspectRatio: return "aspectratio"
        case .background: return "photo.on.rectangle"
        case .adjust: return "slider.horizontal.3"
        }
    }
}
