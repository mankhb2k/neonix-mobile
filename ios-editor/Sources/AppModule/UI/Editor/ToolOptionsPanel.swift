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
    let currentTimeMs: Double
    let onSetAspectRatio: (Double, Double) -> Void
    let onSetBackgroundColor: (String) -> Void
    let onSplit: (String, Double) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        switch tool {
        case .aspectRatio:
            AspectRatioOptionsRow(current: (composition.width, composition.height), onSelect: onSetAspectRatio)
        case .background:
            BackgroundColorOptionsRow(current: composition.background, onSelect: onSetBackgroundColor)
        case .edit:
            EditOptionsRow(
                selectedLayer: selectedLayer, currentTimeMs: currentTimeMs,
                onSplit: onSplit, onDelete: onDelete
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
        self == .aspectRatio || self == .background || self == .edit
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

    /// Split only makes sense strictly inside the clip's own range — right
    /// at either edge would produce a zero-length half.
    private var canSplit: Bool {
        guard let layer = selectedLayer else { return false }
        return currentTimeMs > layer.timing.start && currentTimeMs < layer.timing.start + layer.timing.duration
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
                        Text("Tách")
                            .font(.caption2)
                    }
                }
                .disabled(!canSplit)
                .foregroundColor(canSplit ? .primary : .secondary)

                Button(role: .destructive) {
                    onDelete(selectedLayer.id)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.title3)
                        Text("Xoá")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)
        } else {
            Text("Chọn 1 clip trên timeline để chỉnh sửa")
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
