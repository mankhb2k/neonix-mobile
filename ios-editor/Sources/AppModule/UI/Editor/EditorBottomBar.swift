import SwiftUI

/// "«" at the left of the bottom bar: one level back (a tool's options -> the selection's tools -> the main tools).
/// The bottom of the editor is always exactly one row; going deeper replaces the row instead of stacking a second one.
struct BottomBarBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left.2")
                .font(.body.weight(.semibold))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolbarBack")
        .accessibilityLabel("Back")
    }
}

/// The one row shown while a clip, photo, text or audio clip is selected: what can be done with *that* thing, with
/// a back button that deselects it. Transform and Adjust open as a sheet over the lower part of the screen (a ruler and
/// round buttons); the text field and the volume slider open as the next row, with their own back button.
struct SelectionToolbarView: View {
    enum Subject {
        case layer(V2Layer)
        case audioClip
    }

    let subject: Subject
    let canSplit: Bool
    let onBack: () -> Void
    let onSplit: () -> Void
    let onExtractAudio: () -> Void
    let onTransform: () -> Void
    let onAdjust: () -> Void
    /// Text and Audio still open their options as the next row.
    let onOpenTool: (EditorTool) -> Void
    let onDelete: () -> Void

    var body: some View {
        // Only 4 pt between the divider and the scroll view's clip edge, where actions slide out of sight;
        // the rest of the gap at rest (8 pt) is scroll content margin.
        HStack(spacing: 0) {
            BottomBarBackButton(action: onBack)
                .padding(.trailing, 8)
            Divider().frame(height: 28)
                .padding(.trailing, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) { actions }
            }
            .contentMargins(.horizontal, 8, for: .scrollContent)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selectionToolbar")
    }

    @ViewBuilder private var actions: some View {
        switch subject {
        case .layer(let layer):
            if layer.type == "text" { action("Edit text", "pencil", id: "edit-text") { onOpenTool(.text) } }
            action("Split", "scissors", id: "split", enabled: canSplit, perform: onSplit)
            if layer.type == "video" { action("Extract Audio", "waveform", id: "extract-audio", perform: onExtractAudio) }
            if layer.type != "group" { action("Transform", "arrow.up.left.and.arrow.down.right", id: "transform", perform: onTransform) }
            if layer.type == "video" || layer.type == "image" { action("Adjust", "slider.horizontal.3", id: "adjust", perform: onAdjust) }
            action("Delete", "trash", id: "delete", tint: .red, perform: onDelete)
        case .audioClip:
            action("Volume", "speaker.wave.2", id: "volume") { onOpenTool(.audio) }
            action("Delete", "trash", id: "delete", tint: .red, perform: onDelete)
        }
    }

    private func action(_ title: String, _ symbol: String, id: String, enabled: Bool = true, tint: Color? = nil,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2).lineLimit(1)
            }
            .frame(minWidth: 48)
            .foregroundColor(enabled ? (tint ?? .primary) : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("action-\(id)")
    }
}
