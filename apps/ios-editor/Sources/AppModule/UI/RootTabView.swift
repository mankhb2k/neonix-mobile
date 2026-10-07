import SwiftUI

/// The app's real root UI — three tabs (browse templates, saved/created
/// projects, account). Each tab's content is placeholder/sample data for
/// now (see each view's own doc comment); the actual Editor screen is
/// separate, not-yet-built work — `ContentView`'s fixture picker stays
/// reachable only via Account > Developer for now.
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
