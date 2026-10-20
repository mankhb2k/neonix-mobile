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
    /// The picture the tiles animate (`preview-animation.png`, whole, `AnimationPreviewImage`); nil until loaded.
    @State private var previewImage: UIImage?

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
        .task {
            guard previewImage == nil else { return }
            previewImage = await AnimationPreviewImage.load()
        }
        .presentationDetents([.height(440), .large])
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
                tile(id: "none", title: "None", symbol: "nosign", preset: nil, on: current == nil) { choose(nil) }
                ForEach(presets) { preset in
                    tile(id: preset.id, title: preset.title, symbol: preset.symbol, preset: preset, on: current?.presetId == preset.id) { choose(preset) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .accessibilityIdentifier("animationGrid")
    }

    /// A tile: the preset playing on the preview picture (the None tile keeps its icon) and its name under it.
    private func tile(id: String, title: String, symbol: String, preset: AnimationPreset?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if let preset {
                    AnimationPreviewTile(preset: preset, slot: slot, image: previewImage).frame(height: 58)
                } else {
                    Image(systemName: symbol).font(.system(size: 22)).frame(height: 58)
                }
                Text(title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 5).padding(.top, 5).padding(.bottom, 4)
            .frame(maxWidth: .infinity)
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
import SwiftUI

/// Preset picker for a main-lane cut. It follows AnimationSheet's live selection, preview tiles and duration control.
struct TransitionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: TransitionKind?
    @State private var durationSeconds: Double

    let onPick: (TransitionKind?, Double) -> Void

    init(initialKind: TransitionKind?, initialDurationMs: Double, onPick: @escaping (TransitionKind?, Double) -> Void) {
        _selected = State(initialValue: initialKind)
        _durationSeconds = State(initialValue: min(max(initialDurationMs / 1000, 0.1), 1.5))
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    tile(kind: nil)
                    ForEach(TransitionKind.allCases) { kind in tile(kind: kind) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            if selected != nil { durationControl.padding(.horizontal, 16).padding(.vertical, 10) }
        }
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .animation(.easeOut(duration: 0.2), value: selected?.rawValue)
    }

    private var header: some View {
        HStack {
            Text("Transition").font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("transitionDone")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func tile(kind: TransitionKind?) -> some View {
        let isSelected = selected == kind
        let id = kind?.rawValue ?? "none"
        return Button {
            selected = kind
            onPick(kind, durationSeconds * 1000)
        } label: {
            VStack(spacing: 7) {
                TransitionPreviewTile(kind: kind)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(kind?.title ?? "None")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if isSelected, kind != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.caption)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transitionCell-\(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var durationControl: some View {
        HStack(spacing: 12) {
            Text("Duration").font(.subheadline).foregroundStyle(.secondary)
            Slider(value: $durationSeconds, in: 0.1...1.5, step: 0.1) { editing in
                if !editing, let selected { onPick(selected, durationSeconds * 1000) }
            }
            .accessibilityIdentifier("transitionDuration")
            Text(String(format: "%.1fs", durationSeconds))
                .font(.subheadline.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
                .accessibilityIdentifier("transitionDurationValue")
        }
    }
}

/// A small animated two-shot preview that mirrors each transition's motion.
private struct TransitionPreviewTile: View {
    let kind: TransitionKind?

    var body: some View {
        GeometryReader { proxy in
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let progress = (sin(context.date.timeIntervalSinceReferenceDate * 1.5) + 1) / 2
                let size = proxy.size
                ZStack {
                    if let kind {
                        Color(red: 0.12, green: 0.56, blue: 0.66)
                        switch kind {
                        case .mix:
                            shot(color: Color(red: 0.43, green: 0.32, blue: 0.68), size: size)
                                .opacity(progress)
                        case .fadeBlack:
                            shot(color: Color(red: 0.43, green: 0.32, blue: 0.68), size: size)
                                .opacity(progress)
                            Color.black.opacity(max(0, 1 - abs(progress - 0.5) * 2))
                        case .push:
                            shot(color: Color(red: 0.12, green: 0.56, blue: 0.66), size: size)
                                .offset(x: -progress * size.width)
                            shot(color: Color(red: 0.43, green: 0.32, blue: 0.68), size: size)
                                .offset(x: (1 - progress) * size.width)
                        }
                    } else {
                        Color(.tertiarySystemBackground)
                        Image(systemName: "nosign")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: 25, height: 2).padding(.bottom, 5)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func shot(color: Color, size: CGSize) -> some View {
        Rectangle().fill(color).overlay {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: min(size.height * 0.48, 32), weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
