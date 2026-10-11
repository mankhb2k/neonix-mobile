import Photos
import SwiftUI

/// Replaces the media of one slot: the same library grid, filtered by that slot's rule (a video must be at least
/// as long as the slot). Used from the template result screen.
struct SingleSlotPickerView: View {
    let slot: TemplateManifest.Slot
    let onPick: (PickedMedia) -> Void
    let onCancel: () -> Void

    @State private var library = PhotoLibrary()
    @State private var message: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private var slotMs: Int { slot.durationMs ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Text("Replace \(slot.label)").font(.headline)
                    Spacer()
                    Color.clear.frame(width: 50, height: 24)
                }
                .padding(.horizontal)
                Picker("Show", selection: $library.filter) {
                    ForEach(PhotoLibrary.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .padding(.vertical, 10)

            if let message {
                Text(message).font(.footnote).foregroundColor(.orange).padding(.bottom, 6)
            } else {
                Text("Photos, or videos of at least \(String(format: "%.1f", Double(slotMs) / 1000)) s")
                    .font(.footnote).foregroundColor(.secondary).padding(.bottom, 6)
            }

            switch library.access {
            case .unknown: ProgressView().frame(maxHeight: .infinity)
            case .denied: Text("Allow access to your photos in Settings").foregroundColor(.secondary).frame(maxHeight: .infinity)
            case .ready:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(0..<library.count, id: \.self) { index in
                            if let asset = library.asset(at: index) {
                                AssetCell(library: library, asset: asset, dimmed: !canUse(asset)) { pick(asset) }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await library.requestAccess() }
    }

    private func canUse(_ asset: PHAsset) -> Bool {
        SlotRules.canUse(asset.mediaType == .video ? .video : .photo, durationMs: asset.duration * 1000, forSlotMs: slotMs)
    }

    private func pick(_ asset: PHAsset) {
        let kind: MediaKind = asset.mediaType == .video ? .video : .photo
        guard canUse(asset) else {
            message = "Pick a video of at least \(String(format: "%.1f", Double(slotMs) / 1000)) s for this slot"
            return
        }
        onPick(PickedMedia(asset: asset, kind: kind, durationMs: asset.duration * 1000))
    }
}
