import SwiftUI

/// Placeholder sample data — no persisted-project store exists yet. Each
/// sample's own aspect ratio exercises a different Stage shape; see
/// `ui-design-note.md` (repo root).
struct ProjectSample: Identifiable {
    let id = UUID()
    let name: String
    let lastEdited: String
    let gradient: [Color]
    let compositionWidth: Double
    let compositionHeight: Double
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
        ProjectSample(name: "Trip to Paris", lastEdited: "2 hours ago", gradient: [.blue, .teal], compositionWidth: 360, compositionHeight: 640), // 9:16
        ProjectSample(name: "Product Launch", lastEdited: "Yesterday", gradient: [.pink, .purple], compositionWidth: 640, compositionHeight: 360), // 16:9
        ProjectSample(name: "Birthday Recap", lastEdited: "3 days ago", gradient: [.orange, .yellow], compositionWidth: 480, compositionHeight: 480), // 1:1
    ]
    // `fullScreenCover`, not `NavigationLink` — a pushed page inside a
    // `TabView` leaves this tab's own tab bar showing underneath it.
    @State private var openedProject: ProjectSample?

    var body: some View {
        List {
            ForEach(projects) { project in
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
                    projects.insert(ProjectSample(name: "New Project", lastEdited: "Just now", gradient: [.gray, .black], compositionWidth: 360, compositionHeight: 640), at: 0)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fullScreenCover(item: $openedProject) { project in
            EditorShellView(project: compile(EditorDemoView.makeDocument(
                media: .videoPortrait, inOption: .none, outOption: .none,
                effectOption: .none, easingOption: .linear,
                composition: V2Composition(width: project.compositionWidth, height: project.compositionHeight, fps: 30, background: "#101820"),
                frame: V2Frame(width: project.compositionWidth, height: project.compositionHeight)
            )))
        }
    }
}
