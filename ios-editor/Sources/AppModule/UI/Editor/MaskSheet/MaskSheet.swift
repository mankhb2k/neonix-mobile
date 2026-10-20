import SwiftUI

/// The Mask tool in the editor (user 2026-10-18): the clip row's Mask replaces the bottom row with `MaskToolRow` (None, Horizontal, Mirror, Circle, Rectangle);
/// a tap on a shape applies it and puts its handles on the live stage (`MaskGestureOverlay`), and the picked shape shows an adjust icon whose tap opens this popup.
/// The popup is the lab's "controls on top, round icons below" layout (the Volume popup's way): the ruler or slider of the chosen parameter on top
/// (Position and Rotate, two ways from 0, on Transform's ruler like the Transform tool; Size, Feather, Round, one way, on sliders) and round buttons under it
/// - Position, Rotate, Size, Feather, Round (rectangle only) and Invert. Every change is live; the shell makes the whole session one undo step.
struct MaskSheet: View {
    @Binding var draft: MaskDraft

    @Environment(\.dismiss) private var dismiss
    @State private var parameter: MaskParameter = .position
    @State private var axisIndex = 0

    static let height = PresentationDetent.height(300)

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {   // the gap between the ruler / slider and the round buttons (user 2026-10-18: was 12)
                controls
                    .frame(height: 118, alignment: .center)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(MaskParameter.allCases.filter { $0.applies(to: draft.shape) }) { item in
                            button(item.title, symbol: item.symbol, selected: parameter == item, id: "maskParam-\(item.rawValue)") { parameter = item; axisIndex = 0 }
                        }
                        button("Invert", symbol: "rectangle.lefthalf.inset.filled", selected: draft.invert, id: "maskInvert") { draft.invert.toggle() }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .navigationTitle(parameter.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { draft = MaskDraft(shape: draft.shape) } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(draft == MaskDraft(shape: draft.shape)).accessibilityLabel("Reset").accessibilityIdentifier("maskReset")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("maskDone") }
            }
        }
        .presentationDetents([Self.height])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: draft.shape) { _, shape in if !parameter.applies(to: shape) { parameter = .position } }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let axes = MaskAxis.axes(for: parameter, shape: draft.shape)
        if parameter.isTwoWay, !axes.isEmpty {
            let axis = axes[min(axisIndex, axes.count - 1)]
            VStack(spacing: 2) {
                if axes.count > 1 {
                    Picker("Axis", selection: $axisIndex) {
                        ForEach(Array(axes.enumerated()), id: \.offset) { index, item in Text(item.title).tag(index) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 220)
                    .accessibilityIdentifier("maskAxis")
                }
                RulerDial(value: binding(axis), mapping: .linear(axis.range, step: axis.step, majorEvery: axis.majorEvery), detents: axis.neutral.map { [$0] } ?? [],
                          neutral: axis.neutral, format: { String(format: "%.0f", $0 == 0 ? 0 : $0) })
            }
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 8) {
                ForEach(axes) { axis in
                    HStack {
                        Text(axis.title).font(.caption).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                        Slider(value: binding(axis), in: axis.range).accessibilityIdentifier("maskSlider-\(axis.id)")
                        Text(String(format: "%.0f", axis.get(draft))).font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func binding(_ axis: MaskAxis) -> Binding<Double> {
        Binding(get: { axis.get(draft) }, set: { value in var next = draft; axis.set(&next, value); draft = next })
    }

    private func button(_ title: String, symbol: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(title).font(.caption2).foregroundColor(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One opening of the popup (`.sheet(item:)`, like the Volume and Crop popups).
struct MaskSession: Identifiable {
    let id = UUID()
}

/// The bottom row while the Mask tool is open: the shapes, from the left. The picked one shows an adjust icon; a tap on it opens the popup.
struct MaskToolRow: View {
    let current: MaskShape
    let onPick: (MaskShape) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BottomBarItem.spacing) {
                ForEach(MaskShape.allCases) { shape in
                    let picked = current == shape
                    Button { onPick(shape) } label: {
                        BottomBarItem(title: shape.title, symbol: picked && shape != .none ? "slider.horizontal.3" : shape.symbol, tint: picked ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("maskShape-\(shape.rawValue)")
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

/// The picked mask's outline and handles on the live stage, where the layer is (the layer's own box, turned and scaled by its transform the way
/// `TransformGestureOverlay` places its outline): drag inside to move the mask, the round handles to size / feather / round it, a twist to turn it.
struct MaskGestureOverlay: View {
    @Binding var draft: MaskDraft
    let composition: V2Composition
    let layerFrame: V2Frame
    let transform: TransformValues
    let onBegin: () -> Void
    let onEnd: () -> Void

    /// Room around the layer's box for handles that sit outside it.
    private let margin: CGFloat = 70

    var body: some View {
        GeometryReader { proxy in
            let k = min(proxy.size.width / composition.width, proxy.size.height / composition.height)   // composition px -> points
            let size = CGSize(width: layerFrame.width * k, height: layerFrame.height * k)
            ZStack {
                MaskHandlesLayer(draft: $draft, display: CGRect(x: margin, y: margin, width: size.width, height: size.height), onBegin: onBegin, onEnd: onEnd)
                    .frame(width: size.width + 2 * margin, height: size.height + 2 * margin)
                    .scaleEffect(transform.scale)
                    .rotationEffect(.degrees(transform.rotation))
                    .offset(x: transform.x * k, y: transform.y * k)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityIdentifier("maskOverlay")
    }
}
