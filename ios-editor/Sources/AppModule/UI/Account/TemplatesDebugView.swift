import SwiftUI

/// Developer screen for the neonix-api integration: balance, template catalogue, package download +
/// unpack, and the credit-spending export call. Not the end-user template browser.
struct TemplatesDebugView: View {
    @State private var client = NeonixAPIClient(config: .current)
    @State private var balance: Int?
    @State private var templates: [APITemplate] = []
    @State private var installed: [String: TemplatePackage] = [:]
    @State private var log: [String] = []
    @State private var isLoading = false

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("API", value: client.config.baseURL.absoluteString)
                LabeledContent("Credits", value: balance.map(String.init) ?? "—")
                #if DEBUG
                Button("Add 20 test credits") { run("grant") { balance = try await client.grantTestCredits(20) } }
                #endif
                Button("Reload") { reload() }.disabled(isLoading)
            }

            Section("Templates") {
                if templates.isEmpty { Text(isLoading ? "Loading…" : "No templates").foregroundColor(.secondary) }
                ForEach(templates) { template in row(template) }
            }

            if !log.isEmpty {
                Section("Log") { ForEach(Array(log.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()) } }
            }
        }
        .navigationTitle("Templates (API)")
        .task { reload() }
    }

    @ViewBuilder private func row(_ template: APITemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(template.title).font(.headline)
                Spacer()
                Text("\(template.creditCost) credits").font(.subheadline).foregroundColor(.secondary)
            }
            Text(summary(template)).font(.caption).foregroundColor(.secondary)

            if let package = installed[template.id] {
                Text(package.manifest.slots.map { "\($0.kind): \($0.label)" }.joined(separator: " · "))
                    .font(.caption)
                Button("Export (spend credits)") { export(template) }
            } else {
                Button("Download & unpack") { download(template) }
            }
        }
        .padding(.vertical, 4)
    }

    private func summary(_ template: APITemplate) -> String {
        var parts = ["by \(template.creator.name ?? template.creator.id)"]
        if let v = template.version {
            if let slots = v.slotCount { parts.append("\(slots) slots") }
            if let w = v.width, let h = v.height { parts.append("\(w)×\(h)") }
            if let ms = v.durationMs { parts.append(String(format: "%.0f s", Double(ms) / 1000)) }
            if let bytes = v.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func reload() {
        run("reload") {
            balance = try await client.balance()
            templates = try await client.templates().items
        }
    }

    private func download(_ template: APITemplate) {
        run("download \(template.title)") {
            let info = try await client.packageInfo(templateId: template.id)
            let zip = try await client.downloadPackage(info)
            installed[template.id] = try TemplateInstaller.install(zip: zip, templateId: template.id, version: info.version)
            log.append("unpacked v\(info.version), \(zip.count) bytes")
        }
    }

    /// The first tap buys the template, every later one is free.
    private func export(_ template: APITemplate) {
        run("export \(template.title)") {
            let result = try await client.createExport(templateId: template.id)
            balance = result.balance
            log.append(result.charged ? "bought: \(result.creditsCharged) credits" : "already owned: free")
        }
    }

    private func run(_ name: String, _ work: @escaping () async throws -> Void) {
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do { try await work() }
            catch let error as APIError where error.isInsufficientCredits { log.append("\(name): not enough credits") }
            catch { log.append("\(name): \(error.localizedDescription)") }
        }
    }
}
