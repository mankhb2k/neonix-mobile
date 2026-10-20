import SwiftUI

/// Contextual options panel shown above the bottom nav for the selected
/// tool. Every tool has one except `.filter` (Bộ lọc), which is still a
/// placeholder — see `EditorTool.hasOptionsPanel`.
struct ToolOptionsPanel: View {
    let tool: EditorTool
    let composition: V2Composition
    /// The currently selected clip, if any (Text and Adjust edit it).
    let selectedLayer: V2Layer?
    let onSetAspectRatio: (Double, Double) -> Void
    let onSetBackgroundColor: (String) -> Void
    let onPickAudioFile: (URL) -> Void
    /// Audio > Record: the shell opens the recorder popup.
    let onRecord: () -> Void
    /// Hiệu ứng âm thanh — see `SoundEffectCatalog`'s own doc comment: this
    /// is a one-tap sound-effect library, not a DSP processing effect.
    let onAddSoundEffect: (SoundEffectPreset) -> Void
    /// Văn bản — "Add text": the shell adds a clip at the playhead and opens the Text sheet on it.
    let onAddText: () -> Void
    /// A feature that is only a button so far (Auto captions): the shell shows its "coming soon" note.
    let onComingSoon: (String) -> Void
    /// Audio > Extract: the shell opens the video picker.
    let onExtractAudio: () -> Void
    /// Audio > Sound FX: the shell opens the sound library sheet.
    let onSoundFX: () -> Void

    var body: some View {
        switch tool {
        case .aspectRatio:
            AspectRatioOptionsRow(current: (composition.width, composition.height), onSelect: onSetAspectRatio)
        case .background:
            BackgroundColorOptionsRow(current: composition.background, onSelect: onSetBackgroundColor)
        case .audio:
            AudioOptionsRow(
                onPickFile: onPickAudioFile,
                onRecord: onRecord,
                onExtract: onExtractAudio,
                onSoundFX: onSoundFX
            )
        case .effects:
            SoundEffectsOptionsRow(onSelect: onAddSoundEffect)
        case .text:
            TextOptionsRow(onAddText: onAddText, onComingSoon: onComingSoon)
        default:
            EmptyView()
        }
    }
}

/// Still only usable from this file: whether a tool's panel actually
/// renders something (vs. `EmptyView()`) — `EditorShellView` uses this to
/// decide whether to reserve layout space for the panel at all.
extension EditorTool {
    var hasOptionsPanel: Bool {
        self == .aspectRatio || self == .background || self == .audio || self == .effects || self == .text
    }
}

/// Văn bản. The Text tool is a short list (user 2026-10-12): **Add text** (adds a clip at the playhead and opens the Text sheet on
/// it) and **Auto captions**. Editing an existing text clip goes through its own row ("Edit text") to the same sheet.
private struct TextOptionsRow: View {
    let onAddText: () -> Void
    let onComingSoon: (String) -> Void

    var body: some View {
        HStack(spacing: BottomBarItem.spacing) {
            choice("Add text", symbol: "text.badge.plus", id: "text-add", action: onAddText)
            choice("Auto captions", symbol: "captions.bubble", id: "text-captions") { onComingSoon("Auto captions") }
        }
        .padding(.horizontal, 8)
    }

    private func choice(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BottomBarItem(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Hiệu ứng âm thanh — one tap places the effect at the playhead, same
/// `AddAudioClipCommand` "Thêm nhạc" uses, just from `SoundEffectCatalog`'s
/// bundled presets instead of a Files-app import. No selection state of its
/// own (unlike Âm thanh) — there's nothing to configure per-tap, tapping
/// again just adds another copy.
private struct SoundEffectsOptionsRow: View {
    let onSelect: (SoundEffectPreset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(SoundEffectCatalog.presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: preset.systemImage).font(.title3)
                            Text(preset.title).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Âm thanh — the four ways to get sound onto the timeline: Extract, Music, Sound FX, Record. A selected audio clip has its own row
/// (`SelectionToolbarView`: Split, Volume, Fade, Delete...); Volume opens `VolumeSheet`.
private struct AudioOptionsRow: View {
    let onPickFile: (URL) -> Void
    /// Record opens the recorder popup (`RecorderSheet`).
    let onRecord: () -> Void
    /// Extract opens the video picker, Sound FX the library sheet.
    let onExtract: () -> Void
    let onSoundFX: () -> Void

    @State private var showingPicker = false

    var body: some View {
        // The four ways to get sound onto the timeline, one row like the Text tool's (user 2026-10-16).
        HStack(spacing: BottomBarItem.spacing) {
            label("Extract", symbol: "film.stack", id: "audio-extract", action: onExtract)
            label("Music", symbol: "music.note", id: "audio-music") { showingPicker = true }
            label("Sound FX", symbol: "speaker.wave.3.fill", id: "audio-sfx", action: onSoundFX)
            label("Record", symbol: "mic.fill", id: "audio-record", action: onRecord)
        }
        .padding(.horizontal, 8)
        .sheet(isPresented: $showingPicker) {
            AudioFilePicker(onPick: onPickFile)
        }
    }

    /// One label, the same item as the Edit row's.
    private func label(_ title: String, symbol: String, id: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BottomBarItem(title: title, symbol: symbol, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

}

/// Fits a `width:height` ratio inside a `maxDimension × maxDimension` box
/// — the limiting dimension is whichever of width/height is *larger*
/// relative to the other, not always the width. A naive "fix width to
/// `maxDimension`, scale height" (what this file's first version did)
/// overflows badly for a portrait ratio like 9:16, where height is the
/// larger side.
private func aspectFitSize(width: Double, height: Double, maxDimension: CGFloat) -> CGSize {
    guard width > 0, height > 0 else { return CGSize(width: maxDimension, height: maxDimension) }
    if width >= height {
        return CGSize(width: maxDimension, height: maxDimension * height / width)
    } else {
        return CGSize(width: maxDimension * width / height, height: maxDimension)
    }
}

private struct AspectRatioPreset {
    let title: String
    let width: Double
    let height: Double
}

/// A small, deliberately short list — CapCut's own common presets, not
/// every possible ratio. More can be added later without any structural
/// change here.
private let aspectRatioPresets: [AspectRatioPreset] = [
    AspectRatioPreset(title: "9:16", width: 360, height: 640),
    AspectRatioPreset(title: "1:1", width: 480, height: 480),
    AspectRatioPreset(title: "4:5", width: 384, height: 480),
    AspectRatioPreset(title: "16:9", width: 640, height: 360),
]

private struct AspectRatioOptionsRow: View {
    let current: (width: Double, height: Double)
    let onSelect: (Double, Double) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(aspectRatioPresets, id: \.title) { preset in
                    let isSelected = preset.width == current.width && preset.height == current.height
                    let iconSize = aspectFitSize(width: preset.width, height: preset.height, maxDimension: 28)
                    Button {
                        onSelect(preset.width, preset.height)
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: isSelected ? 2 : 1)
                                .frame(width: iconSize.width, height: iconSize.height)
                                .frame(width: 28, height: 28)
                            Text(preset.title)
                                .font(.caption2)
                        }
                        .foregroundColor(isSelected ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Solid colors only — `composition.background` is a hex string, no
/// image/blur background type exists in Protocol V2 today. Out of scope
/// for this pass, per the roadmap plan.
private let backgroundColorPresets: [String] = [
    "#101820", "#000000", "#FFFFFF", "#1C1C1E", "#2C2C54", "#34495E", "#8E44AD", "#C0392B",
]

private struct BackgroundColorOptionsRow: View {
    let current: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(backgroundColorPresets, id: \.self) { hex in
                    let isSelected = hex.caseInsensitiveCompare(current) == .orderedSame
                    Button {
                        onSelect(hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
