import SwiftUI

/// Transform as a sheet over the lower part of the screen (the same pattern as Adjust): the ruler on top, the round
/// buttons for Position X/Y, Scale, Rotate and Opacity under it; Reset is an icon button opposite Done. The stage above stays live and can
/// also be dragged, pinched and twisted directly (`TransformGestureOverlay`); both edit the same `values`.
struct TransformSheet: View {
    @Binding var values: TransformValues
    let composition: V2Composition
    let onBegin: () -> Void
    let onEnd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var control: TransformControl

    /// `initialControl`: the ruler the sheet opens on (the Opacity tool opens it on `.opacity`).
    init(values: Binding<TransformValues>, composition: V2Composition, initialControl: TransformControl = .x,
         onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        _values = values
        self.composition = composition
        self.onBegin = onBegin
        self.onEnd = onEnd
        _control = State(initialValue: initialControl)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                RulerDial(
                    value: Binding(get: { values[keyPath: control.keyPath] }, set: { values[keyPath: control.keyPath] = $0 }),
                    mapping: control.mapping(for: composition), detents: control.detents, neutral: control.neutral,
                    format: control.display,
                    onEditingChanged: { editing in if editing { onBegin() } else { onEnd() } }
                )
                .id(control)
                .padding(.bottom, 18)   // 14 (stack spacing) + 18 = 32 pt between the ruler and the buttons
                buttons
            }
            .padding(.top, 8)
            .navigationTitle(control.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { reset { $0 = TransformValues() } } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(values == TransformValues())
                        .accessibilityLabel("Reset")
                        .accessibilityIdentifier("transform-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("transformDone")
                }
            }
        }
        .presentationDetents([.height(280)])
        .presentationBackgroundInteraction(.enabled)
    }

    private var buttons: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(TransformControl.allCases) { item in button(item).id(item.rawValue) }
                }
                .padding(.horizontal, 16)
                // The 5 buttons are narrower than the screen: without this a horizontal ScrollView hugs them to the left.
                .containerRelativeFrame(.horizontal, alignment: .center)
            }
            .onChange(of: control) { _, new in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new.rawValue, anchor: .center) } }
        }
    }

    private func button(_ item: TransformControl) -> some View {
        let selected = control == item
        let changed = values.isChanged(item)
        return Button { control = item } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(selected ? Color.accentColor : Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(item.display(values[keyPath: item.keyPath]))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(changed ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        // Double tap puts just this one back to neutral (its own undo step).
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset { $0[keyPath: item.keyPath] = item.neutral } })
        .accessibilityIdentifier("transform-\(item.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityValue(item.display(values[keyPath: item.keyPath]))
    }

    private func reset(_ change: (inout TransformValues) -> Void) {
        onBegin()
        change(&values)
        onEnd()
    }
}

/// Direct manipulation on the stage while the Transform sheet is open: drag to move, pinch to scale, twist to rotate,
/// with an outline around the layer. Edits the same `values` the sheet's rulers do, as one undo step per gesture.
struct TransformGestureOverlay: View {
    @Binding var values: TransformValues
    let composition: V2Composition
    /// The layer's own size in composition units, for the outline.
    let layerFrame: V2Frame
    let onBegin: () -> Void
    let onEnd: () -> Void

    @State private var dragBase: (x: Double, y: Double)?
    @State private var pinchBase: Double?
    @State private var twistBase: Double?

    var body: some View {
        GeometryReader { proxy in
            let k = min(proxy.size.width / composition.width, proxy.size.height / composition.height)   // composition px -> points
            ZStack {
                Color.clear
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: layerFrame.width * k, height: layerFrame.height * k)
                    .scaleEffect(values.scale)
                    .rotationEffect(.degrees(values.rotation))
                    .offset(x: values.x * k, y: values.y * k)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(gestures(k))
        }
        .accessibilityIdentifier("transformOverlay")
    }

    private var isActive: Bool { dragBase != nil || pinchBase != nil || twistBase != nil }

    /// One undo step spans every gesture that is on the stage at once (a pinch and a twist together are one edit).
    private func started() { if !isActive { onBegin() } }
    private func finished() { if !isActive { onEnd() } }

    private func gestures(_ k: Double) -> some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                if dragBase == nil { started(); dragBase = (values.x, values.y) }
                guard let base = dragBase else { return }
                values.x = (base.x + value.translation.width / k).rounded()
                values.y = (base.y + value.translation.height / k).rounded()
            }
            .onEnded { _ in dragBase = nil; finished() }
        let pinch = MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil { started(); pinchBase = values.scale }
                values.scale = min(max((pinchBase ?? 1) * value.magnification, 0.25), 4)
            }
            .onEnded { _ in pinchBase = nil; finished() }
        let twist = RotateGesture()
            .onChanged { value in
                if twistBase == nil { started(); twistBase = values.rotation }
                var degrees = ((twistBase ?? 0) + value.rotation.degrees).truncatingRemainder(dividingBy: 360)
                if degrees > 180 { degrees -= 360 } else if degrees < -180 { degrees += 360 }
                values.rotation = degrees.rounded()
            }
            .onEnded { _ in twistBase = nil; finished() }
        return drag.simultaneously(with: pinch).simultaneously(with: twist)
    }
}
