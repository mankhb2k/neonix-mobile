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
/// **`filter` ("Bộ lọc") is still a UI-only placeholder** — the
/// `feColorLUT`/`V2LutAsset` primitives it will drive exist (see CLAUDE.md),
/// but there is no LUT picker, bundled `.cube` preset or import flow yet, so
/// tapping it only highlights it.
///
/// Case order matches CapCut's own bottom nav order for the tools this app
/// kept (confirmed with the user 2026-10-07 when the nav was redesigned).
enum EditorTool: String, CaseIterable, Identifiable {
    case edit, audio, text, effects, filter, aspectRatio, background, adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return "Edit"
        case .audio: return "Audio"
        case .text: return "Text"
        case .effects: return "Effects"
        case .filter: return "Filter"
        case .aspectRatio: return "Aspect Ratio"
        case .background: return "Background"
        case .adjust: return "Adjust"
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
