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

/// One button of a bottom-bar row: an icon over a caption. The Edit row (`SelectionToolbarView`) and the Text and Audio tools' rows all
/// use it, so the icon size and spacing are the same everywhere (user 2026-10-16): `title3` icon, 48 pt minimum width, rows spaced
/// by `BottomBarItem.spacing`.
struct BottomBarItem: View {
    let title: String
    let symbol: String
    var tint: Color = .primary

    static let spacing: CGFloat = 22

    var body: some View {
        VStack(spacing: 4) {
            // The icons differ in height; a fixed box keeps the captions on one line.
            Image(systemName: symbol).font(.title3).frame(height: 24)
            Text(title).font(.caption2).lineLimit(1)
        }
        .frame(minWidth: 48)
        .foregroundColor(tint)
    }
}

/// The one row shown while a clip, photo, text or audio clip is selected: what can be done with *that* thing, with
/// a back button that deselects it on the left and Delete pinned on the right. The tools in between scroll sideways;
/// which ones appear, and in what order, is `ClipTool.tools(for:)`. A tool that is not built yet shows a short
/// "coming soon" note instead of doing anything (`EditorShellView.handleClipTool`).
struct SelectionToolbarView: View {
    enum Subject {
        case layer(V2Layer)
        case audioClip
    }

    let subject: Subject
    /// The selected video has a sound track (decides Volume / Extract Audio / Unlink).
    let hasAudio: Bool
    let canSplit: Bool
    /// The playhead is between two keyframes of the selection: only then is Graph live (otherwise it shows dimmed).
    var canGraph = false
    let onBack: () -> Void
    let onTool: (ClipTool) -> Void

    private var kind: ClipKind {
        switch subject {
        case .layer(let layer): return ClipKind(layer: layer)
        case .audioClip: return .audio
        }
    }

    var body: some View {
        // Only 4 pt between the divider and the scroll view's clip edge, where actions slide out of sight;
        // the rest of the gap at rest (8 pt) is scroll content margin.
        HStack(spacing: 0) {
            BottomBarBackButton(action: onBack)
                .padding(.trailing, 8)
            Divider().frame(height: 28)
                .padding(.trailing, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BottomBarItem.spacing) {
                    ForEach(ClipTool.tools(for: kind)) { tool in button(tool) }
                }
            }
            .contentMargins(.horizontal, 8, for: .scrollContent)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selectionToolbar")
    }

    private func button(_ tool: ClipTool) -> some View {
        let needsSound = kind == .video && (tool == .volume || tool == .unlink)
        let enabled = (tool != .split || canSplit) && (tool != .graph || canGraph) && (!needsSound || hasAudio)
        return Button { onTool(tool) } label: {
            BottomBarItem(title: tool.title, symbol: tool.symbol, tint: !enabled ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("action-\(tool.id)")
    }
}
