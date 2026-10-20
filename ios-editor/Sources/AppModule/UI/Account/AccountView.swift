import SwiftUI

struct AccountView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    /// Last balance the server gave (-1 = never); shown at once and refreshed below, so the row is never empty.
    @AppStorage(CreditsView.lastBalanceKey) private var lastBalance = -1
    @StateObject private var account = GoogleAccountSession()
    @State private var showingSignIn = false

    var body: some View {
        Group {
            if account.isSignedIn {
                signedInAccount
            } else {
                GuestAccountView {
                    showingSignIn = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingSignIn) {
            GoogleLoginView(account: account) {
                if let balance = try? await NeonixAPIClient(config: .current).balance() {
                    lastBalance = balance
                }
                showingSignIn = false
            }
        }
        .task {   // refreshed each time the tab appears
            await account.restore()
            if let balance = try? await NeonixAPIClient(config: .current).balance() { lastBalance = balance }
        }
    }

    private var signedInAccount: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                        .frame(width: 56, height: 56)
                        .overlay {
                            if let avatar = account.profile?.avatarUrl {
                                AsyncImage(url: avatar) { image in image.resizable().scaledToFill() } placeholder: {
                                    Text("N").font(.title2.bold()).foregroundColor(.white)
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            } else {
                                Text("N").font(.title2.bold()).foregroundColor(.white)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.profile?.displayName ?? (account.isSignedIn ? "Neonix Account" : "Guest"))
                            .font(.body.weight(.semibold))
                        Text(account.email ?? (account.isSignedIn ? "Google account" : "Sign in to export and manage credits"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if account.isSignedIn {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await account.signOut()
                            lastBalance = -1
                        }
                    }
                    .disabled(account.isLoading)
                }
                if let message = account.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Account") {
                accountLabel("Edit profile", symbol: "person.crop.circle.fill")
                NavigationLink {
                    CreditsView()
                } label: {
                    HStack {
                        accountLabel("Credits", symbol: "bitcoinsign.circle.fill")
                        Spacer()
                        Text(verbatim: lastBalance >= 0 ? String(lastBalance) : "—").foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("row-credits")
                NavigationLink {
                    StorageView()
                } label: {
                    accountLabel("Storage", symbol: "externaldrive.fill")
                }
                .accessibilityIdentifier("row-storage")
            }

            Section("Preferences") {
                accountLabel("Notifications", symbol: "bell.fill")
                NavigationLink {
                    AppearanceView()
                } label: {
                    HStack {
                        accountLabel("Appearance", symbol: "paintbrush.pointed.fill")
                        Spacer()
                        Text(appearance.title).foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    LanguageView()
                } label: {
                    HStack {
                        accountLabel("Language", symbol: "globe.americas.fill")
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
                    accountLabel("Privacy & Terms", symbol: "lock.fill")
                }
            }

            Section("Support") {
                NavigationLink {
                    HelpCenterView()
                } label: {
                    accountLabel("Help Center", symbol: "questionmark.circle.fill")
                }
                NavigationLink {
                    FeedbackView()
                } label: {
                    accountLabel("Send feedback", symbol: "envelope.fill")
                }
            }

            #if DEBUG
            Section {
                NavigationLink {
                    DesignLabView()
                } label: {
                    HStack {
                        accountLabel("Design Lab", symbol: "slider.horizontal.3")
                        Spacer()
                        Text("DEV")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(Color(red: 0.34, green: 0.35, blue: 0.86))
                    }
                }
                .accessibilityIdentifier("developer-design-lab")
            } header: {
                Text("Developer")
            } footer: {
                Text("Experiments on fake data. Nothing here touches projects or the server.")
            }
            #endif
        }
    }

    private func accountLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            AccountGradientIcon(systemName: symbol, size: 32)
            Text(title)
        }
    }
}
