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
        Topic(title: "Templates", entries: [
            Entry(question: "How do I make a video from a template?",
                  answer: "Open a template on Home, tap use, then fill each slot with a photo or video. Change the texts and music if you like, then tap Export."),
            Entry(question: "Why was my video clip refused for a slot?",
                  answer: "A video must be at least as long as its slot. A longer video is cropped to the slot's length, and you choose where it starts."),
            Entry(question: "Can I change the template's text and music?",
                  answer: "Yes. The result screen has a Text section with the template's texts and an Audio switch for the music."),
        ]),
        Topic(title: "Credits", entries: [
            Entry(question: "What are credits for?",
                  answer: "Credits unlock templates. A template is bought once, with its first export."),
            Entry(question: "Do I pay every time I export?",
                  answer: "No. After the first export of a template it is yours: later exports of it are free."),
            Entry(question: "How do I get a refund for credits?",
                  answer: "Credit purchases go through the App Store, so refunds are handled by Apple at reportaproblem.apple.com. Credits that were refunded are taken back from your balance."),
        ]),
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
