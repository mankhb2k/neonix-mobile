import Photos
import SwiftUI

/// What a picked photo or video is for: swap the media of this clip (`ReplaceClipCommand`). `minVideoMs`: a video shorter than the footage the
/// clip plays is dimmed (0 for a photo clip).
struct MediaPickerPurpose: Identifiable, Equatable {
    let layerId: String
    let minVideoMs: Double
    var id: String { "replace-\(layerId)" }
    var title: String { "Replace" }
}

/// The library grid the editor's Replace and Overlay tools use (All / Videos / Photos): the same cells as the template slot picker. For Replace a
/// video shorter than the clip's footage is dimmed (the clip would run out of picture); a photo always fits.
struct EditorMediaPickerView: View {
    let purpose: MediaPickerPurpose
    let onPick: (PickedMedia) -> Void
    let onCancel: () -> Void

    @State private var library = PhotoLibrary()
    @State private var message: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var minVideoMs: Double { purpose.minVideoMs }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Show", selection: $library.filter) {
                ForEach(PhotoLibrary.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)

            if let message {
                Text(message).font(.subheadline.weight(.medium)).foregroundColor(.orange)
                    .frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.orange.opacity(0.12))
            }

            switch library.access {
            case .unknown: ProgressView().frame(maxHeight: .infinity)
            case .denied: Text("Allow access to your photos in Settings").foregroundColor(.secondary).frame(maxHeight: .infinity)
            case .ready:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(0..<library.count, id: \.self) { index in
                            if let asset = library.asset(at: index) {
                                AssetCell(library: library, asset: asset, dimmed: !canUse(asset), dimmedLabel: "Too short") { pick(asset) }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("mediaPickerGrid")
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await library.requestAccess() }
    }

    /// A big Cancel (a 44 pt capsule, 18 pt semibold - the old plain text button was too small to hit or read), the title and what the picker is for.
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("Cancel").font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mediaPickerCancel")
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(purpose.title).font(.title3.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: 92, height: 44)   // balances Cancel so the title stays centred
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var subtitle: String {
        minVideoMs > 0 ? "Photos, or videos ≥ \(String(format: "%.1f", minVideoMs / 1000)) s" : "Pick a photo or video"
    }

    private func canUse(_ asset: PHAsset) -> Bool {
        asset.mediaType != .video || asset.duration * 1000 >= minVideoMs
    }

    private func pick(_ asset: PHAsset) {
        guard canUse(asset) else {
            message = "Pick a video of at least \(String(format: "%.1f", minVideoMs / 1000)) s for this clip"
            return
        }
        onPick(PickedMedia(asset: asset, kind: asset.mediaType == .video ? .video : .photo, durationMs: asset.duration * 1000))
    }
}
