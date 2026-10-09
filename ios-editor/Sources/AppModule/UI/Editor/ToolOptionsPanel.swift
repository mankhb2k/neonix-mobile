import SwiftUI

/// Contextual options panel shown above the bottom nav when a tool that
/// has real functionality is selected — see the "Bottom nav tools"
/// roadmap plan for which tools are built vs. still placeholder. Only
/// `.aspectRatio`/`.background` do anything today (Phase 1); every other
/// tool still just highlights (`EditorToolbarView`'s own behavior,
/// unchanged).
struct ToolOptionsPanel: View {
    let tool: EditorTool
    let composition: V2Composition
    /// Chỉnh sửa only — the currently selected clip, if any (`nil` when
    /// nothing's selected, which the panel itself renders as a hint rather
    /// than an empty space).
    let selectedLayer: V2Layer?
    /// Âm thanh — the selected standalone `V2AudioClip`, if any.
    let selectedAudioClip: V2AudioClip?
    let currentTimeMs: Double
    let onSetAspectRatio: (Double, Double) -> Void
    let onSetBackgroundColor: (String) -> Void
    let onSplit: (String, Double) -> Void
    let onDelete: (String) -> Void
    let onExtractAudio: (String) -> Void
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
    /// Tuỳ chỉnh — the selected layer's current slider values (neutral if
    /// never adjusted this session), plus the same begin/live-update/end
    /// shape `TimelineView`'s drag-to-trim handles already use.
    let adjustValues: AdjustValues
    let onAdjustBegin: () -> Void
    let onAdjustChange: (String, AdjustValues) -> Void
    let onAdjustEnd: () -> Void

    var body: some View {
        switch tool {
        case .aspectRatio:
            AspectRatioOptionsRow(current: (composition.width, composition.height), onSelect: onSetAspectRatio)
        case .background:
            BackgroundColorOptionsRow(current: composition.background, onSelect: onSetBackgroundColor)
        case .edit:
            EditOptionsRow(
                selectedLayer: selectedLayer, currentTimeMs: currentTimeMs,
                onSplit: onSplit, onDelete: onDelete, onExtractAudio: onExtractAudio
            )
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
            TextOptionsRow(selectedLayer: selectedLayer, onAddText: onAddText, onSetTextContent: onSetTextContent)
        case .adjust:
            AdjustOptionsRow(
                selectedLayer: selectedLayer, values: adjustValues,
                onBegin: onAdjustBegin, onChange: onAdjustChange, onEnd: onAdjustEnd
            )
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
        self == .aspectRatio || self == .background || self == .edit || self == .audio || self == .effects || self == .text || self == .adjust
    }
}

/// Tuỳ chỉnh — every continuous slider this tool has, compiling straight
/// into `EffectPresetKind`/`SetAdjustCommand` (see CLAUDE.md's "Tuỳ chỉnh"
/// note): Light/color basics, HSL, white balance, tone curve (Highlights/
/// Shadows/Whites/Blacks — the stand-in for a real draggable curve graph,
/// confirmed with the user), and detail/effects. Unlike `AudioOptionsRow`'s
/// volume slider (commit-on-release only), every tick calls `onChange`
/// live — a grading tool is useless without real-time feedback — while
/// `onBegin`/`onEnd` (driven by `Slider`'s own `onEditingChanged`) bracket
/// exactly one undo step per drag, same shape as `TimelineView`'s
/// drag-to-trim handles. One long horizontal scroll, not grouped tabs —
/// simplest thing that works for ~17 sliders without new navigation chrome.
private struct AdjustOptionsRow: View {
    let selectedLayer: V2Layer?
    let values: AdjustValues
    let onBegin: () -> Void
    let onChange: (String, AdjustValues) -> Void
    let onEnd: () -> Void

    @State private var local = AdjustValues()

    var body: some View {
        if let selectedLayer {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    adjustSlider("Brightness", value: $local.brightness, range: -0.5...0.5)
                    adjustSlider("Contrast", value: $local.contrast, range: 0.5...1.5)
                    adjustSlider("Saturation", value: $local.saturation, range: 0...2)
                    adjustSlider("Exposure", value: $local.exposure, range: -2...2)
                    Divider()
                    adjustSlider("Hue", value: $local.hue, range: -180...180)
                    adjustSlider("Lightness", value: $local.lightness, range: -0.5...0.5)
                    Divider()
                    adjustSlider("Temperature", value: $local.temperature, range: -1...1)
                    adjustSlider("Tint", value: $local.tint, range: -1...1)
                    Divider()
                    adjustSlider("Blacks", value: $local.blacks, range: -1...1)
                    adjustSlider("Shadows", value: $local.shadows, range: -1...1)
                    adjustSlider("Highlights", value: $local.highlights, range: -1...1)
                    adjustSlider("Whites", value: $local.whites, range: -1...1)
                    Divider()
                    adjustSlider("Sharpen", value: $local.sharpen, range: 0...1)
                    adjustSlider("Clarity", value: $local.clarity, range: -1...1)
                    adjustSlider("Blur", value: $local.blur, range: 0...20)
                    Divider()
                    adjustSlider("Vignette", value: $local.vignette, range: 0...2)
                    adjustSlider("Noise", value: $local.noise, range: 0...1)
                }
                .padding(.horizontal)
            }
            .onAppear { local = values }
            .onChange(of: selectedLayer.id) { _, _ in local = values }
        } else {
            Text("Select a clip on the timeline to adjust")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }

    private func adjustSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Slider(value: value, in: range) { editing in
                if editing {
                    onBegin()
                } else {
                    onEnd()
                }
            }
            .frame(width: 140)
            // `Slider`'s own live `value` updates continuously while
            // dragging regardless of `onEditingChanged` — this is what
            // gives the Stage real-time feedback, not just a final value
            // on release.
            .onChange(of: value.wrappedValue) { _, _ in
                guard let selectedLayer else { return }
                onChange(selectedLayer.id, local)
            }
        }
    }
}

/// Văn bản — a single text field that does double duty: "Thêm chữ" when
/// nothing text-ish is selected (places a new clip at the playhead,
/// `AddTextLayerCommand`), "Sửa nội dung" when a text clip already is
/// (`SetTextContentCommand`, rewriting just that clip's content in place —
/// its position/duration never move). Reusing `selectedLayer` is
/// deliberate: it's the same selection Chỉnh sửa's Tách/Xoá already act on,
/// so selecting a text clip in either tool lets you edit it in this one.
private struct TextOptionsRow: View {
    let selectedLayer: V2Layer?
    let onAddText: (String) -> Void
    let onSetTextContent: (String, String) -> Void

    @State private var draftText: String = ""

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
        HStack(spacing: 12) {
            TextField(selectedTextLayer == nil ? "Enter text..." : "Edit text...", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            Button(selectedTextLayer == nil ? "Add Text" : "Done", action: commit)
                .disabled(!canCommit)
        }
        .padding(.horizontal)
        .onAppear { draftText = currentText ?? "" }
        .onChange(of: selectedLayer?.id) { _, _ in draftText = currentText ?? "" }
    }

    private func commit() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let layer = selectedTextLayer {
            onSetTextContent(layer.id, trimmed)
        } else {
            onAddText(trimmed)
            draftText = ""
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

/// Chỉnh sửa (Phase 2) — Tách (split at the playhead) and Xoá (delete),
/// both acting on whichever clip is currently selected in the Timeline.
/// Drag-to-trim handles directly on the clip are a separate, bigger UI
/// piece explicitly deferred — see the "Bottom nav tools" roadmap plan;
/// this ships the 2 actions that don't need a new gesture at all.
private struct EditOptionsRow: View {
    let selectedLayer: V2Layer?
    let currentTimeMs: Double
    let onSplit: (String, Double) -> Void
    let onDelete: (String) -> Void
    /// Trích xuất — only meaningful for a video clip (there's no embedded
    /// audio to pull out of an image/text/shape layer).
    let onExtractAudio: (String) -> Void

    /// Split only makes sense strictly inside the clip's own range — right
    /// at either edge would produce a zero-length half.
    private var canSplit: Bool {
        guard let layer = selectedLayer else { return false }
        return currentTimeMs > layer.timing.start && currentTimeMs < layer.timing.start + layer.timing.duration
    }

    private var isVideo: Bool {
        selectedLayer?.type == "video"
    }

    var body: some View {
        if let selectedLayer {
            HStack(spacing: 20) {
                Button {
                    onSplit(selectedLayer.id, currentTimeMs)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.title3)
                        Text("Split")
                            .font(.caption2)
                    }
                }
                .disabled(!canSplit)
                .foregroundColor(canSplit ? .primary : .secondary)

                if isVideo {
                    Button {
                        onExtractAudio(selectedLayer.id)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.title3)
                            Text("Extract Audio")
                                .font(.caption2)
                        }
                    }
                }

                Button(role: .destructive) {
                    onDelete(selectedLayer.id)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.title3)
                        Text("Delete")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)
        } else {
            Text("Select a clip on the timeline to edit")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
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
