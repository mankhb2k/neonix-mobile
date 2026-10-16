import SwiftUI

/// Credits: balance and history from the API. Buying packs (StoreKit) is the next step, see the footer.
struct CreditsView: View {
    static let lastBalanceKey = "lastCreditBalance"

    @AppStorage(lastBalanceKey) private var lastBalance = -1
    @State private var client = NeonixAPIClient(config: .current)
    @State private var store = CreditStore()
    @State private var balance: Int?
    @State private var entries: [APILedgerEntry] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text("\(balance ?? 0) credits")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .redacted(reason: balance == nil && !failed ? .placeholder : [])
                        .accessibilityIdentifier("credits-balance")
                    Text("Credits unlock templates, one time each.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                ForEach(store.packs) { pack in packRow(pack) }
                if store.packs.isEmpty {
                    Text(store.isLoading ? "Loading…" : "No credit packs available right now.").foregroundColor(.secondary)
                }
                #if DEBUG
                Button("Add 20 test credits") { Task { await grant() } }
                #endif
            } header: {
                Text("Get more credits")
            } footer: {
                switch store.failure {
                case .purchaseFailed: Text("The purchase didn't go through. If you were charged, your credits will arrive shortly.")
                case .pending: Text("Your purchase is waiting for approval.")
                case .loadFailed, nil: EmptyView()
                }
            }

            if failed {
                Section {
                    Text("Couldn't load your credits.").foregroundColor(.secondary)
                    Button("Try again") { Task { await reload() } }
                }
            }

            Section("History") {
                if entries.isEmpty && !isLoading && !failed {
                    Text("No activity yet.").foregroundColor(.secondary)
                }
                ForEach(entries) { entry in row(entry) }
                if nextCursor != nil {
                    Button("Load more") { Task { await loadMore() } }.disabled(isLoading)
                }
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            store.onBalance = { newBalance in
                balance = newBalance
                lastBalance = newBalance
                Task { await reload() }
            }
            await reload()
            await store.start()
        }
    }

    private func packRow(_ pack: CreditStore.Pack) -> some View {
        Button {
            Task { await store.buy(pack) }
        } label: {
            HStack {
                Text("\(pack.credits) credits").foregroundColor(.primary)
                Spacer()
                if store.buyingId == pack.id {
                    ProgressView()
                } else if let product = pack.product {
                    Text(verbatim: product.displayPrice).foregroundColor(.accentColor).fontWeight(.semibold)
                } else {
                    Text("Unavailable").foregroundColor(.secondary)
                }
            }
        }
        .disabled(pack.product == nil || store.buyingId != nil)
        .accessibilityIdentifier("pack-\(pack.credits)")
    }

    private func row(_ entry: APILedgerEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: entry.reason))
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(verbatim: (entry.delta > 0 ? "+" : "") + String(entry.delta))
                .font(.body.monospacedDigit())
                .foregroundColor(entry.delta > 0 ? .green : .primary)
        }
    }

    static func title(for reason: String) -> LocalizedStringKey {
        switch reason {
        case "purchase": return "Credits purchased"
        case "template_purchase": return "Template unlocked"
        case "export": return "Export"
        case "export_refund": return "Export refunded"
        case "iap_refund": return "Purchase refunded"
        case "grant": return "Bonus credits"
        default: return "Other"
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let newBalance = client.balance()
            let page = try await client.ledger()
            balance = try await newBalance
            lastBalance = balance ?? lastBalance
            entries = page.items
            nextCursor = page.nextCursor
            failed = false
        } catch {
            failed = true
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await client.ledger(cursor: cursor) {
            entries += page.items
            nextCursor = page.nextCursor
        }
    }

    #if DEBUG
    private func grant() async {
        if (try? await client.grantTestCredits(20)) != nil { await reload() }
    }
    #endif
}
