import SafariServices
import SwiftUI

/// Legal pages, opened in an in-app Safari sheet so the text can change without an app release.
struct PrivacyTermsView: View {
    /// Placeholder addresses: set the real pages before App Store review (Privacy Policy is required there).
    static let privacyURL = URL(string: "https://neonix.video/privacy")!
    static let termsURL = URL(string: "https://neonix.video/terms")!

    @State private var page: LegalPage?

    var body: some View {
        List {
            Section {
                row("Privacy Policy", systemImage: "hand.raised", page: LegalPage(url: Self.privacyURL))
                row("Terms of Use", systemImage: "doc.text", page: LegalPage(url: Self.termsURL))
            }
        }
        .navigationTitle("Privacy & Terms")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $page) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    private func row(_ title: String, systemImage: String, page: LegalPage) -> some View {
        Button {
            self.page = page
        } label: {
            HStack {
                Label(title, systemImage: systemImage).foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote).foregroundColor(.secondary)
            }
        }
    }
}

private struct LegalPage: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
