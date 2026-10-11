import SwiftUI

/// Adjust (Tuỳ chỉnh) as a sheet over the lower part of the screen, like the Curves editor: the ruler on top and one
/// row of round buttons - the 13 controls plus Curves - that scrolls sideways, the selected one centred and every
/// button whose value has been changed marked with a dot. The stage above stays live while it is open.
///
/// Edits keep the contract the old slider row had: `onChange` on every tick (grading needs live feedback), and
/// `onBegin`/`onEnd` around one ruler drag (or one reset) so each is a single undo step.
struct AdjustSheet: View {
    let layerId: String
    let onBegin: () -> Void
    let onChange: (String, AdjustValues) -> Void
    let onEnd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: AdjustValues
    @State private var control: AdjustControl = .brightness
    @State private var showingCurves = false

    init(layerId: String, initial: AdjustValues, onBegin: @escaping () -> Void,
         onChange: @escaping (String, AdjustValues) -> Void, onEnd: @escaping () -> Void) {
        self.layerId = layerId
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd
        _values = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                RulerDial(
                    value: Binding(get: { values[keyPath: control.keyPath] }, set: { values[keyPath: control.keyPath] = $0 }),
                    mapping: control.mapping, detents: [control.neutral], neutral: control.neutral,
                    format: control.display,
                    onEditingChanged: { editing in if editing { onBegin() } else { onEnd() } }
                )
                .id(control)
                .padding(.bottom, 20)   // 12 (stack spacing) + 20 = 32 pt between the ruler and the buttons
                controlButtons
            }
            .padding(.top, 8)
            .onChange(of: values) { _, new in onChange(layerId, new) }
            .navigationTitle(control.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset all") { commitReset { $0 = AdjustValues() } }
                        .disabled(values == AdjustValues())
                        .accessibilityIdentifier("adjustResetAll")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("adjustDone")
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationBackgroundInteraction(.enabled)
        .sheet(isPresented: $showingCurves) {
            CurveEditorSheet(points: $values.curvePoints, onBegin: onBegin, onEnd: onEnd) {
                onChange(layerId, values)
            }
        }
    }

    /// A reset is not a ruler drag, so it brackets its own undo step.
    private func commitReset(_ change: (inout AdjustValues) -> Void) {
        onBegin()
        change(&values)
        onChange(layerId, values)
        onEnd()
    }

    // MARK: Buttons

    private var controlButtons: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(AdjustControl.allCases) { item in
                        controlButton(item).id(item.rawValue)
                        if item == .tint { curvesButton.id("curves") }
                    }
                }
                .padding(.horizontal, 16)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .onChange(of: control) { _, new in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new.rawValue, anchor: .center) } }
            .onAppear { proxy.scrollTo(control.rawValue, anchor: .center) }
            .accessibilityIdentifier("adjustButtons")
        }
    }

    private func controlButton(_ item: AdjustControl) -> some View {
        let selected = control == item
        let changed = values.isChanged(item)
        return Button { control = item } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(selected ? Color.accentColor : Color(.tertiarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(item.display(values[keyPath: item.keyPath])).font(.caption2.monospacedDigit()).foregroundColor(changed ? .accentColor : .secondary)
                Circle().fill(changed ? Color.accentColor : .clear).frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        // Double tap puts just this control back to neutral.
        .simultaneousGesture(TapGesture(count: 2).onEnded { commitReset { $0[keyPath: item.keyPath] = item.neutral } })
        .accessibilityIdentifier("adjust-\(item.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityValue(item.display(values[keyPath: item.keyPath]))
    }

    /// Curves has its own editor (a draggable graph), so this one opens it instead of selecting a ruler.
    private var curvesButton: some View {
        Button { showingCurves = true } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "chart.xyaxis.line").font(.system(size: 18, weight: .medium)))
                Text("Curves").font(.caption2).foregroundColor(values.curvesChanged ? .accentColor : .secondary)
                Circle().fill(values.curvesChanged ? Color.accentColor : .clear).frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("adjust-curves")
    }
}
