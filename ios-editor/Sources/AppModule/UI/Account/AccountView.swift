import SwiftUI
import Observation
import StoreKit

struct AccountView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
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
                showingSignIn = false
            }
        }
        .task {   // refreshed each time the tab appears
            await account.restore()
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
                        Text(account.email ?? (account.isSignedIn ? "Google account" : "Sign in to manage your account"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if account.isSignedIn {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await account.signOut()
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
                NavigationLink {
                    DonateView()
                } label: {
                    accountLabel("Donate", symbol: "heart.fill")
                }
                .accessibilityIdentifier("row-donate")
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

@Observable @MainActor
final class DonationStore {
    static let productIDs = [
        "com.neonix.editor.donate.small",
        "com.neonix.editor.donate.medium",
        "com.neonix.editor.donate.large",
    ]

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchasingID: String?
    var message: String?
    var didDonate = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted {
                (Self.productIDs.firstIndex(of: $0.id) ?? .max) < (Self.productIDs.firstIndex(of: $1.id) ?? .max)
            }
            listenForTransactionsIfNeeded()
        } catch {
            message = "Donation options couldn't be loaded. Please try again later."
        }
    }

    func donate(_ product: Product) async {
        guard purchasingID == nil else { return }
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "The App Store couldn't verify this purchase."
                    return
                }
                await transaction.finish()
                didDonate = true
            case .pending:
                message = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                message = "The purchase couldn't be completed. Please try again."
            }
        } catch {
            message = "The purchase couldn't be completed. Please try again."
        }
    }

    private func listenForTransactionsIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      Self.productIDs.contains(transaction.productID) else { continue }
                await transaction.finish()
                didDonate = true
            }
        }
    }
}

struct DonateView: View {
    @State private var store = DonationStore()

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AccountGradientIcon(systemName: "heart.fill", size: 58)
                    Text("Support Neonix")
                        .font(.title3.weight(.semibold))
                    Text("Your optional tip helps fund ongoing development. Neonix's editing features remain available to everyone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .listRowBackground(Color.clear)
            }

            Section {
                if store.isLoading && store.products.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if store.products.isEmpty {
                    Text("Donation options are unavailable right now.")
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await store.load() } }
                } else {
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task { await store.donate(product) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "heart")
                                    .foregroundStyle(.tint)
                                    .frame(width: 26)
                                Text(product.displayName.isEmpty ? "One-time tip" : product.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if store.purchasingID == product.id {
                                    ProgressView()
                                } else {
                                    Text(product.displayPrice)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(store.purchasingID != nil)
                        .accessibilityIdentifier("donate-\(product.id)")
                    }
                }
            } header: {
                Text("Choose a tip")
            } footer: {
                Text("Tips are optional, one-time purchases processed by the App Store.")
            }
        }
        .navigationTitle("Donate")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .alert("Thank you", isPresented: $store.didDonate) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("Thanks for supporting Neonix development.")
        }
        .alert("Purchase", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK", role: .cancel) { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
