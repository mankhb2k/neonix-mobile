import SwiftUI

/// Remove BG on video takes a while (every frame is cut once, `VideoMatteJob`): this card sits on the stage while it runs - a ring that fills with the percentage in the
/// middle, what is going on, and Cancel (the shell takes Remove BG off the clip again; the frames done are kept, so picking it again carries on from there).
struct RemoveBackgroundProgressCard: View {
    let fraction: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressRing(fraction: fraction)
                .frame(width: 64, height: 64)
            Text("Removing background")
                .font(.footnote.weight(.semibold))
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("removeBgCancel")
        }
        .padding(.horizontal, 26).padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("removeBgProgress")
    }
}

/// A track, an accent arc from 12 o'clock and the whole-number percentage in the middle.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ZStack {
            Circle().stroke(Color(.systemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: clamped)
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .accessibilityIdentifier("removeBgPercent")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}
