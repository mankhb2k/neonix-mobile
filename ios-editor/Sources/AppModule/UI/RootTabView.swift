import SwiftUI

/// The app's real root UI — three tabs (browse templates, saved/created
/// projects, account). Each tab's content is placeholder/sample data for
/// now (see each view's own doc comment); opening a project from Folder
/// presents the real `EditorShellView`. The old `ContentView` dev-fixture
/// picker (reachable via Account > Developer) was deleted 2026-10-08 once
/// the real Editor screen made it redundant.
struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                ProjectsView()
            }
            .tabItem { Label("Folder", systemImage: "folder") }
            .tag(1)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("Account", systemImage: "person.circle") }
            .tag(2)
        }
    }
}
