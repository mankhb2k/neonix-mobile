import Charts
import SwiftUI

/// Account › Storage, laid out like Telegram's: a ring of what the app takes, rows you tick, one "Clear Selected"
/// button under them and a popup to confirm. Media can't be ticked: the Folder tab has no stored projects yet
/// (see `ProjectsView`), so there is no safe way to remove it from here.
struct StorageView: View {
    private enum Slice: CaseIterable, Identifiable {
        case media, templates, cache, other
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .media: return "Projects & media"
            case .templates: return "Downloaded templates"
            case .cache: return "Cache"
            case .other: return "Other"
            }
        }

        var color: Color {
            switch self {
            case .media: return .blue
            case .templates: return .orange
            case .cache: return .purple
            case .other: return .gray
            }
        }

        var isClearable: Bool { self == .templates || self == .cache }

        func bytes(in snapshot: StorageSnapshot) -> Int64 {
            switch self {
            case .media: return snapshot.media
            case .templates: return snapshot.templates
            case .cache: return snapshot.cache
            case .other: return snapshot.other
            }
        }
    }

    @State private var snapshot: StorageSnapshot?
    @State private var selected: Set<Slice> = [.templates, .cache]
    @State private var confirming = false

    private var selectedBytes: Int64 {
        guard let snapshot else { return 0 }
        return selected.reduce(0) { $0 + $1.bytes(in: snapshot) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ring
                header
                card
                clearButton
                Text("Cache and downloaded templates are made again when needed, so clearing them is safe. Your media is not removed here.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Clear Storage?", isPresented: $confirming) {
            Button("Clear", role: .destructive) { Task { await clearSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if selected.contains(.templates) {
                Text("Cache and downloaded templates are made again when needed. Templates you own stay yours. Your media is not removed.")
            } else {
                Text("Cache is made again when needed. Your media is not removed.")
            }
        }
    }

    // MARK: Pieces

    private var ring: some View {
        let total = snapshot?.total ?? 0
        return Chart {
            if let snapshot, total > 0 {
                ForEach(Slice.allCases) { slice in
                    SectorMark(angle: .value("Size", slice.bytes(in: snapshot)), innerRadius: .ratio(0.64), angularInset: 1)
                        .foregroundStyle(slice.color)
                }
            } else {
                SectorMark(angle: .value("Size", 1), innerRadius: .ratio(0.64)).foregroundStyle(Color(.systemGray5))
            }
        }
        .frame(width: 190, height: 190)
        .overlay {
            Text(verbatim: format(total))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .redacted(reason: snapshot == nil ? .placeholder : [])
                .accessibilityIdentifier("storage-total")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Storage Usage").font(.title3.weight(.semibold))
            if let snapshot, let free = snapshot.deviceFree {
                let share = Double(snapshot.total) / Double(max(snapshot.total + free, 1))
                Text("Neonix uses \(percentText(share)) of your free disk space.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Capsule().fill(Color(.systemGray5)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(Color.blue).frame(width: max(proxy.size.width * share, 4))
                        }
                    }
                    .padding(.horizontal, 24)
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Slice.allCases) { slice in
                row(slice)
                if slice != Slice.allCases.last { Divider().padding(.leading, 56) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var clearButton: some View {
        Button {
            confirming = true
        } label: {
            Text("Clear")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedBytes > 0 ? Color.blue : Color(.systemGray4), in: Capsule())
                .foregroundColor(.white)
        }
        .disabled(selectedBytes == 0)
        .accessibilityIdentifier("storage-clear")
    }

    private func row(_ slice: Slice) -> some View {
        let bytes = snapshot.map { slice.bytes(in: $0) }
        let total = max(snapshot?.total ?? 0, 1)
        return Button {
            guard slice.isClearable else { return }
            if selected.contains(slice) { selected.remove(slice) } else { selected.insert(slice) }
        } label: {
            HStack(spacing: 12) {
                marker(slice)
                Text(slice.title).foregroundColor(.primary)
                if let bytes {
                    Text(verbatim: percentText(Double(bytes) / Double(total))).foregroundColor(.secondary)
                }
                Spacer()
                Text(verbatim: bytes.map(format) ?? "—").foregroundColor(.primary).monospacedDigit()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!slice.isClearable)
        .accessibilityIdentifier("storage-select-\(slice)")
        .accessibilityAddTraits(slice.isClearable && selected.contains(slice) ? .isSelected : [])
    }

    /// A filled circle in the slice's colour; ticked when it will be cleared, plain when it can't be cleared.
    private func marker(_ slice: Slice) -> some View {
        let on = selected.contains(slice)
        return ZStack {
            Circle().fill(slice.isClearable && !on ? Color.clear : slice.color)
            Circle().stroke(slice.color, lineWidth: 2)
            if slice.isClearable && on {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundColor(.white)
            }
        }
        .frame(width: 26, height: 26)
    }

    // MARK: Data

    private func format(_ bytes: Int64?) -> String {
        ByteCountFormatter.string(fromByteCount: bytes ?? 0, countStyle: .file)
    }

    private func percentText(_ fraction: Double) -> String {
        let percent = fraction * 100
        return percent > 0 && percent < 0.1 ? "<0.1%" : String(format: "%.1f%%", percent)
    }

    private func refresh() async {
        snapshot = await Task.detached { StorageUsage.measure() }.value
    }

    private func clearSelected() async {
        let clearCache = selected.contains(.cache)
        let clearTemplates = selected.contains(.templates)
        await Task.detached {
            if clearCache { StorageUsage.clearCache() }
            if clearTemplates { StorageUsage.removeDownloadedTemplates() }
        }.value
        await refresh()
    }
}
