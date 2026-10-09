import SwiftUI

/// Tuỳ chỉnh — Curves' own dedicated sheet (confirmed with the user: "hãy
/// dựng UI riêng" — a separate screen, not squeezed into the ~64pt-tall
/// slider row every other Tuỳ chỉnh control lives in; a 160pt-square graph
/// simply doesn't fit there). Presented from `ToolOptionsPanel`'s "Curves"
/// button; `onCurveChanged` fires on every drag tick (same live-preview
/// contract every other Tuỳ chỉnh control already uses) and `onBegin`/
/// `onEnd` (passed straight through to `CurveGraphView`) still bracket one
/// undo step per individual handle drag, sheet or no sheet.
struct CurveEditorSheet: View {
    @Binding var points: [Double]
    let onBegin: () -> Void
    let onEnd: () -> Void
    let onCurveChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let identity: [Double] = [0, 0.25, 0.5, 0.75, 1]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                CurveGraphView(points: $points, onBegin: onBegin, onEnd: onEnd)
                    .frame(width: 280, height: 280)
                Button("Reset") {
                    onBegin()
                    points = Self.identity
                    onEnd()
                }
                .disabled(points == Self.identity)
                Spacer()
            }
            .padding()
            .onChange(of: points) { _, _ in onCurveChanged() }
            .navigationTitle("Curves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Tuỳ chỉnh — Curves: a real draggable tone-curve editor, replacing the
/// earlier Highlights/Shadows/Whites/Blacks parametrized-slider stand-in
/// (see CLAUDE.md's "Tuỳ chỉnh" notes). Exactly 5 draggable points at fixed
/// x-positions (`0, 0.25, 0.5, 0.75, 1`) — matching `CIToneCurve`'s own
/// hard 5-point limit (`FilterRenderer.toneCurve`), so there's nothing to
/// resample: the point the user drags *is* the value that reaches Core
/// Image, verbatim. Only a point's own y (output level) is draggable; x
/// never moves, so points can't cross or reorder — no clamping/validation
/// needed downstream (`EffectPresetKind.toneCurve` applies `points`
/// verbatim), matching this app's "UI proposes only valid values" rule.
struct CurveGraphView: View {
    @Binding var points: [Double]
    let onBegin: () -> Void
    let onEnd: () -> Void

    private let size: CGFloat = 160
    private let handleDiameter: CGFloat = 18

    var body: some View {
        ZStack {
            background
            curvePath
            ForEach(points.indices, id: \.self) { index in
                handle(at: index)
            }
        }
        .frame(width: size, height: size)
    }

    private var background: some View {
        Canvas { context, canvasSize in
            // A light grid (quarter lines) plus the straight diagonal
            // reference — "no change" is this line; the actual curve
            // (drawn separately, see `curvePath`) deviating from it is
            // the whole point of the graph.
            let gridColor = Color.secondary.opacity(0.2)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let x = fraction * canvasSize.width
                let y = fraction * canvasSize.height
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: canvasSize.height)) }, with: .color(gridColor))
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: canvasSize.width, y: y)) }, with: .color(gridColor))
            }
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: canvasSize.height)); $0.addLine(to: CGPoint(x: canvasSize.width, y: 0)) },
                with: .color(.secondary.opacity(0.4)), lineWidth: 1
            )
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The actual curve — a smooth spline through the 5 points (Catmull-Rom
    /// → cubic Bezier, same technique `TimelineView`'s own waveform curve
    /// already uses), not straight segments between them.
    private var curvePath: some View {
        Canvas { context, canvasSize in
            let canvasPoints = points.enumerated().map { index, value -> CGPoint in
                CGPoint(x: CGFloat(index) / 4 * canvasSize.width, y: (1 - CGFloat(value)) * canvasSize.height)
            }
            context.stroke(smoothPath(through: canvasPoints), with: .color(.accentColor), lineWidth: 2)
        }
    }

    private func handle(at index: Int) -> some View {
        let x = CGFloat(index) / 4 * size
        let y = (1 - CGFloat(points[index])) * size
        return Circle()
            .fill(Color(.systemBackground))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: handleDiameter, height: handleDiameter)
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onBegin()
                        points[index] = Double(1 - min(max(value.location.y / size, 0), 1))
                    }
                    .onEnded { _ in onEnd() }
            )
    }

    /// Catmull-Rom → Bezier — identical technique to `TimelineView`'s
    /// `WaveformCurveView.smoothPath(through:)`, duplicated rather than
    /// shared since that one is `private` to a different file and this is
    /// a small, self-contained piece of math.
    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 0..<(pts.count - 1) {
            let p0 = i == 0 ? pts[i] : pts[i - 1]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}
