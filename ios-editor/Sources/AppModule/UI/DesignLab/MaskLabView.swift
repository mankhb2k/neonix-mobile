import SwiftUI

/// Design lab for the Mask tool, after CapCut's (user's references 2026-10-18). One working mask on a live photo (`MaskStage`: yellow outline, handles to move,
/// size, feather and round it, a twist to turn it) with four shapes - Horizontal, Mirror, Circle, Rectangle - and Invert, in three layouts of the controls, all in
/// a sheet with the stage live above it: A the Volume popup's way (parameter chips, then the ruler or slider on top, **round shape icons below**), B round buttons
/// Shape / Position / Rotate / Size / Feather / Invert with the tiles or a ruler inside, C tiles on top with chips and a ruler or slider under them (the
/// two-way parameters, Position and Rotate, on Transform's ruler, the one-way ones on sliders). Fake data: nothing is stored.
struct MaskLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case icons = "A Icons below", sheet = "B Sheet", sliders = "C Sliders"
        var id: String { rawValue }

        var summary: String {
            switch self {
            case .icons: return "Like the Volume popup: parameter chips and the ruler or slider on top, the round shape icons (Horizontal, Mirror, Circle, Rectangle, Invert) below"
            case .sheet: return "The editor's sheet: round buttons Shape / Position / Rotate / Size / Feather / Invert, the tiles or a ruler inside, Reset and Done on top"
            case .sliders: return "A lighter sheet: tiles and parameter chips; Position and Rotate (two ways from a middle mark) on the Transform ruler, Size / Feather / Round on plain sliders"
            }
        }
    }

    enum Param: String, CaseIterable, Identifiable {
        case position, rotate, size, feather, roundness
        var id: String { rawValue }
        var title: String {
            switch self {
            case .position: return "Position"
            case .rotate: return "Rotate"
            case .size: return "Size"
            case .feather: return "Feather"
            case .roundness: return "Round"
            }
        }
        var symbol: String {
            switch self {
            case .position: return "arrow.up.and.down.and.arrow.left.and.right"
            case .rotate: return "rotate.right"
            case .size: return "arrow.up.left.and.arrow.down.right"
            case .feather: return "aqi.medium"
            case .roundness: return "square.on.square.squareshape.controlhandles"
            }
        }
        func applies(to shape: MaskShape) -> Bool {
            switch self {
            case .position, .rotate, .feather: return shape != .none
            case .size: return shape.hasHeight
            case .roundness: return shape == .rectangle
            }
        }
    }

    @State private var variant: Variant = .icons
    @State private var draft = MaskDraft()
    @State private var photo: UIImage?
    @State private var param: Param = .position
    @State private var axisIndex = 0
    @State private var sheetOpen = false
    @State private var sheetSection: SheetSection = .shape
    @State private var toast: String?

    enum SheetSection: Hashable { case shape, param(Param) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) { ForEach(Variant.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
                .accessibilityIdentifier("maskVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal).padding(.top, 4)
            switch variant {
            case .icons, .sheet, .sliders: sheetHost
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { photo = await AdjustLabView.loadPhoto() }
        .onChange(of: variant) { _, _ in sheetOpen = false }
        .sheet(isPresented: $sheetOpen) {
            switch variant {
            case .icons: AnyView(iconsSheet)
            case .sheet: AnyView(maskSheet)
            case .sliders: AnyView(slidersSheet)
            }
        }
        .overlay { if let toast { Text(toast).font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.75), in: Capsule()).foregroundColor(.white) } }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }.accessibilityIdentifier("maskClose")
            Spacer()
            Text("Mask lab").font(.headline)
            Spacer()
            Menu { Button("Reset mask", role: .destructive) { draft = MaskDraft() } } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 8)
    }

    private var stage: some View {
        MaskStage(image: photo, draft: $draft)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .padding(.bottom, sheetOpen ? (variant == .sliders ? 330 : 290) : 0)
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: sheetOpen)
    }

    // MARK: Parameters as rulers / sliders (shared by the three layouts)

    private func pick(_ shape: MaskShape) {
        draft = MaskDraft(shape: shape, keeping: draft)
        if !param.applies(to: shape) { param = .position }
        axisIndex = 0
    }

    private struct Axis {
        let id: String
        let title: String
        let range: ClosedRange<Double>
        let step: Double
        let majorEvery: Int
        let neutral: Double?
        let get: (MaskDraft) -> Double
        let set: (inout MaskDraft, Double) -> Void
    }

    private func axes(for param: Param) -> [Axis] {
        switch param {
        case .position:
            return [Axis(id: "x", title: "X axis", range: -50...50, step: 1, majorEvery: 10, neutral: 0, get: { ($0.centerX - 0.5) * 100 }, set: { $0.centerX = 0.5 + $1 / 100 }),
                    Axis(id: "y", title: "Y axis", range: -50...50, step: 1, majorEvery: 10, neutral: 0, get: { ($0.centerY - 0.5) * 100 }, set: { $0.centerY = 0.5 + $1 / 100 })]
        case .rotate:
            return [Axis(id: "rotate", title: "Rotate", range: -180...180, step: 1, majorEvery: 45, neutral: 0, get: { $0.rotation }, set: { $0.rotation = $1 })]
        case .size:
            var list: [Axis] = []
            if draft.shape.hasWidth { list.append(Axis(id: "width", title: "Width", range: 5...200, step: 1, majorEvery: 25, neutral: nil, get: { $0.width * 100 }, set: { $0.width = $1 / 100 })) }
            if draft.shape.hasHeight { list.append(Axis(id: "height", title: draft.shape == .mirror ? "Thickness" : "Height", range: 5...200, step: 1, majorEvery: 25, neutral: nil, get: { $0.height * 100 }, set: { $0.height = $1 / 100 })) }
            return list
        case .feather:
            return [Axis(id: "feather", title: "Feather", range: 0...100, step: 1, majorEvery: 10, neutral: 0, get: { $0.feather * 100 }, set: { $0.feather = $1 / 100 })]
        case .roundness:
            return [Axis(id: "round", title: "Round", range: 0...100, step: 1, majorEvery: 10, neutral: 0, get: { $0.roundness * 100 }, set: { $0.roundness = $1 / 100 })]
        }
    }

    private func binding(_ axis: Axis) -> Binding<Double> {
        Binding(get: { axis.get(draft) }, set: { value in var next = draft; axis.set(&next, value); draft = next })
    }

    /// One ruler at a time (two did not fit the sheet): with two axes (X / Y, Width / Height) a small switch picks which one the ruler edits.
    private func rulers(for param: Param) -> some View {
        let list = axes(for: param)
        let axis = list[min(axisIndex, max(list.count - 1, 0))]
        return VStack(spacing: 2) {
            if list.count > 1 {
                Picker("Axis", selection: $axisIndex) {
                    ForEach(Array(list.enumerated()), id: \.offset) { index, item in Text(item.title).tag(index) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 220)
                .accessibilityIdentifier("maskAxis")
            }
            RulerDial(value: binding(axis), mapping: .linear(axis.range, step: axis.step, majorEvery: axis.majorEvery), detents: axis.neutral.map { [$0] } ?? [],
                      neutral: axis.neutral, format: { String(format: "%.0f", $0 == 0 ? 0 : $0) })
        }
    }

    private func tile(_ shape: MaskShape, idPrefix: String) -> some View {
        let on = draft.shape == shape
        return Button { pick(shape) } label: {
            VStack(spacing: 5) {
                Image(systemName: shape.symbol).font(.system(size: 22))
                    .frame(width: 64, height: 56)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                    .foregroundColor(.primary)
                Text(shape.title).font(.caption2).foregroundColor(on ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(idPrefix)-\(shape.rawValue)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tiles(idPrefix: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) { ForEach(MaskShape.allCases) { tile($0, idPrefix: idPrefix) } }.padding(.horizontal, 16)
        }
    }

    // MARK: A - the Volume popup's way: controls on top, round icons below

    private var iconsSheet: some View {
        NavigationStack {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Param.allCases.filter { $0.applies(to: draft.shape) }) { item in
                            Button { param = item; axisIndex = 0 } label: {
                                Text(item.title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(param == item ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                                    .foregroundColor(param == item ? .white : .primary)
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("iconChip-\(item.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 32)
                Group {
                    if draft.shape == .none {
                        Text("Pick a shape below").font(.subheadline).foregroundColor(.secondary)
                    } else if param == .position || param == .rotate {
                        rulers(for: param).padding(.horizontal, 12)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(axes(for: param), id: \.id) { axis in
                                HStack {
                                    Text(axis.title).font(.caption).foregroundColor(.secondary).frame(width: 62, alignment: .leading)
                                    Slider(value: binding(axis), in: axis.range).accessibilityIdentifier("iconSlider-\(axis.id)")
                                    Text(String(format: "%.0f", axis.get(draft))).font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .frame(height: 112, alignment: .center)
                HStack(spacing: 14) {
                    ForEach(MaskShape.allCases) { shape in
                        roundButton(shape.title, symbol: shape.symbol, selected: draft.shape == shape, id: "iconShape-\(shape.rawValue)") { pick(shape) }
                    }
                    roundButton("Invert", symbol: "rectangle.lefthalf.inset.filled", selected: draft.invert, id: "iconInvert") { draft.invert.toggle() }
                        .disabled(draft.shape == .none)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .navigationTitle("Mask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { draft = MaskDraft() } label: { Image(systemName: "arrow.counterclockwise") }.disabled(!draft.isChanged).accessibilityLabel("Reset").accessibilityIdentifier("iconReset")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetOpen = false }.accessibilityIdentifier("maskSheetDone") }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    // MARK: B - the editor's sheet

    private var sheetHost: some View {
        VStack(spacing: 0) {
            stage
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.2").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Divider().frame(height: 28)
                ForEach([("scissors", "Split"), ("circle.lefthalf.filled", "Mask"), ("trash", "Delete")], id: \.1) { symbol, title in
                    Button { if title == "Mask" { sheetOpen = true } } label: {
                        VStack(spacing: 4) { Image(systemName: symbol).font(.title3); Text(title).font(.caption2) }
                            .frame(maxWidth: .infinity)
                            .foregroundColor(title == "Delete" ? .red : (title == "Split" ? .secondary : .primary))
                    }
                    .accessibilityIdentifier(title == "Mask" ? "maskOpen" : "maskMock-\(title)")
                }
            }
            .padding(.horizontal, 12).frame(height: 56)
        }
    }

    private var maskSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Group {
                    switch sheetSection {
                    case .shape: tiles(idPrefix: "sheetTile")
                    case .param(let item): rulers(for: item)
                    }
                }
                .frame(height: 104, alignment: .center)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        roundButton("Shape", symbol: "square.on.circle", selected: sheetSection == .shape, id: "maskSection-shape") { sheetSection = .shape }
                        ForEach(Param.allCases.filter { $0.applies(to: draft.shape) }) { item in
                            roundButton(item.title, symbol: item.symbol, selected: sheetSection == .param(item), id: "maskSection-\(item.rawValue)") { sheetSection = .param(item); axisIndex = 0 }
                        }
                        roundButton("Invert", symbol: "rectangle.lefthalf.inset.filled", selected: draft.invert, id: "maskSection-invert") { draft.invert.toggle() }
                            .disabled(draft.shape == .none)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 8)
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { draft = MaskDraft() } label: { Image(systemName: "arrow.counterclockwise") }.disabled(!draft.isChanged).accessibilityLabel("Reset").accessibilityIdentifier("maskSheetReset")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetOpen = false }.accessibilityIdentifier("maskSheetDone") }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    private var sheetTitle: String {
        switch sheetSection {
        case .shape: return "Mask"
        case .param(let item): return item.title
        }
    }

    private func roundButton(_ title: String, symbol: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(title).font(.caption2).foregroundColor(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    // MARK: C - sliders

    private var slidersSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                tiles(idPrefix: "sliderTile")
                if draft.shape != .none {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Param.allCases.filter { $0.applies(to: draft.shape) }) { item in
                                Button { param = item; axisIndex = 0 } label: {
                                    Text(item.title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(param == item ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                                        .foregroundColor(param == item ? .white : .primary)
                                }
                                .buttonStyle(.plain).accessibilityIdentifier("sliderChip-\(item.rawValue)")
                            }
                            Toggle("Invert", isOn: $draft.invert).toggleStyle(.button).font(.subheadline.weight(.medium)).accessibilityIdentifier("sliderInvert")
                        }
                        .padding(.horizontal, 16)
                    }
                    if param == .position || param == .rotate {
                        // Two ways from a middle mark (0): the same ruler as the Transform tool.
                        rulers(for: param).padding(.horizontal, 12)
                    } else {
                        // One way from zero: a plain slider is enough.
                        VStack(spacing: 6) {
                            ForEach(axes(for: param), id: \.id) { axis in
                                HStack {
                                    Text(axis.title).font(.caption).foregroundColor(.secondary).frame(width: 62, alignment: .leading)
                                    Slider(value: binding(axis), in: axis.range).accessibilityIdentifier("maskSlider-\(axis.id)")
                                    Text(String(format: "%.0f", axis.get(draft))).font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Mask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { draft = MaskDraft() } label: { Image(systemName: "arrow.counterclockwise") }.disabled(!draft.isChanged).accessibilityLabel("Reset")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetOpen = false }.accessibilityIdentifier("maskSheetDone") }
            }
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
    }
}
