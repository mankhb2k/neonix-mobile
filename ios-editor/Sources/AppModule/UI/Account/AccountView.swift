import SwiftUI

struct AccountView: View {
    @AppStorage("playbackMetricsArmed") private var playbackMetricsArmed = false

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
                Label("Subscription", systemImage: "star.circle")
                Label("Storage", systemImage: "externaldrive")
            }

            Section("Preferences") {
                Label("Notifications", systemImage: "bell")
                Label("Appearance", systemImage: "paintbrush")
                Label("Privacy", systemImage: "lock")
            }

            Section("Support") {
                Label("Help Center", systemImage: "questionmark.circle")
                Label("Send feedback", systemImage: "envelope")
            }

            Section {
                Toggle("Playback metrics HUD", isOn: $playbackMetricsArmed)
            } header: {
                Text("Developer")
            } footer: {
                Text("Shows a metrics pill in the editor. Start/stop a recorded run there and share the CSV. See PLAYBACK_PIPELINE.md.")
            }
        }
    }
}
