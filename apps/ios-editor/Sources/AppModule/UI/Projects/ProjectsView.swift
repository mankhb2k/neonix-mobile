import SwiftUI

/// Placeholder sample data only — no persisted-project store exists yet
/// (Editor Document save/load isn't wired to a project library).
struct ProjectSample: Identifiable {
    let id = UUID()
    let name: String
    let lastEdited: String
    let gradient: [Color]
}

private struct ProjectRow: View {
    let project: ProjectSample

    var body: some View {
        HStack(spacing: 12) {
            LinearGradient(colors: project.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.body.weight(.medium))
                Text("Edited \(project.lastEdited)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct ProjectsView: View {
    @State private var projects: [ProjectSample] = [
        ProjectSample(name: "Trip to Paris", lastEdited: "2 hours ago", gradient: [.blue, .teal]),
        ProjectSample(name: "Product Launch", lastEdited: "Yesterday", gradient: [.pink, .purple]),
        ProjectSample(name: "Birthday Recap", lastEdited: "3 days ago", gradient: [.orange, .yellow]),
    ]
    // `fullScreenCover`, not a `NavigationLink` push — the Editor is a full
    // immersive takeover (its own X button dismisses it), matching CapCut's
    // own UX, and a `NavigationLink` push would leave this tab's own tab bar
    // showing underneath it (confirmed on the simulator), which a pushed
    // page inside a `TabView` does by default unless told otherwise.
    @State private var openedProject: ProjectSample?

    var body: some View {
        List {
            ForEach(projects) { project in
                // `ProjectSample` has no real document backing yet (see its
                // own doc comment), so every row opens the same placeholder
                // composition — `EditorShellView`'s own doc comment explains
                // why. This still proves Folder → Editor navigation end to
                // end.
                Button {
                    openedProject = project
                } label: {
                    ProjectRow(project: project)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    projects.insert(ProjectSample(name: "New Project", lastEdited: "Just now", gradient: [.gray, .black]), at: 0)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fullScreenCover(item: $openedProject) { _ in
            EditorShellView(project: compile(EditorDemoView.makeDocument(
                media: .videoPortrait, inOption: .none, outOption: .none,
                effectOption: .none, easingOption: .linear
            )))
        }
    }
}
