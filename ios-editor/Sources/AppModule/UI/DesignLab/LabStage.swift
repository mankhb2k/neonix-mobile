import SwiftUI

/// A stand-in for the editor's stage: a 9:16 canvas with one layer that follows a `LabTransform`, centre guides
/// that light up at 0, and (optionally) the direct-manipulation gestures - drag, pinch, twist.
struct LabStage: View {
    @Binding var transform: LabTransform
    var gesturesEnabled = true

    @State private var dragBase: (x: Double, y: Double)?
    @State private var pinchBase: Double?
    @State private var twistBase: Double?

    var body: some View {
        GeometryReader { proxy in
            let k = proxy.size.width / 1080   // composition px -> points
            ZStack {
                Color(.tertiarySystemBackground)
                guides(size: proxy.size)
                layer(k)
            }
            .contentShape(Rectangle())
            .gesture(gestures(k), including: gesturesEnabled ? .all : .none)
            .clipped()
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("labStage")
    }

    private func layer(_ k: Double) -> some View {
        RoundedRectangle(cornerRadius: 24 * k, style: .continuous)
            .fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text("Photo").font(.system(size: 90 * k, weight: .bold)).foregroundColor(.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 24 * k, style: .continuous).stroke(Color.accentColor, lineWidth: 3))
            .frame(width: 540 * k, height: 720 * k)
            .scaleEffect(transform.scale)
            .rotationEffect(.degrees(transform.rotation))
            .offset(x: transform.x * k, y: transform.y * k)
            .opacity(transform.opacity)
    }

    @ViewBuilder private func guides(size: CGSize) -> some View {
        if abs(transform.x) < 0.5 {
            Rectangle().fill(Color.yellow.opacity(0.9)).frame(width: 1).frame(maxHeight: .infinity)
        }
        if abs(transform.y) < 0.5 {
            Rectangle().fill(Color.yellow.opacity(0.9)).frame(height: 1).frame(maxWidth: .infinity)
        }
    }

    private func gestures(_ k: Double) -> some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                if dragBase == nil { dragBase = (transform.x, transform.y) }
                guard let base = dragBase else { return }
                transform.x = min(max(base.x + value.translation.width / k, -1080), 1080).rounded()
                transform.y = min(max(base.y + value.translation.height / k, -1920), 1920).rounded()
            }
            .onEnded { _ in dragBase = nil }
        let pinch = MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = transform.scale }
                transform.scale = min(max((pinchBase ?? 1) * value.magnification, 0.25), 4)
            }
            .onEnded { _ in pinchBase = nil }
        let twist = RotateGesture()
            .onChanged { value in
                if twistBase == nil { twistBase = transform.rotation }
                var degrees = (twistBase ?? 0) + value.rotation.degrees
                degrees = degrees.truncatingRemainder(dividingBy: 360)
                if degrees > 180 { degrees -= 360 } else if degrees < -180 { degrees += 360 }
                transform.rotation = degrees.rounded()
            }
            .onEnded { _ in twistBase = nil }
        return drag.simultaneously(with: pinch).simultaneously(with: twist)
    }
}
