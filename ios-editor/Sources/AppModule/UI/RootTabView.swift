import SwiftUI

/// The app's root UI — saved/created projects and account. The template
/// catalogue is currently hidden; opening a project from Folder
/// presents the real `EditorShellView`. The old `ContentView` dev-fixture
/// picker (reachable via Account > Developer) was deleted 2026-10-08 once
/// the real Editor screen made it redundant.
struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ProjectsView()
            }
            .tabItem { Label("Folder", systemImage: "folder") }
            .tag(0)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("Account", systemImage: "person.circle") }
            .tag(1)
        }
    }
}
