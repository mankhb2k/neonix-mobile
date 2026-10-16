import SwiftUI

/// The vertical axis of the speed graph (user 2026-10-15): three lines - 9x at the top, 1x in the middle, 0.1x at the bottom - with each half
/// logarithmic, so 1x is exactly in the middle and both slowing down and speeding up have room.
enum SpeedGraphAxis {
    /// 0 (bottom, 0.1x) ... 1 (top, 9x) for a speed.
    static func level(forRate rate: Double) -> Double {
        let r = SpeedScale.clamped(rate)
        return r <= 1 ? 0.5 * (log10(r) + 1) : 0.5 + 0.5 * log10(r) / log10(SpeedScale.maximum)
    }

    /// The speed at a level; close to the middle line it snaps to exactly 1x.
    static func rate(forLevel level: Double) -> Double {
        let u = min(max(level, 0), 1)
        if abs(u - 0.5) < 0.025 { return 1 }
        return u <= 0.5 ? pow(10, 2 * u - 1) : pow(SpeedScale.maximum, 2 * u - 1)
    }
}

/// CapCut's "Custom" speed graph: the clip's source footage runs left to right, the line is its speed, the circles are the beats. Drag a beat up to
/// speed that part up, down to slow it; the first and last beats only move vertically. A white line marks the playhead; grab it (its round handle on top, or the line) to move it along the footage.
struct SpeedCurveEditor: View {
    @Binding var points: [V2SpeedPoint]
    @Binding var selected: Int?
    let span: Double
    /// Where the playhead is in the source footage, 0...1 (nil = outside the clip).
    var playheadFraction: Double?
    let onChange: () -> Void
    /// The playhead was dragged to this fraction of the footage (0...1) / the drag ended.
    var onSeek: (Double) -> Void = { _ in }
    var onSeekEnd: () -> Void = {}

    @State private var dragging: Int?
    @State private var draggingPlayhead = false

    private let inset: CGFloat = 16
    private let hitRadius: CGFloat = 26
    private let gripRadius: CGFloat = 8
    /// Beats keep at least this much of the width between them.
    private let minGap = 0.03

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(x: inset, y: 12, width: proxy.size.width - 2 * inset, height: proxy.size.height - 24)
            ZStack(alignment: .topLeading) {
                grid(plot)
                curvePath(plot)
                if let fraction = playheadFraction {
                    Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 1.5, height: plot.height)
                        .position(x: plot.minX + plot.width * fraction, y: plot.midY)
                    Circle().fill(Color.primary.opacity(0.85)).frame(width: 2 * gripRadius, height: 2 * gripRadius)
                        .position(x: plot.minX + plot.width * fraction, y: plot.minY)
                        .accessibilityHidden(true)
                }
                ForEach(points.indices, id: \.self) { index in beat(index, plot) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in drag(value.location, startLocation: value.startLocation, plot: plot) }
                .onEnded { _ in
                    dragging = nil
                    if draggingPlayhead { draggingPlayhead = false; onSeekEnd() }
                })
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("speedGraph")
    }

    // MARK: Drawing

    private func grid(_ plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([(9.0, "9x", true), (1.0, "1x", false), (0.1, "0.1x", true)], id: \.1) { rate, label, dashed in
                let y = plot.maxY - plot.height * SpeedGraphAxis.level(forRate: rate)
                Path { p in p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y)) }
                    .stroke(Color.secondary.opacity(dashed ? 0.5 : 0.8), style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
                Text(label).font(.caption2).foregroundColor(.secondary).position(x: plot.minX + 14, y: y - 8)
            }
        }
    }

    private func curvePath(_ plot: CGRect) -> some View {
        let curve = SpeedCurve(points: points, span: span)
        return Path { path in
            let steps = 120
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let rate = curve?.rate(atSource: fraction * span) ?? 1
                let point = CGPoint(x: plot.minX + plot.width * fraction, y: plot.maxY - plot.height * SpeedGraphAxis.level(forRate: rate))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func position(_ index: Int, _ plot: CGRect) -> CGPoint {
        CGPoint(x: plot.minX + plot.width * points[index].sourceMs / span, y: plot.maxY - plot.height * SpeedGraphAxis.level(forRate: points[index].rate))
    }

    private func beat(_ index: Int, _ plot: CGRect) -> some View {
        let on = selected == index
        return ZStack {
            Circle().fill(on ? Color.accentColor : Color(.systemBackground)).frame(width: 22, height: 22)
            Circle().strokeBorder(on ? Color.white : Color.primary, lineWidth: 2.5).frame(width: 22, height: 22)
            if on {
                Text(SpeedScale.label(points[index].rate)).font(.caption2.weight(.semibold)).foregroundColor(.primary)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color(.systemBackground).opacity(0.9), in: Capsule())
                    .offset(y: -22)
            }
        }
        .position(position(index, plot))
        .accessibilityElement()
        .accessibilityLabel("Beat \(index + 1), \(SpeedScale.label(points[index].rate))")
        .accessibilityIdentifier("speedBeat-\(index)")
    }

    // MARK: Dragging

    private func drag(_ location: CGPoint, startLocation: CGPoint, plot: CGRect) {
        if draggingPlayhead {
            onSeek(min(max((location.x - plot.minX) / plot.width, 0), 1))
            return
        }
        if dragging == nil {
            // The playhead's round handle wins over a beat sitting on the line; its line loses to a beat.
            if let fraction = playheadFraction {
                let x = plot.minX + plot.width * fraction
                let onGrip = distance(CGPoint(x: x, y: plot.minY), startLocation) <= hitRadius * 0.7
                let nearBeat = points.indices.contains { distance(position($0, plot), startLocation) <= hitRadius }
                let onLine = abs(startLocation.x - x) <= 14 && !nearBeat
                if onGrip || onLine {
                    draggingPlayhead = true
                    selected = nil
                    onSeek(min(max((location.x - plot.minX) / plot.width, 0), 1))
                    return
                }
            }
            // The nearest beat to where the finger went down, if it is close enough.
            let nearest = points.indices.min { distance(position($0, plot), startLocation) < distance(position($1, plot), startLocation) }
            guard let nearest, distance(position(nearest, plot), startLocation) <= hitRadius else { selected = nil; return }   // a touch on empty graph deselects
            dragging = nearest
            selected = nearest
        }
        guard let index = dragging, index < points.count else { return }
        var point = points[index]
        point.slope = nil
        point.rate = SpeedGraphAxis.rate(forLevel: (plot.maxY - location.y) / plot.height)
        if index != 0 && index != points.count - 1 {
            let low = points[index - 1].sourceMs / span + minGap, high = points[index + 1].sourceMs / span - minGap
            point.sourceMs = min(max((location.x - plot.minX) / plot.width, low), max(high, low)) * span
        }
        points[index] = point
        onChange()
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
}

extension SpeedCurveEditor {
    /// The default: five beats spread evenly over the clip, all at `rate`.
    static func flatPoints(rate: Double, span: Double) -> [V2SpeedPoint] {
        (0..<5).map { V2SpeedPoint(sourceMs: span * Double($0) / 4, rate: rate) }
    }

    /// A beat added at the source fraction `fraction` on the existing curve (same speed there), or in the middle of the widest gap when `fraction`
    /// is nil or too close to a beat. Returns the new beat's index.
    static func addingBeat(to points: inout [V2SpeedPoint], span: Double, at fraction: Double?) -> Int? {
        let curve = SpeedCurve(points: points, span: span)
        var x: Double
        if let fraction, fraction > 0.03, fraction < 0.97, points.allSatisfy({ abs($0.sourceMs / span - fraction) > 0.04 }) {
            x = fraction * span
        } else {
            guard let gap = (1..<points.count).max(by: { points[$0].sourceMs - points[$0 - 1].sourceMs < points[$1].sourceMs - points[$1 - 1].sourceMs }),
                  points[gap].sourceMs - points[gap - 1].sourceMs > span * 0.08 else { return nil }
            x = (points[gap].sourceMs + points[gap - 1].sourceMs) / 2
        }
        let beat = V2SpeedPoint(sourceMs: x, rate: curve?.rate(atSource: x) ?? 1)
        let index = points.firstIndex { $0.sourceMs > x } ?? points.count - 1
        points.insert(beat, at: index)
        // The curve before and after the new beat is recomputed from the beats; they keep their own (automatic) shape.
        points = points.map { V2SpeedPoint(sourceMs: $0.sourceMs, rate: $0.rate) }
        return index
    }
}
