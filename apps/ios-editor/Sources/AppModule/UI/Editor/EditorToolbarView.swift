import SwiftUI

/// Bottom tool row — icon above label, horizontally scrollable, matching
/// CapCut's own bottom nav *layout* only. Colors stay the app's established
/// light/system-dynamic-color chrome (`CLAUDE.md`'s standing rule for this
/// screen's nav), not CapCut's dark theme — confirmed with the user
/// 2026-10-07 rather than assumed from the reference screenshot.
///
/// No per-tool screen exists yet (see `EditorTool.swift`'s own doc comment
/// on the 7-tool v1 scope) — tapping only toggles which tool is
/// highlighted, nothing opens. Tapping the already-selected tool clears the
/// selection, so "nothing selected" stays a reachable, honest resting state
/// given there's no content to show either way.
struct EditorToolbarView: View {
    @Binding var selectedTool: EditorTool?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        selectedTool = (selectedTool == tool) ? nil : tool
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.systemImage)
                                .font(.body)
                            Text(tool.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedTool == tool ? .accentColor : .primary)
                        .frame(width: 64)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 58)
        .background(Color(.systemBackground))
    }
}
