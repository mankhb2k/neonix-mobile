import SwiftUI

/// In-app FAQ (no backend): grouped questions, searchable, with a way through to Send feedback.
struct HelpCenterView: View {
    struct Entry: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    struct Topic: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    static let topics: [Topic] = [
        Topic(title: "Editing", entries: [
            Entry(question: "How do I trim or split a clip?",
                  answer: "Tap a clip on the timeline. The bottom row then shows that clip's tools, including Split. Drag a clip's handles to trim it."),
            Entry(question: "How do I zoom the timeline?",
                  answer: "Pinch the timeline. The playhead stays in the centre while you zoom."),
            Entry(question: "A tool says \"coming soon\".",
                  answer: "Some tools are not built yet and only show that message. They will arrive in later versions."),
        ]),
        Topic(title: "Your data", entries: [
            Entry(question: "The app can't see my photos or microphone.",
                  answer: "Open the Settings app, choose Neonix, and allow Photos or Microphone access."),
        ]),
        Topic(title: "Support Neonix", entries: [
            Entry(question: "How does Donate work?",
                  answer: "Donations are optional one-time tips that support Neonix development. They do not unlock app features."),
        ]),
    ]

    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @State private var search = ""

    private var visibleTopics: [Topic] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return Self.topics }
        return Self.topics.compactMap { topic in
            let hits = topic.entries.filter {
                language.string($0.question).localizedCaseInsensitiveContains(term) || language.string($0.answer).localizedCaseInsensitiveContains(term)
            }
            return hits.isEmpty ? nil : Topic(title: topic.title, entries: hits)
        }
    }

    var body: some View {
        List {
            ForEach(visibleTopics) { topic in
                Section(language.string(topic.title)) {
                    ForEach(topic.entries) { entry in
                        DisclosureGroup(language.string(entry.question)) {
                            Text(language.string(entry.answer))
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            if visibleTopics.isEmpty {
                Section { Text("No results for \"\(search)\".").foregroundColor(.secondary) }
            }
            Section {
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("Contact us", systemImage: "envelope")
                }
            } footer: {
                Text("Can't find your answer? Send us a message.")
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic))
        .navigationTitle("Help Center")
        .navigationBarTitleDisplayMode(.inline)
    }
}
