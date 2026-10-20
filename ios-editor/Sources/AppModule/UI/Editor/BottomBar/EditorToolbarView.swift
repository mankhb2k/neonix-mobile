import SwiftUI

/// The main row of tools. Choosing one replaces this row (with the tool's own options, or, for Edit, with the tools of
/// the clip under the playhead) - nothing is highlighted because this row is not on screen while a tool is in use.
struct EditorToolbarView: View {
    let onSelect: (EditorTool) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(EditorTool.navigationTools) { tool in
                    Button { onSelect(tool) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.systemImage)
                                .font(.body)
                            Text(tool.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundColor(.primary)
                        .frame(width: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tool-\(tool.rawValue)")
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 58)
        .background(Color(.systemBackground))
    }
}
