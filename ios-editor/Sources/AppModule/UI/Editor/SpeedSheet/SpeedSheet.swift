import SwiftUI

/// The Speed tool, laid out like the Adjust and Transform sheets (user 2026-10-15): a NavigationStack with Reset (back to 1x) and Done, the
/// **ruler** on top (0.1x - 9x, one tick = 0.1x, opens on 1x, `SpeedScale`), and under it the round buttons that pick the mode - **Normal** (one speed
/// for the clip) and **Curve** (a speed graph, not built yet). Normal also shows the clip's length before and after ("Duration: 3.9s -> 3.2s").
/// The change is live on the stage and the timeline; the shell makes the whole session one undo step when the sheet closes.
struct SpeedSheet: View {
    /// How much source footage the clip plays, in ms (its length at 1x).
    let sourceSpanMs: Double
    let fps: Double
    let playheadFraction: Double?
    /// The playhead dragged on the graph: a fraction of the clip's footage / end of that drag.
    var onSeek: (Double) -> Void = { _ in }
    var onSeekEnd: () -> Void = {}
    let onRate: (Double) -> Void
    /// The speed curve, live (nil = back to a constant 1x).
    let onCurve: ([V2SpeedPoint]?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rate: Double
    @State private var mode: Mode
    @State private var points: [V2SpeedPoint]
    @State private var selectedBeat: Int?
    @State private var detent: PresentationDetent

    enum Mode: String, CaseIterable, Identifiable {
        case normal = "Normal", curve = "Curve"
        var id: String { rawValue }
        var symbol: String { self == .normal ? "speedometer" : "chart.xyaxis.line" }
    }

    /// `curve`: the clip's speed curve when it has one (the sheet then opens on Curve).
    init(rate: Double, curve: [V2SpeedPoint]?, sourceSpanMs: Double, fps: Double, playheadFraction: Double?,
         onSeek: @escaping (Double) -> Void = { _ in }, onSeekEnd: @escaping () -> Void = {},
         onRate: @escaping (Double) -> Void, onCurve: @escaping ([V2SpeedPoint]?) -> Void) {
        _rate = State(initialValue: SpeedScale.snapped(rate))
        _mode = State(initialValue: curve == nil ? .normal : .curve)
        _points = State(initialValue: curve ?? SpeedCurveEditor.flatPoints(rate: rate, span: sourceSpanMs))
        _detent = State(initialValue: curve == nil ? Self.normalHeight : Self.curveHeight)
        self.sourceSpanMs = sourceSpanMs
        self.fps = fps
        self.playheadFraction = playheadFraction
        self.onSeek = onSeek
        self.onSeekEnd = onSeekEnd
        self.onRate = onRate
        self.onCurve = onCurve
    }

    private static let normalHeight = PresentationDetent.height(300)
    private static let curveHeight = PresentationDetent.height(440)

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                switch mode {
                case .normal: normal
                case .curve: curve
                }
                buttons
            }
            .padding(.top, 8)
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { resetAll() } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(mode == .normal ? rate == 1 : points.allSatisfy { $0.rate == 1 })
                        .accessibilityLabel("Reset")
                        .accessibilityIdentifier("speed-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("speedDone")
                }
            }
        }
        .presentationDetents([Self.normalHeight, Self.curveHeight], selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: rate) { _, new in onRate(new) }
        .onChange(of: mode) { _, new in detent = new == .curve ? Self.curveHeight : Self.normalHeight }
    }

    // MARK: Normal

    private var normal: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Duration:").foregroundColor(.secondary)
                Text(seconds(sourceSpanMs)).foregroundColor(.secondary)
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundColor(.orange)
                Text(seconds(SpeedScale.duration(sourceMs: sourceSpanMs, rate: rate, fps: fps))).foregroundColor(.primary)
            }
            .font(.subheadline.monospacedDigit())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("speedDuration")
            RulerDial(value: $rate, mapping: .speed, detents: [1], neutral: 1, tickSpacing: 10, format: SpeedScale.label)
                .padding(.bottom, 8)
        }
    }

    // MARK: Curve

    private var curve: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Duration:").foregroundColor(.secondary)
                    Text(seconds(sourceSpanMs)).foregroundColor(.secondary)
                    Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundColor(.orange)
                    Text(seconds(SpeedCurve(points: points, span: sourceSpanMs)?.outputDuration ?? sourceSpanMs)).foregroundColor(.primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("speedDuration")
                Spacer()
                beatToggle
            }
            .font(.subheadline.monospacedDigit())
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            SpeedCurveEditor(points: $points, selected: $selectedBeat, span: sourceSpanMs, playheadFraction: playheadFraction, onChange: pushCurve,
                             onSeek: onSeek, onSeekEnd: onSeekEnd)
                .frame(height: 170)
        }
    }

    /// The beat the button would remove: an inner beat under the playhead, else the inner beat the finger picked. Nil = the button adds one.
    private var anchorIndex: Int? {
        if let fraction = playheadFraction,
           let near = points.indices.dropFirst().dropLast().first(where: { abs(points[$0].sourceMs / sourceSpanMs - fraction) < 0.03 }) { return near }
        if let index = selectedBeat, index > 0, index < points.count - 1 { return index }
        return nil
    }

    /// One icon: + adds a beat at the playhead; on a beat it becomes - and takes that beat away (CapCut's Add / Delete beat).
    private var beatToggle: some View {
        let removing = anchorIndex != nil
        return Button {
            if let index = anchorIndex {
                points.remove(at: index); selectedBeat = nil; pushCurve()
            } else if let index = SpeedCurveEditor.addingBeat(to: &points, span: sourceSpanMs, at: playheadFraction) {
                selectedBeat = index; pushCurve()
            }
        } label: {
            Image(systemName: removing ? "minus" : "plus").font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 32)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(removing ? "Delete beat" : "Add beat")
        .accessibilityIdentifier(removing ? "speedDeleteBeat" : "speedAddBeat")
    }

    /// The beats changed: tell the clip (a curve that is 1x everywhere removes it).
    private func pushCurve() { onCurve(points.allSatisfy { $0.rate == 1 } ? nil : points) }

    private func resetAll() {
        if mode == .normal { rate = 1; return }
        points = SpeedCurveEditor.flatPoints(rate: 1, span: sourceSpanMs)
        selectedBeat = nil
        onCurve(nil)
    }

    // MARK: Round buttons

    private var buttons: some View {
        HStack(spacing: 26) {
            ForEach(Mode.allCases) { item in
                let selected = mode == item
                Button { mode = item } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(selected ? Color.accentColor : Color(.secondarySystemBackground))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                        Text(item.rawValue).font(.caption2).foregroundColor(selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("speedMode-\(item.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func seconds(_ ms: Double) -> String { String(format: "%.1fs", ms / 1000) }
}
