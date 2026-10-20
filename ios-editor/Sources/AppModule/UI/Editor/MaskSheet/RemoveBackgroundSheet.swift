import SwiftUI

/// Remove BG for a photo (Phase 1; CLAUDE.md "Remove BG"): the clip row's Remove BG replaces the bottom row with `RemoveBackgroundToolRow` (None, Auto removal,
/// Choose subject); the picked tile shows an adjust icon whose tap opens this popup - Feather, Invert and, for Choose subject, the picture to tap the subject on.
/// Every change is live; the shell makes the whole session one undo step (shared with the Mask tool's bookkeeping).
struct RemoveBackgroundSheet: View {
    @Binding var draft: RemoveBackgroundDraft
    /// The picture of the selected clip, its asset key, and the layer box's shorter side (the feather's unit).
    let source: CGImage?
    let sourceKey: String

    @Environment(\.dismiss) private var dismiss

    static func height(for mode: RemoveBackgroundMode) -> CGFloat { mode == .point ? 480 : 250 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if draft.mode == .point { SubjectPicker(draft: $draft, source: source, sourceKey: sourceKey) }
                HStack {
                    Text("Feather").font(.caption).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                    Slider(value: $draft.feather, in: 0...1).accessibilityIdentifier("removeBgFeather")
                    Text(String(format: "%.0f", draft.feather * 100)).font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                Button { draft.invert.toggle() } label: {
                    VStack(spacing: 4) {
                        Circle().fill(draft.invert ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                            .overlay(Image(systemName: "rectangle.lefthalf.inset.filled").font(.system(size: 18, weight: .medium)).foregroundColor(draft.invert ? .white : .primary))
                        Text("Invert").font(.caption2).foregroundColor(draft.invert ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("removeBgInvert")
                .accessibilityAddTraits(draft.invert ? .isSelected : [])
            }
            .padding(.top, 8)
            .navigationTitle(draft.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { draft.feather = 0; draft.invert = false; draft.at = RemoveBackgroundDraft().at } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(!(draft.feather != 0 || draft.invert || draft.at != RemoveBackgroundDraft().at))
                        .accessibilityLabel("Reset").accessibilityIdentifier("removeBgReset")
                }
                ToolbarItem(placement: .principal) { if SegmentationStore.shared.isWorking { ProgressView().accessibilityIdentifier("removeBgWorking") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("removeBgDone") }
            }
        }
        .presentationDetents([.height(Self.height(for: draft.mode))])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
    }
}

/// The whole picture on a checkerboard - the original faded, the cut-out in full on top - and a tap on it chooses the subject (`draft.at`, fractions of the picture).
private struct SubjectPicker: View {
    @Binding var draft: RemoveBackgroundDraft
    let source: CGImage?
    let sourceKey: String

    @State private var cutout: CGImage?

    var body: some View {
        GeometryReader { proxy in
            if let source {
                let ratio = CGFloat(source.width) / CGFloat(source.height)
                let fit = ratio > proxy.size.width / proxy.size.height
                    ? CGSize(width: proxy.size.width, height: proxy.size.width / ratio)
                    : CGSize(width: proxy.size.height * ratio, height: proxy.size.height)
                ZStack {
                    Checkerboard()
                    Image(decorative: source, scale: 1).resizable().opacity(0.3)
                    if let cutout { Image(decorative: cutout, scale: 1).resizable() }
                    Circle().strokeBorder(.white, lineWidth: 3).background(Circle().fill(Color.accentColor.opacity(0.5))).frame(width: 22, height: 22)
                        .shadow(radius: 2)
                        .position(x: draft.at.x * fit.width, y: draft.at.y * fit.height)
                }
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    draft.at = CGPoint(x: min(max(tap.location.x / fit.width, 0), 1), y: min(max(tap.location.y / fit.height, 0), 1))
                })
                .frame(width: proxy.size.width, height: proxy.size.height)
                .task(id: "\(draft.at.x),\(draft.at.y)") {
                    let segmentation = V2MaskSegmentation(mode: "point", at: V2Vec2(x: Double(draft.at.x), y: Double(draft.at.y)))
                    cutout = await SegmentationStore.shared.cutout(of: source, sourceKey: sourceKey, segmentation: segmentation, featherPx: 0, invert: false)
                }
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("removeBgPicker")
    }
}

/// One opening of the popup (`.sheet(item:)`, like the Mask popup).
struct RemoveBackgroundSession: Identifiable {
    let id = UUID()
}

/// The bottom row while Remove BG is open. The picked tile shows an adjust icon (a spinner while Vision works); a tap on it opens the popup.
struct RemoveBackgroundToolRow: View {
    let current: RemoveBackgroundMode
    /// A photo offers every mode; a video only None and Auto (Choose subject would need the subject followed from frame to frame).
    var modes: [RemoveBackgroundMode] = RemoveBackgroundMode.allCases
    let onPick: (RemoveBackgroundMode) -> Void
    var chromaKeyEnabled = false
    var onChromaKey: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BottomBarItem.spacing) {
                ForEach(modes) { mode in
                    let picked = current == mode
                    Button { onPick(mode) } label: {
                        BottomBarItem(title: mode.title, symbol: picked && mode != .none ? "slider.horizontal.3" : mode.symbol, tint: picked ? .accentColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if picked, mode != .none, SegmentationStore.shared.isWorking || !SegmentationJobs.shared.running.isEmpty { ProgressView().controlSize(.mini) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("removeBg-\(mode.rawValue)")
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
                Button(action: onChromaKey) {
                    BottomBarItem(title: "Chroma key", symbol: chromaKeyEnabled ? "slider.horizontal.3" : "viewfinder", tint: chromaKeyEnabled ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("removeBg-chroma")
                .accessibilityAddTraits(chromaKeyEnabled ? .isSelected : [])
            }
            .padding(.horizontal, 8)
        }
    }
}
