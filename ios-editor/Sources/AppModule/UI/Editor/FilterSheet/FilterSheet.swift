import SwiftUI

/// Filter as a sheet over the lower part of the screen, like Adjust: category chips, a 4-column grid of thumbnails of the
/// clip itself (None first), and an Intensity slider that appears once a filter is picked (design lab "A Grid" with the
/// slider, 2026-10-12). Tapping a filter applies it at once, one undo step; dragging Intensity is one step per drag. The
/// stage above stays live while it is open.
struct FilterSheet: View {
    let layerId: String
    let sourceProvider: () async -> FilterThumbnails.Source?
    let onBegin: () -> Void
    let onChange: (String, AppliedFilter?) -> Void
    let onEnd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applied: AppliedFilter?
    @State private var category: FilterCategory = .all
    @State private var thumbnails: [String: UIImage] = [:]

    init(layerId: String, initial: AppliedFilter?, sourceProvider: @escaping () async -> FilterThumbnails.Source?,
         onBegin: @escaping () -> Void, onChange: @escaping (String, AppliedFilter?) -> Void, onEnd: @escaping () -> Void) {
        self.layerId = layerId
        self.sourceProvider = sourceProvider
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd
        _applied = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                categoryChips
                grid
                if applied != nil {
                    intensitySlider.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.top, 4)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { select(nil) }
                        .disabled(applied == nil)
                        .accessibilityIdentifier("filterReset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("filterDone")
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: applied == nil)
        .presentationDetents([.height(340)])
        .presentationBackgroundInteraction(.enabled)
        .task { await loadThumbnails() }
    }

    // MARK: Parts

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCategory.allCases) { item in
                    let on = category == item
                    Button { category = item } label: {
                        Text(item.rawValue).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                            .foregroundColor(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filterChip-\(item.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                noneCell
                ForEach(FilterCatalog.list(in: category)) { preset in cell(preset) }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("filterGrid")
    }

    private var noneCell: some View {
        Button { select(nil) } label: {
            Color(.tertiarySystemBackground)
                .overlay(Image(systemName: "nosign").font(.title2).foregroundColor(.secondary))
                .overlay(alignment: .bottom) { label("None") }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(border(applied == nil))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterCell-none")
        .accessibilityLabel("None")
        .accessibilityAddTraits(applied == nil ? .isSelected : [])
    }

    private func cell(_ preset: FilterPreset) -> some View {
        let isSelected = applied?.id == preset.id
        return Button { select(preset) } label: {
            Color(.tertiarySystemBackground)
                .overlay {
                    if let image = thumbnails[preset.id] {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .overlay(alignment: .bottom) { label(preset.name) }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(border(isSelected))
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).font(.body).padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterCell-\(preset.id)")
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .foregroundColor(.primary)
    }

    private func border(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
    }

    private var intensitySlider: some View {
        HStack(spacing: 12) {
            Text("Intensity").font(.subheadline).foregroundColor(.secondary)
            Slider(value: intensityBinding, in: 0...1, onEditingChanged: { editing in editing ? onBegin() : onEnd() })
                .accessibilityIdentifier("filterSlider")
            Text("\(Int(((applied?.intensity ?? 1) * 100).rounded()))")
                .font(.subheadline.monospacedDigit()).frame(width: 34, alignment: .trailing)
                .accessibilityIdentifier("filterIntensityValue")
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    // MARK: Actions

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { applied?.intensity ?? 1 },
            set: { value in
                guard var current = applied else { return }
                current.intensity = value
                applied = current
                onChange(layerId, current)
            }
        )
    }

    /// Picking a filter (or None) is one undo step of its own.
    private func select(_ preset: FilterPreset?) {
        onBegin()
        applied = preset.map { AppliedFilter(id: $0.id, intensity: 1) }
        onChange(layerId, applied)
        onEnd()
    }

    private func loadThumbnails() async {
        guard let source = await sourceProvider() else { return }
        await FilterThumbnails.render(source: source, presets: FilterThumbnails.ordered(for: category)) { id, image in
            thumbnails[id] = image
        }
    }
}
