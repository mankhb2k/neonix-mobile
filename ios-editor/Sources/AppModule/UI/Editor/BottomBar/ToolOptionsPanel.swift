import SwiftUI

/// Contextual options panel shown above the bottom nav for the selected
/// tool. Every tool has one except `.filter` (Bộ lọc), which is still a
/// placeholder — see `EditorTool.hasOptionsPanel`.
struct ToolOptionsPanel: View {
    let tool: EditorTool
    let composition: V2Composition
    /// The currently selected clip, if any (Text and Adjust edit it).
    let selectedLayer: V2Layer?
    /// Âm thanh — the selected standalone `V2AudioClip`, if any.
    let selectedAudioClip: V2AudioClip?
    let onSetAspectRatio: (Double, Double) -> Void
    let onSetBackgroundColor: (String) -> Void
    let onPickAudioFile: (URL) -> Void
    let onSetAudioVolume: (String, Double) -> Void
    let onDeleteAudio: (String) -> Void
    /// Ghi âm — same destination as `onPickAudioFile`, just sourced from
    /// the mic instead of the Files app.
    let onRecordingFinished: (URL) -> Void
    /// Hiệu ứng âm thanh — see `SoundEffectCatalog`'s own doc comment: this
    /// is a one-tap sound-effect library, not a DSP processing effect.
    let onAddSoundEffect: (SoundEffectPreset) -> Void
    /// Văn bản — add a new text clip at the playhead, or edit the selected
    /// one's content (same `selectedLayer` Chỉnh sửa already reads).
    let onAddText: (String) -> Void
    let onSetTextContent: (String, String) -> Void
    /// A feature that is only a button so far (Auto captions): the shell shows its "coming soon" note.
    let onComingSoon: (String) -> Void

    var body: some View {
        switch tool {
        case .aspectRatio:
            AspectRatioOptionsRow(current: (composition.width, composition.height), onSelect: onSetAspectRatio)
        case .background:
            BackgroundColorOptionsRow(current: composition.background, onSelect: onSetBackgroundColor)
        case .audio:
            AudioOptionsRow(
                selectedClip: selectedAudioClip,
                onPickFile: onPickAudioFile,
                onSetVolume: onSetAudioVolume,
                onDelete: onDeleteAudio,
                onRecordingFinished: onRecordingFinished
            )
        case .effects:
            SoundEffectsOptionsRow(onSelect: onAddSoundEffect)
        case .text:
            TextOptionsRow(selectedLayer: selectedLayer, onAddText: onAddText, onSetTextContent: onSetTextContent, onComingSoon: onComingSoon)
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

/// Văn bản. With no text clip selected the Text tool first offers a short list - **Add text** and **Auto captions**
/// (user 2026-10-12); Add text then shows the text field (`AddTextLayerCommand`, a new clip at the playhead). With a
/// text clip selected ("Edit text" in its row) it goes straight to the field and rewrites just that clip's content
/// (`SetTextContentCommand`; its position and duration never move).
private struct TextOptionsRow: View {
    let selectedLayer: V2Layer?
    let onAddText: (String) -> Void
    let onSetTextContent: (String, String) -> Void
    let onComingSoon: (String) -> Void

    @State private var draftText: String = ""
    @State private var isTyping = false

    private var selectedTextLayer: V2Layer? {
        guard let selectedLayer, selectedLayer.type == "text" else { return nil }
        return selectedLayer
    }

    private var currentText: String? {
        guard case .text(let payload) = selectedTextLayer?.payload else { return nil }
        return payload.source.text
    }

    private var canCommit: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isTyping || selectedTextLayer != nil {
                HStack(spacing: 12) {
                    TextField(selectedTextLayer == nil ? "Enter text..." : "Edit text...", text: $draftText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commit)
                        .accessibilityIdentifier("editorTextField")
                    Button(selectedTextLayer == nil ? "Add Text" : "Done", action: commit)
                        .disabled(!canCommit)
                }
                .padding(.horizontal)
            } else {
                HStack(spacing: 28) {
                    choice("Add text", symbol: "text.badge.plus", id: "text-add") { isTyping = true }
                    choice("Auto captions", symbol: "captions.bubble", id: "text-captions") { onComingSoon("Auto captions") }
                }
            }
        }
        .onAppear { draftText = currentText ?? "" }
        .onChange(of: selectedLayer?.id) { _, _ in draftText = currentText ?? ""; isTyping = false }
    }

    private func choice(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2).lineLimit(1)
            }
            .frame(minWidth: 72)
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func commit() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let layer = selectedTextLayer {
            onSetTextContent(layer.id, trimmed)
        } else {
            onAddText(trimmed)
            draftText = ""
            isTyping = false
        }
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

/// Âm thanh — "Thêm nhạc" (import + place at the playhead) when nothing's
/// selected, a volume slider + "Xoá" when a standalone clip is selected.
/// Dragging a clip to reposition/trim it is explicitly deferred (see the
/// "audio playback foundation" roadmap plan) — this ships exactly what
/// doesn't need a new timeline gesture.
private struct AudioOptionsRow: View {
    let selectedClip: V2AudioClip?
    let onPickFile: (URL) -> Void
    let onSetVolume: (String, Double) -> Void
    let onDelete: (String) -> Void
    /// Ghi âm — the finished recording's temp URL, handed to the exact
    /// same `addAudio(from:)` path `onPickFile` already uses.
    let onRecordingFinished: (URL) -> Void

    @State private var showingPicker = false
    @StateObject private var recorder = AudioRecorderService()
    /// 0–1 UI range, converted to/from `gainDb` (0 dB == 1.0, matching the
    /// clip's own "no clip yet authored" default).
    @State private var volumeFraction: Double = 1

    var body: some View {
        if let selectedClip {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume").font(.caption2).foregroundColor(.secondary)
                    Slider(value: $volumeFraction, in: 0...1) { editing in
                        guard !editing else { return }
                        onSetVolume(selectedClip.id, dB(fromFraction: volumeFraction))
                    }
                    .frame(width: 160)
                }
                Button(role: .destructive) {
                    onDelete(selectedClip.id)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash").font(.title3)
                        Text("Delete").font(.caption2)
                    }
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .onAppear { volumeFraction = fraction(fromDB: selectedClip.gainDb ?? 0) }
            .onChange(of: selectedClip.id) { _, _ in volumeFraction = fraction(fromDB: selectedClip.gainDb ?? 0) }
        } else {
            HStack(spacing: 20) {
                Button {
                    showingPicker = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "music.note.list").font(.title3)
                        Text("Add Music").font(.caption2)
                    }
                }
                .disabled(recorder.isRecording)

                Button {
                    if recorder.isRecording {
                        if let url = recorder.stopRecording() {
                            onRecordingFinished(url)
                        }
                    } else {
                        Task { await recorder.startRecording() }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.title3)
                        Text(recorder.isRecording ? formattedElapsed : "Record")
                            .font(.caption2)
                    }
                }
                .foregroundColor(recorder.isRecording ? .red : .primary)

                if recorder.permissionDenied {
                    Text("Microphone access needed in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !recorder.isRecording {
                    Text("Select an audio clip on the timeline to adjust volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .sheet(isPresented: $showingPicker) {
                AudioFilePicker(onPick: onPickFile)
            }
        }
    }

    private var formattedElapsed: String {
        let total = Int(recorder.elapsedSeconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// `gainDb` 0 → fraction 1 (unity); -40dB floor → fraction 0. A plain
    /// linear 0–1 slider over dB would spend most of its range on barely-
    /// audible levels, so this maps the slider's own linear travel onto a
    /// dB range instead of onto linear gain.
    private func dB(fromFraction fraction: Double) -> Double {
        -40 * (1 - fraction)
    }

    private func fraction(fromDB gainDb: Double) -> Double {
        min(max(1 + gainDb / 40, 0), 1)
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
