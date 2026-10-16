import SwiftUI

struct AccountView: View {
    @AppStorage("playbackMetricsArmed") private var playbackMetricsArmed = false
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    /// Last balance the server gave (-1 = never); shown at once and refreshed below, so the row is never empty.
    @AppStorage(CreditsView.lastBalanceKey) private var lastBalance = -1

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                        .frame(width: 56, height: 56)
                        .overlay(Text("N").font(.title2.bold()).foregroundColor(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Neonix Account").font(.body.weight(.semibold))
                        Text("mankhb2k@neonix.video")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Account") {
                Label("Edit profile", systemImage: "person.crop.circle")
                NavigationLink {
                    CreditsView()
                } label: {
                    HStack {
                        Label("Credits", systemImage: "bitcoinsign.circle")
                        Spacer()
                        Text(verbatim: lastBalance >= 0 ? String(lastBalance) : "—").foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("row-credits")
                NavigationLink {
                    StorageView()
                } label: {
                    Label("Storage", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("row-storage")
            }

            Section("Preferences") {
                Label("Notifications", systemImage: "bell")
                NavigationLink {
                    AppearanceView()
                } label: {
                    HStack {
                        Label("Appearance", systemImage: "paintbrush")
                        Spacer()
                        Text(appearance.title).foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    LanguageView()
                } label: {
                    HStack {
                        Label("Language", systemImage: "globe")
                        Spacer()
                        Group {
                            if let name = language.nativeName { Text(verbatim: name) } else { Text("System") }
                        }
                        .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    PrivacyTermsView()
                } label: {
                    Label("Privacy & Terms", systemImage: "lock")
                }
            }

            Section("Support") {
                NavigationLink {
                    HelpCenterView()
                } label: {
                    Label("Help Center", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("Send feedback", systemImage: "envelope")
                }
            }

            Section {
                Toggle("Playback metrics HUD", isOn: $playbackMetricsArmed)
                NavigationLink("Templates & credits (API)") { TemplatesDebugView() }
                NavigationLink("Design Lab") { DesignLabView() }
            } header: {
                Text("Developer")
            } footer: {
                Text("Shows a metrics pill in the editor. Start/stop a recorded run there and share the CSV. See PLAYBACK_PIPELINE.md.")
            }
        }
        .task {   // refreshed each time the tab appears
            if let balance = try? await NeonixAPIClient(config: .current).balance() { lastBalance = balance }
        }
    }
}
