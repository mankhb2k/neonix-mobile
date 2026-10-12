import SwiftUI

/// Design lab for the Filter tool. The question is the shape of the picker: a CapCut-style grid in a sheet like Adjust's
/// (A), the same grid with a second, taller detent (B), or a single row of thumbnails (C). Same mock editor around it, a
/// real photo, 16 fake filters in 4 categories, an Intensity ruler, and press-and-hold on the photo to compare.
struct FilterLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case grid = "A Grid", tall = "B Grid+", row = "C Row"
        var id: String { rawValue }

        var summary: String {
            switch self {
            case .grid: return "Fixed-height sheet: category chips, 4-column grid (second row peeks), Intensity ruler"
            case .tall: return "Like A, plus a second detent: pull the sheet up to browse the whole grid"
            case .row: return "One row of thumbnails under the chips, Intensity ruler below - lighter, fewer visible"
            }
        }
    }

    enum GridHeight: Int, CaseIterable, Identifiable {
        case short = 300, standard = 340, tall = 380
        var id: Int { rawValue }
        var title: String { "\(rawValue) pt" }
    }

    /// How Intensity is edited: the Photos-style ruler (about 120 pt tall with its readout) or a compact slider (44 pt),
    /// which leaves room for more of the grid.
    enum IntensityStyle: String, CaseIterable, Identifiable {
        case ruler = "Ruler", slider = "Slider"
        var id: String { rawValue }
    }

    @State private var variant: Variant = .grid
    @State private var intensityStyle: IntensityStyle = .ruler
    @State private var category: LabFilterCategory = .all
    @State private var selected: LabFilter = .none
    @State private var intensity = 1.0
    @State private var sheetOpen = false
    @State private var haptics = true
    @State private var gridHeight: GridHeight = .standard
    @State private var photo: UIImage?
    @State private var thumbnail: UIImage?
    @State private var showsOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("filterVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)
            HStack {
                Text("Intensity").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Picker("Intensity control", selection: $intensityStyle) {
                    ForEach(IntensityStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .accessibilityIdentifier("filterIntensityPicker")
            }
            .padding(.top, 6)

            stage
                .padding(.horizontal, 44).padding(.vertical, 8)
                .frame(maxHeight: .infinity)

            mockSelectionRow
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task {
            photo = await AdjustLabView.loadPhoto()
            if let photo { thumbnail = await photo.byPreparingThumbnail(ofSize: CGSize(width: 300, height: 300)) }
        }
        .onChange(of: variant) { _, _ in sheetOpen = false }
        .sheet(isPresented: $sheetOpen) { filterSheet }
    }

    // MARK: Top + stage

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("filterClose")
            Spacer()
            Text("Filter lab").font(.headline)
            Spacer()
            Menu {
                Toggle("Haptics on ruler", isOn: $haptics)
                Picker("Grid sheet height (A)", selection: $gridHeight) { ForEach(GridHeight.allCases) { Text($0.title).tag($0) } }
                Button("Remove filter", role: .destructive) { selected = .none; intensity = 1 }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 8)
    }

    private var stage: some View {
        // The photo is an overlay so its own size never decides the layout (see AdjustLabView's stage).
        Color(.tertiarySystemBackground)
            .overlay {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .labFilterLook(showsOriginal ? .none : selected, intensity: intensity)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(showsOriginal ? "Original" : (selected == .none ? "No filter" : "\(selected.name) \(Int((intensity * 100).rounded()))%"))
                    .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule()).foregroundColor(.white).padding(8)
                    .accessibilityIdentifier("filterStageName")
            }
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40, perform: {}, onPressingChanged: { showsOriginal = $0 })
            .accessibilityElement(children: .contain)   // keep the name label reachable by its own id
            .accessibilityIdentifier("filterStage")
    }

    /// The row the editor shows while a photo is selected; Filter is one of its buttons.
    private var mockSelectionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.2").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Divider().frame(height: 28)
            ForEach([("scissors", "Split"), ("camera.filters", "Filter"), ("trash", "Delete")], id: \.1) { symbol, title in
                Button { if title == "Filter" { sheetOpen = true } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(title == "Delete" ? .red : (title == "Split" ? .secondary : .primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filterAction-\(title)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Sheet

    private var filterSheet: some View {
        NavigationStack {
            VStack(spacing: 10) {
                categoryChips
                switch variant {
                case .grid, .tall: grid
                case .row: thumbnailRow
                }
                intensityBar
            }
            .padding(.top, 4)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { selected = .none; intensity = 1 }
                        .disabled(selected == .none)
                        .accessibilityIdentifier("filterReset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { sheetOpen = false }.accessibilityIdentifier("filterDone")
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: selected)
        .presentationDetents(detents)
        .presentationDragIndicator(variant == .tall ? .visible : .hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    private var detents: Set<PresentationDetent> {
        switch variant {
        case .grid: return [.height(CGFloat(gridHeight.rawValue))]
        case .tall: return [.height(340), .large]
        case .row: return [.height(300)]
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LabFilterCategory.allCases) { item in
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

    /// 4 columns; in A the second row peeks out under the first, which says "this scrolls".
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(LabFilter.list(in: category)) { filter in cell(filter) }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("filterGrid")
    }

    private var thumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LabFilter.list(in: category)) { filter in cell(filter).frame(width: 78) }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("filterRow")
    }

    private func cell(_ filter: LabFilter) -> some View {
        let isSelected = selected == filter
        return Button { selected = filter } label: {
            Color(.tertiarySystemBackground)
                .overlay {
                    if filter == .none {
                        Image(systemName: "nosign").font(.title2).foregroundColor(.secondary)
                    } else if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill().labFilterLook(filter, intensity: 1)
                    }
                }
                .overlay(alignment: .bottom) {
                    Text(filter.name).font(.caption2.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .foregroundColor(.primary)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5))
                .overlay(alignment: .topTrailing) {
                    if isSelected && filter != .none {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).font(.body).padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterCell-\(filter.id)")
        .accessibilityLabel(filter.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Only shown once a filter is picked (user 2026-10-12): with None selected the grid gets the room instead.
    @ViewBuilder private var intensityBar: some View {
        if selected != .none {
            intensityControl.transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var intensityControl: some View {
        Group {
            switch intensityStyle {
            case .ruler:
                VStack(spacing: 2) {
                    Text("Intensity").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    RulerDial(value: $intensity, mapping: .linear(0...1, step: 0.01, majorEvery: 10), haptics: haptics,
                              format: { String(format: "%.0f", $0 * 100) })
                }
                .padding(.bottom, 8)
            case .slider:
                HStack(spacing: 12) {
                    Text("Intensity").font(.subheadline).foregroundColor(.secondary)
                    Slider(value: $intensity, in: 0...1).accessibilityIdentifier("filterSlider")
                    Text("\(Int((intensity * 100).rounded()))").font(.subheadline.monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }
}
