import SwiftUI
import UIKit

/// How a ruler's ticks map to values: where each tick is, which ones are major, how the value reads.
/// Ticks are evenly spaced on screen; `logarithmic` makes them evenly spaced in *ratio*, so 50% and 200% sit at
/// the same distance from 100%.
struct RulerMapping {
    let tickCount: Int
    let value: (Int) -> Double
    /// Nearest tick for a value (clamped into the ruler).
    let index: (Double) -> Int
    let isMajor: (Int) -> Bool

    /// `lower...upper` in steps of `step`; every `majorEvery`-th multiple of `step` is a major tick, so 0 is always one
    /// when the range spans it.
    static func linear(_ range: ClosedRange<Double>, step: Double, majorEvery: Int) -> RulerMapping {
        let count = Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1
        func clamp(_ i: Int) -> Int { min(max(i, 0), count - 1) }
        return RulerMapping(
            tickCount: count,
            value: { i in
                let raw = range.lowerBound + Double(clamp(i)) * step
                return (raw / step).rounded() * step   // no float drift: -0.30000000000000004 -> -0.3
            },
            index: { v in clamp(Int(((v - range.lowerBound) / step).rounded())) },
            isMajor: { i in Int(((range.lowerBound + Double(i) * step) / step).rounded()) % majorEvery == 0 }
        )
    }

    /// `lower...upper` with `ticksPerDoubling` ticks for each doubling; the major ticks are the doublings.
    static func logarithmic(_ range: ClosedRange<Double>, ticksPerDoubling: Int) -> RulerMapping {
        let count = Int((log2(range.upperBound / range.lowerBound) * Double(ticksPerDoubling)).rounded()) + 1
        func clamp(_ i: Int) -> Int { min(max(i, 0), count - 1) }
        return RulerMapping(
            tickCount: count,
            value: { i in range.lowerBound * pow(2, Double(clamp(i)) / Double(ticksPerDoubling)) },
            index: { v in clamp(Int((log2(max(v, range.lowerBound) / range.lowerBound) * Double(ticksPerDoubling)).rounded())) },
            isMajor: { i in i % ticksPerDoubling == 0 }
        )
    }
}

/// Subtle haptics for the ruler: a faint tick for each step (rate-limited so a fast flick does not buzz), a firmer one on
/// the major ticks and a distinct one at the neutral/snap values. Generators are kept and prepared, not recreated.
final class RulerHaptics {
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private var lastMinor = Date.distantPast

    func prepare() { soft.prepare(); light.prepare() }

    func minor() {
        let now = Date()
        guard now.timeIntervalSince(lastMinor) > 0.055 else { return }
        lastMinor = now
        soft.impactOccurred(intensity: 0.3)
    }

    func major() { soft.impactOccurred(intensity: 0.6) }
    func detent() { light.impactOccurred(intensity: 0.7) }
}

/// A horizontal ruler like the one in the Photos editor: drag it sideways, the tick in the middle is the value. Ticks
/// stand on a baseline; there is no fixed marker - whichever tick is in the middle *becomes* the centre mark (accent
/// colour, a little taller than a major tick). All three lines are 1.5 pt wide: minor = grey, major = dark and goes back to a minor/major tick when the next one takes over. A small dot over
/// the `neutral` tick shows where "unchanged" is. Built on `ScrollView`, so it has the system's momentum. `onEditingChanged(false)` fires only after the ruler has
/// come to rest, not when the finger lifts.
struct RulerDial: View {
    @Binding var value: Double
    let mapping: RulerMapping
    var detents: [Double] = []
    /// The "unchanged" value: gets a dot over its tick while the ruler is somewhere else.
    var neutral: Double?
    var haptics = true
    var tickSpacing: CGFloat = 9
    let format: (Double) -> String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var position: Int?
    @State private var isTouching = false
    @State private var settleTask: Task<Void, Never>?
    @State private var isEditing = false
    @State private var haptic = RulerHaptics()

    private let rulerHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 6) {
            Text(format(value))
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.12), value: value)
                .accessibilityIdentifier("rulerReadout")
            ruler
        }
    }

    private var ruler: some View {
        let center = position ?? mapping.index(value)
        let neutralIndex = neutral.map(mapping.index)
        return GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<mapping.tickCount, id: \.self) { index in
                        tick(index, center: center, isNeutral: index == neutralIndex)
                            .frame(width: tickSpacing).id(index)
                    }
                }
                .scrollTargetLayout()
                .animation(.easeOut(duration: 0.14), value: center)
            }
            .contentMargins(.horizontal, max(0, proxy.size.width / 2 - tickSpacing / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in touchBegan() }
                    .onEnded { _ in touchEnded() }
            )
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                       .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
        }
        .frame(height: rulerHeight)
        .task { position = mapping.index(value) }
        .onAppear { haptic.prepare() }
        .onChange(of: position) { old, new in
            guard let new else { return }
            let v = mapping.value(new)
            if v != value { value = v }
            if haptics, let old, old != new { tickFeedback(from: mapping.value(old), to: v, major: mapping.isMajor(new)) }
        }
        .onChange(of: value) { _, new in
            // Moved from outside (reset, a gesture on the stage): bring the ruler along, unless the user is on it.
            let target = mapping.index(new)
            if target != position && !isEditing { withAnimation(.easeOut(duration: 0.2)) { position = target } }
        }
        .accessibilityElement()
        .accessibilityIdentifier("ruler")
        .accessibilityLabel("Ruler")
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let current = mapping.index(value)
            position = mapping.index(mapping.value(direction == .increment ? current + 1 : current - 1))
        }
    }

    /// Three kinds of line, all standing on the baseline: minor tick, major tick, and the centre mark - which is just
    /// the tick that happens to be in the middle right now.
    private func tick(_ index: Int, center: Int, isNeutral: Bool) -> some View {
        let isCenter = index == center
        let major = mapping.isMajor(index)
        return ZStack(alignment: .bottom) {
            if isNeutral && !isCenter {
                Circle().fill(Color.secondary.opacity(0.9)).frame(width: 6, height: 6)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            Rectangle()
                .fill(isCenter ? Color.accentColor : (major ? Color.primary.opacity(0.5) : Color(.systemGray2)))
                .frame(width: 1.5, height: isCenter ? 30 : (major ? 22 : 16))
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: Editing state + haptics

    private func touchBegan() {
        settleTask?.cancel()
        isTouching = true
        if !isEditing { isEditing = true; onEditingChanged(true) }
    }

    /// The finger lifted, but momentum may carry on: editing ends once the position has held still for a moment.
    private func touchEnded() {
        isTouching = false
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            var last = position
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled || isTouching { return }
                if position == last { break }
                last = position
            }
            if isEditing { isEditing = false; onEditingChanged(false) }
        }
    }

    private func tickFeedback(from old: Double, to new: Double, major: Bool) {
        let crossed = detents.contains { ($0 - old) * ($0 - new) <= 0 && old != new }
        if crossed { haptic.detent() } else if major { haptic.major() } else { haptic.minor() }
    }
}
