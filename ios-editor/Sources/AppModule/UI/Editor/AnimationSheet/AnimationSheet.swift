import SwiftUI

/// The Animation tool (user 2026-10-14, after CapCut): three tabs - In, Out, Combo - a row of group chips and a four-column grid of
/// presets (None first). Picking one applies it at once (one undo step) and plays it on the stage; a Duration slider appears for an In or Out
/// animation. `AnimationWrappers` keeps the animations in the project; this view only picks and reads them back.
struct AnimationSheet: View {
    let clipDurationMs: Double
    let onPick: (AnimationSlot, String?, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applied: [AnimationSlot: AnimationWrappers.Applied]
    @State private var slot: AnimationSlot = .in
    @State private var group = "All"

    init(initial: [AnimationSlot: AnimationWrappers.Applied], clipDurationMs: Double, onPick: @escaping (AnimationSlot, String?, Double) -> Void) {
        _applied = State(initialValue: initial)
        self.clipDurationMs = clipDurationMs
        self.onPick = onPick
    }

    private var current: AnimationWrappers.Applied? { applied[slot] }
    private var presets: [AnimationPreset] {
        AnimationCatalog.presets(for: slot).filter { group == "All" || $0.group == group }
    }
    private var groups: [String] { ["All"] + AnimationCatalog.groups.filter { g in AnimationCatalog.presets(for: slot).contains { $0.group == g } } }
    /// An entrance and an exit may not overlap: each gets at most half of the clip (and 3 s).
    private var maxDurationMs: Double { min(3000, max(clipDurationMs / 2, 200)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            chips.padding(.top, 10)
            grid.padding(.top, 8)
            if let current, slot != .combo { durationRow(for: current).padding(.horizontal, 16).padding(.vertical, 10) }
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .animation(.easeOut(duration: 0.2), value: current?.presetId)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 26) {
            ForEach(AnimationSlot.allCases) { item in
                Button { slot = item; group = "All" } label: {
                    VStack(spacing: 6) {
                        Text(item.title).font(.subheadline.weight(slot == item ? .semibold : .regular))
                            .foregroundColor(slot == item ? .primary : .secondary)
                        Capsule().fill(slot == item ? Color.accentColor : .clear).frame(width: 28, height: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("animationTab-\(item.title)")
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 40, height: 40) }
                .accessibilityIdentifier("animationDone")
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.self) { item in
                    let on = group == item
                    Button { group = item } label: {
                        Text(item).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                            .foregroundColor(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("animationChip-\(item)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                tile(id: "none", title: "None", symbol: "nosign", on: current == nil) { choose(nil) }
                ForEach(presets) { preset in
                    tile(id: preset.id, title: preset.title, symbol: preset.symbol, on: current?.presetId == preset.id) { choose(preset) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .accessibilityIdentifier("animationGrid")
    }

    private func tile(id: String, title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22)).frame(height: 30)
                Text(title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if on && id != "none" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).font(.caption).padding(3) }
            }
            .foregroundColor(on ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("animationCell-\(id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func durationRow(for applied: AnimationWrappers.Applied) -> some View {
        let binding = Binding<Double>(
            get: { min(applied.durationMs, maxDurationMs) },
            set: { value in self.applied[slot]?.durationMs = value }
        )
        return HStack(spacing: 12) {
            Text("Duration").font(.subheadline).foregroundColor(.secondary)
            Slider(value: binding, in: 100...maxDurationMs, onEditingChanged: { editing in
                if !editing, let now = self.applied[slot] { onPick(slot, now.presetId, now.durationMs) }
            })
            .accessibilityIdentifier("animationDuration")
            Text(String(format: "%.1fs", binding.wrappedValue / 1000)).font(.subheadline.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }

    private func choose(_ preset: AnimationPreset?) {
        guard let preset else {
            applied[slot] = nil
            onPick(slot, nil, 0)
            return
        }
        let duration = slot == .combo ? 0 : min(applied[slot]?.durationMs ?? preset.defaultDurationMs, maxDurationMs)
        applied[slot] = AnimationWrappers.Applied(slot: slot, presetId: preset.id, durationMs: duration)
        onPick(slot, preset.id, duration)
    }
}
