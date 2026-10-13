import SwiftUI

/// The sticker picker (user 2026-10-12): the Filter lab's "B Grid+" layout - a sheet that opens at 340 pt and can be pulled
/// up to browse the whole library; category chips, a 4-column grid, tap a sticker to put it on the canvas at the playhead.
/// The stage stays live (and tappable) at the small size. The pictures come from the API / R2 through `StickerStore`.
struct StickerSheet: View {
    let store: StickerStore
    let onPick: (APIStickerCatalogue.Sticker) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: String?   // nil = All

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if let catalogue = store.catalogue {
                    chips(catalogue)
                    grid(catalogue)
                } else {
                    placeholder
                }
            }
            .padding(.top, 4)
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("stickerDone")
                }
            }
        }
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(340)))
        .task { await store.load() }
    }

    // MARK: Parts

    private func chips(_ catalogue: APIStickerCatalogue) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", id: nil)
                ForEach(catalogue.categories) { chip($0.title, id: $0.id) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, id: String?) -> some View {
        let on = category == id
        return Button { category = id } label: {
            Text(title).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stickerChip-\(id ?? "all")")
    }

    private func grid(_ catalogue: APIStickerCatalogue) -> some View {
        let stickers = catalogue.stickers.filter { category == nil || $0.category == category }
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(stickers) { sticker in
                    Button { onPick(sticker) } label: {
                        StickerCell(sticker: sticker, store: store)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stickerCell-\(sticker.id)")
                    .accessibilityLabel(sticker.name)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            Text("Emoji art: Fluent Emoji by Microsoft, MIT licence")
                .font(.caption2).foregroundColor(.secondary).padding(.bottom, 12)
        }
        .accessibilityIdentifier("stickerGrid")
    }

    @ViewBuilder private var placeholder: some View {
        Spacer()
        switch store.state {
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundColor(.secondary)
                Text("The stickers could not be loaded").font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Button("Try again") { Task { await store.load() } }.buttonStyle(.bordered).accessibilityIdentifier("stickerRetry")
            }
        default:
            ProgressView().accessibilityIdentifier("stickerLoading")
        }
        Spacer()
    }
}

/// One square cell: the sticker's picture (loaded lazily, cached), on a light tile.
private struct StickerCell: View {
    let sticker: APIStickerCatalogue.Sticker
    let store: StickerStore
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: sticker.id) { image = await store.image(for: sticker) }
    }
}
