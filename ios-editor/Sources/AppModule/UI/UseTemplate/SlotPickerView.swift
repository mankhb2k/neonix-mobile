import Photos
import SwiftUI

/// "Pick your media": library grid on top, the template's slots in a tray at the bottom. Tapping a photo/video
/// fills the current slot and moves to the next empty one; Next is enabled once every required slot is filled.
struct SlotPickerView: View {
    let templateTitle: String
    let onClose: () -> Void
    let onNext: ([PickedMedia?], [TemplateManifest.Slot]) -> Void

    @State private var library = PhotoLibrary()
    /// Owned by the flow, so the picks survive going to the result screen and coming back.
    let model: SlotPickerModel
    @State private var cropping: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(model: SlotPickerModel, templateTitle: String, onClose: @escaping () -> Void, onNext: @escaping ([PickedMedia?], [TemplateManifest.Slot]) -> Void) {
        self.model = model
        self.templateTitle = templateTitle
        self.onClose = onClose
        self.onNext = onNext
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch library.access {
            case .unknown: ProgressView().frame(maxHeight: .infinity)
            case .denied: deniedView
            case .ready: grid
            }
            tray
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await library.requestAccess() }
        .fullScreenCover(item: Binding(get: { cropping.map(CropTarget.init) }, set: { cropping = $0?.index })) { target in
            if let media = model.slots[target.index].media {
                SlotCropView(library: library, media: media, slotMs: model.slots[target.index].durationMs) { start in
                    model.setCrop(slot: target.index, startMs: start)
                    cropping = nil
                } onCancel: { cropping = nil }
            }
        }
    }

    private struct CropTarget: Identifiable { let index: Int; var id: Int { index } }

    // MARK: Header + grid

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onClose) { Image(systemName: "xmark").font(.title3) }
                Spacer()
                Text(templateTitle).font(.headline)
                Spacer()
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(.horizontal)
            Picker("Show", selection: $library.filter) {
                ForEach(PhotoLibrary.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<library.count, id: \.self) { index in
                    if let asset = library.asset(at: index) {
                        AssetCell(library: library, asset: asset, dimmed: !model.canUse(asset)) { model.pick(asset) }
                    }
                }
            }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundColor(.secondary)
            Text("Allow access to your photos").font(.headline)
            Text("Neonix needs your photos and videos to fill the template.").font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    // MARK: Slot tray

    private var tray: some View {
        VStack(spacing: 10) {
            if let message = model.message {
                Text(message).font(.footnote).foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.slots.enumerated()), id: \.element.id) { index, state in
                        SlotChip(library: library, index: index, state: state, isCurrent: model.currentIndex == index,
                                 needsCrop: model.needsCrop(slot: index),
                                 onSelect: { model.select(slot: index) },
                                 onClear: { model.clear(slot: index) },
                                 onCrop: { cropping = index })
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Text(hint).font(.footnote).foregroundColor(.secondary)
                Spacer()
                Button {
                    onNext(model.slots.map(\.media), model.slots.map(\.slot))
                } label: {
                    Text("Next").fontWeight(.semibold).padding(.horizontal, 28).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canContinue)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    private var hint: String {
        if let current = model.current {
            return "Slot \(model.currentIndex + 1): \(String(format: "%.1f", Double(current.durationMs) / 1000)) s. Photos or videos of at least that length."
        }
        return ""
    }
}

struct AssetCell: View {
    let library: PhotoLibrary
    let asset: PHAsset
    let dimmed: Bool
    /// Shown on a dimmed cell ("Too short").
    var dimmedLabel: String?
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            Color(.tertiarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if asset.mediaType == .video {
                        Text(clock(asset.duration))
                            .font(.caption2.weight(.semibold).monospacedDigit()).foregroundColor(.white)
                            .padding(4).shadow(radius: 2)
                    }
                }
                .overlay {
                    if dimmed {
                        Color.black.opacity(0.55)
                            .overlay { if let dimmedLabel { Text(dimmedLabel).font(.caption.weight(.semibold)).foregroundColor(.white) } }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assetCell")
        .task(id: asset.localIdentifier) { image = await library.thumbnail(for: asset, side: 240) }
    }
}

private struct SlotChip: View {
    let library: PhotoLibrary
    let index: Int
    let state: SlotPickerModel.SlotState
    let isCurrent: Bool
    let needsCrop: Bool
    let onSelect: () -> Void
    let onClear: () -> Void
    let onCrop: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemBackground))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            Text("\(index + 1)").font(.caption2.weight(.bold)).padding(5).foregroundColor(.white).shadow(radius: 2)
            Text(String(format: "%.1fs", Double(state.durationMs) / 1000))
                .font(.caption.weight(.semibold)).foregroundColor(state.media == nil ? .primary : .white).shadow(radius: state.media == nil ? 0 : 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isCurrent ? Color.primary : .clear, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if state.media != nil {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)) }.padding(3)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if needsCrop {
                Button(action: onCrop) {
                    Image(systemName: "crop").font(.caption2.weight(.bold)).foregroundColor(.white)
                        .padding(5).background(Color.accentColor, in: Circle())
                }
                .padding(4)
                .accessibilityIdentifier("slotCrop-\(index)")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slot \(index + 1)")
        .accessibilityValue(state.media == nil ? "empty" : "filled")
        .accessibilityIdentifier("slotChip-\(index)")
        .accessibilityAddTraits(.isButton)
        .onTapGesture(perform: onSelect)
        .task(id: state.media?.asset.localIdentifier) {
            if let asset = state.media?.asset { image = await library.thumbnail(for: asset, side: 160) } else { image = nil }
        }
    }
}

func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%02d:%02d", total / 60, total % 60)
}
