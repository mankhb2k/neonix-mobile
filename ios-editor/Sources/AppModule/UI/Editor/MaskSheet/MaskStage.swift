import SwiftUI

/// The picture with the Mask tool's mask applied live and its yellow outline + handles on top (CapCut's look): drag inside the shape to move it, the round
/// handles to size it (right = width, top = height), to feather it (the chevron under it - pulled further out = softer) and, on a rectangle, to round its
/// corners (top-left); a twist of two fingers turns it. The mask is a `MaskDraft`; what is drawn is its `V2Mask` through `MaskMatteView`, the same as the
/// editor's renderer draws.
struct MaskStage: View {
    let image: UIImage?
    @Binding var draft: MaskDraft
    /// Draws the picture without any mask (while the outline is still being placed, or to compare).
    var showsMask = true

    var body: some View {
        GeometryReader { geo in
            let aspect = image.map { $0.size.width / $0.size.height } ?? 0.75
            let display = fit(aspect, in: CGRect(origin: .zero, size: geo.size))
            ZStack {
                Checkerboard().frame(width: display.width, height: display.height).position(x: display.midX, y: display.midY)
                if let image {
                    Image(uiImage: image).resizable()
                        .frame(width: display.width, height: display.height)
                        .mask { matte(size: display.size) }
                        .position(x: display.midX, y: display.midY)
                } else {
                    ProgressView()
                }
                MaskHandlesLayer(draft: $draft, display: display)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("maskStage")
            .accessibilityValue(String(format: "%.3f,%.3f,%.3f,%.3f,%.3f", draft.centerX, draft.centerY, draft.width, draft.height, draft.roundness))
        }
    }

    @ViewBuilder private func matte(size: CGSize) -> some View {
        if showsMask, let mask = draft.v2Mask(id: "stage", frame: size) {
            MaskMatteView(mask: mask, size: size)
        } else {
            Rectangle()
        }
    }

    private func fit(_ aspect: CGFloat, in box: CGRect) -> CGRect {
        let inner = box.insetBy(dx: 14, dy: 14)
        let width = min(inner.width, inner.height * aspect), height = width / aspect
        return CGRect(x: inner.midX - width / 2, y: inner.midY - height / 2, width: width, height: height)
    }
}

/// The yellow outline and round handles of a mask and the gestures that edit it, drawn over `display` (the picture's rectangle, in this view's own
/// coordinates; the view itself is the hit area, so handles may sit outside `display`). Shared by the lab's `MaskStage` and the editor's overlay on the live
/// stage (`MaskGestureOverlay`).
struct MaskHandlesLayer: View {
    @Binding var draft: MaskDraft
    let display: CGRect
    /// Called once when a drag or twist starts, so the editor can open one undo step for it.
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    private enum Handle { case width, height, feather, roundness }
    private enum Drag { case move(startX: Double, startY: Double), handle(Handle) }
    @State private var drag: Drag?
    @State private var twistStart: Double?

    private let yellow = Color(red: 1, green: 0.84, blue: 0.04)
    private let grab: CGFloat = 40
    private let offset: CGFloat = 30
    private let featherReach: CGFloat = 0.15

    var body: some View {
        let short = min(display.width, display.height)
        ZStack {
            Color.clear.contentShape(Rectangle())
            if draft.shape != .none { outline(display: display, short: short) }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { change($0, display: display, short: short) }
            .onEnded { _ in drag = nil; onEnd() })
        .simultaneousGesture(RotateGesture()
            .onChanged { value in
                if twistStart == nil { onBegin(); twistStart = draft.rotation }
                draft.rotation = wrap((twistStart ?? 0) + value.rotation.degrees)
            }
            .onEnded { _ in twistStart = nil; onEnd() })
    }

    private func wrap(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private struct Axes {
        let center: CGPoint
        let u: CGVector   // along the shape's width
        let v: CGVector   // along its height, pointing down
        func point(_ du: CGFloat, _ dv: CGFloat) -> CGPoint { CGPoint(x: center.x + u.dx * du + v.dx * dv, y: center.y + u.dy * du + v.dy * dv) }
        func local(_ p: CGPoint) -> CGPoint {
            let dx = p.x - center.x, dy = p.y - center.y
            return CGPoint(x: dx * u.dx + dy * u.dy, y: dx * v.dx + dy * v.dy)
        }
    }

    private func axes(display: CGRect) -> Axes {
        let angle = draft.rotation * .pi / 180
        return Axes(center: CGPoint(x: display.minX + draft.centerX * display.width, y: display.minY + draft.centerY * display.height),
                    u: CGVector(dx: cos(angle), dy: sin(angle)), v: CGVector(dx: -sin(angle), dy: cos(angle)))
    }

    /// Where each handle sits (nil when the shape has none).
    private func handlePoints(_ a: Axes, short: CGFloat) -> [Handle: CGPoint] {
        var points: [Handle: CGPoint] = [:]
        let halfW = CGFloat(draft.width) * short / 2, halfH = CGFloat(draft.height) * short / 2
        let reach = CGFloat(draft.feather) * featherReach * short
        if draft.shape.hasWidth { points[.width] = a.point(halfW + offset, 0) }
        if draft.shape.hasHeight { points[.height] = a.point(0, -(halfH + offset)) }
        let below: CGFloat = draft.shape == .horizontal ? 0 : halfH
        points[.feather] = a.point(0, below + offset + reach)
        if draft.shape == .rectangle {
            // Outside the top-left corner at no rounding, sliding in along the diagonal as the corners round off: it stays under the finger.
            let slide = CGFloat(draft.roundness) * min(halfW, halfH)
            points[.roundness] = a.point(-(halfW + 20) + slide, -(halfH + 20) + slide)
        }
        return points
    }

    // MARK: Gestures

    private func change(_ value: DragGesture.Value, display: CGRect, short: CGFloat) {
        guard draft.shape != .none else { return }
        let a = axes(display: display)
        if drag == nil {
            let hit = handlePoints(a, short: short).min { distance($0.value, value.startLocation) < distance($1.value, value.startLocation) }
            if let hit, distance(hit.value, value.startLocation) < grab {
                drag = .handle(hit.key)
            } else if inside(a.local(value.startLocation), short: short) {
                drag = .move(startX: draft.centerX, startY: draft.centerY)
            }
            if drag != nil { onBegin() }
        }
        switch drag {
        case .move(let startX, let startY):
            draft.centerX = min(max(startX + value.translation.width / display.width, 0), 1)
            draft.centerY = min(max(startY + value.translation.height / display.height, 0), 1)
        case .handle(let handle):
            let p = a.local(value.location)
            switch handle {
            case .width: draft.width = min(max(Double((abs(p.x) - offset) * 2 / short), 0.05), 2)
            case .height: draft.height = min(max(Double((abs(p.y) - offset) * 2 / short), 0.05), 2)
            case .feather:
                let edge: CGFloat = draft.shape == .horizontal ? 0 : CGFloat(draft.height) * short / 2
                draft.feather = min(max(Double((p.y - edge - offset) / (featherReach * short)), 0), 1)
            case .roundness:
                let halfW = CGFloat(draft.width) * short / 2, halfH = CGFloat(draft.height) * short / 2
                let slide = ((p.x + halfW + 20) + (p.y + halfH + 20)) / 2   // how far in along the diagonal the finger has gone
                draft.roundness = min(max(Double(slide / max(min(halfW, halfH), 1)), 0), 1)
            }
        case nil:
            break
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Whether a point (in the shape's own axes, centre at 0) is on the shape - or, for the half-plane and the band, near enough its line.
    private func inside(_ p: CGPoint, short: CGFloat) -> Bool {
        let halfW = CGFloat(draft.width) * short / 2, halfH = CGFloat(draft.height) * short / 2
        switch draft.shape {
        case .none: return false
        case .horizontal: return abs(p.y) < 44
        case .mirror: return abs(p.y) < max(halfH, 22) + 22
        case .circle: return (p.x * p.x) / (max(halfW, 1) * max(halfW, 1)) + (p.y * p.y) / (max(halfH, 1) * max(halfH, 1)) <= 1.2
        case .rectangle: return abs(p.x) <= halfW + 12 && abs(p.y) <= halfH + 12
        }
    }

    // MARK: Outline and handles

    @ViewBuilder private func outline(display: CGRect, short: CGFloat) -> some View {
        let a = axes(display: display)
        let halfW = CGFloat(draft.width) * short / 2, halfH = CGFloat(draft.height) * short / 2
        let long = max(display.width, display.height) * 3
        ZStack {
            Canvas { context, _ in
                func line(_ dv: CGFloat) {
                    context.stroke(Path { p in p.move(to: a.point(-long, dv)); p.addLine(to: a.point(long, dv)) }, with: .color(yellow), lineWidth: 2)
                }
                switch draft.shape {
                case .none: break
                case .horizontal: line(0)
                case .mirror: line(-halfH); line(halfH)
                case .circle:
                    var path = Path(ellipseIn: CGRect(x: -halfW, y: -halfH, width: 2 * halfW, height: 2 * halfH))
                    path = path.applying(CGAffineTransform(rotationAngle: draft.rotation * .pi / 180)).applying(CGAffineTransform(translationX: a.center.x, y: a.center.y))
                    context.stroke(path, with: .color(yellow), lineWidth: 2)
                case .rectangle:
                    let radius = CGFloat(draft.roundness) * min(halfW, halfH)
                    var path = Path(roundedRect: CGRect(x: -halfW, y: -halfH, width: 2 * halfW, height: 2 * halfH), cornerSize: CGSize(width: radius, height: radius), style: .continuous)
                    path = path.applying(CGAffineTransform(rotationAngle: draft.rotation * .pi / 180)).applying(CGAffineTransform(translationX: a.center.x, y: a.center.y))
                    context.stroke(path, with: .color(yellow), lineWidth: 2)
                }
                context.stroke(Path(ellipseIn: CGRect(x: a.center.x - 9, y: a.center.y - 9, width: 18, height: 18)), with: .color(yellow), lineWidth: 1.5)
            }
            .allowsHitTesting(false)
            ForEach(Array(handlePoints(a, short: short)), id: \.key.hashValue) { entry in
                Image(systemName: symbol(entry.key))
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
                    .frame(width: 32, height: 32).background(Color.white, in: Circle()).shadow(color: .black.opacity(0.25), radius: 2)
                    .position(entry.value)
                    .allowsHitTesting(false)
            }
        }
    }

    private func symbol(_ handle: Handle) -> String {
        switch handle {
        case .width: return "arrow.left.and.right"
        case .height: return "arrow.up.and.down"
        case .feather: return "chevron.down.2"
        case .roundness: return "square.on.square.squareshape.controlhandles"
        }
    }
}

/// Grey squares behind the picture, so what the mask hides reads as transparent.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 12
            for row in 0..<Int(ceil(size.height / step)) {
                for column in 0..<Int(ceil(size.width / step)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step)), with: .color(Color(.systemGray5)))
                }
            }
        }
        .background(Color(.systemGray6))
    }
}
