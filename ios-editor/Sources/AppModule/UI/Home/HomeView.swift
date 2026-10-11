import SwiftUI

/// Browse screen: search, category chips and a two-column waterfall of the published templates. Tapping a card
/// opens the full-screen viewer; "Use template" there starts the fill-the-slots flow.
struct HomeView: View {
    @State private var catalog = TemplateCatalog()
    /// nil = Discover.
    @State private var category: String?
    @State private var searchText = ""
    @State private var viewer: ViewerRequest?

    private struct ViewerRequest: Identifiable {
        let id = UUID()
        let templates: [APITemplate]
        let startID: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                if catalog.categories.count > 0 { chips }
                feed
            }
            .padding(.vertical)
        }
        .refreshable { await reload() }
        // Reloads on first show and whenever the search text or category changes (debounced for typing).
        .task(id: SearchKey(text: searchText, category: category)) {
            if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
            if Task.isCancelled { return }
            await reload()
        }
        // Back from the viewer: what was bought there should now say "Owned".
        .fullScreenCover(item: $viewer, onDismiss: { Task { await reload() } }) { request in
            TemplateViewerView(templates: request.templates, startID: request.startID)
        }
    }

    private struct SearchKey: Hashable { let text: String; let category: String? }

    private func reload() async {
        await catalog.reload(query: searchText, category: category)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search templates", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Discover", selected: category == nil) { category = nil }
                ForEach(catalog.categories, id: \.self) { name in
                    chip(TemplateCatalog.displayName(forCategory: name), selected: category == name) { category = name }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundColor(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var feed: some View {
        if catalog.templates.isEmpty {
            switch catalog.state {
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundColor(.secondary)
                    Text("Can't load templates").font(.headline)
                    Text(message).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("Try again") { Task { await reload() } }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal)
            case .loaded:
                Text(searchText.isEmpty ? "No templates yet" : "No results").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 80)
            default:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        } else {
            let columns = MasonryColumns.split(catalog.templates)
            HStack(alignment: .top, spacing: 12) {
                column(columns.left)
                column(columns.right)
            }
            .padding(.horizontal)

            if catalog.hasMore {
                ProgressView().frame(maxWidth: .infinity).padding()
                    .onAppear { Task { await catalog.loadMore() } }
            }
        }
    }

    private func column(_ templates: [APITemplate]) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(templates) { template in
                TemplateCard(template: template) {
                    viewer = ViewerRequest(templates: catalog.templates, startID: template.id)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
