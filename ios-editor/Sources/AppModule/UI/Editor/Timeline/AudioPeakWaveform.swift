import SwiftUI

/// The peak waveform of a standalone audio clip (user 2026-10-17, chosen in the Design Lab: "C Peaks · both", cyan, full row, 1 pt lines,
/// no gap, gain 0.90): one hairline per point, as tall as the loudest sample under it, mirrored around the middle of the row.
///
/// **Scale** (measured on a real iPhone recording, 2026-10-17): a column's height is `(peak / the file's loudest peak) ^ curve`. Scaling to a
/// percentile instead of the maximum cut off the loudest 0.5 % of the file at one height (2.7 % of the columns that made sound ended as flat
/// squares - exactly the spikes worth seeing); scaling to the maximum alone leaves most of the wave tiny, so the curve (< 1) lifts the
/// quiet parts without ever touching the order of the loud ones.
///
/// Only the part of the clip that is on screen is drawn (`localRange`, in points from the clip's left edge, widened to multiples of 256 pt
/// by the caller so scrolling does not redraw it every frame); the columns sit on absolute positions, so they do not shimmer while the
/// timeline moves. `trimStartMs` is where in the file the clip begins; the clip plays at normal speed.
/// The 45 % area of an audio clip's two-tone body (user 2026-10-17: "C Scaled + shade", two-tone, no badge): the part of the clip that is still audible -
/// the whole body when there is no fade, curving down at the ends that fade, along the same envelope the engine plays. A vector shape (no bitmap), so a
/// clip tens of thousands of points wide costs nothing; only the fades are sampled.
struct AudioFadeBodyShape: Shape {
    let durationMs: Double
    let fadeIn: V2AudioFade?
    let fadeOut: V2AudioFade?

    func path(in rect: CGRect) -> Path {
        guard durationMs > 0, rect.width > 0 else { return Path(rect) }
        let inMs = min(max(fadeIn?.duration ?? 0, 0), durationMs)
        let outMs = min(max(fadeOut?.duration ?? 0, 0), durationMs)
        // Where the envelope is not flat: both fades (all of the clip when they overlap).
        var times: [Double] = []
        func sample(_ from: Double, _ to: Double) {
            let steps = min(max(Int(rect.width * (to - from) / durationMs / 2), 6), 160)
            for i in 0...steps { times.append(from + (to - from) * Double(i) / Double(steps)) }
        }
        if inMs + outMs >= durationMs {
            sample(0, durationMs)
        } else {
            if inMs > 0 { sample(0, inMs) } else { times.append(0) }
            if outMs > 0 { sample(durationMs - outMs, durationMs) } else { times.append(durationMs) }
        }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        for t in times {
            let gain = AudioFadeEnvelope.gain(elapsedMs: t, durationMs: durationMs, fadeIn: fadeIn, fadeOut: fadeOut)
            path.addLine(to: CGPoint(x: rect.minX + rect.width * t / durationMs, y: rect.maxY - rect.height * gain))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct AudioPeakWaveform: View {
    let envelope: PeakEnvelope
    let trimStartMs: Double
    let pxPerMs: Double
    /// The part of the clip to draw, in points from its left edge.
    let localRange: Range<CGFloat>
    let height: CGFloat
    /// The clip's length and fades: each column is scaled by the fade's gain there (`AudioFadeEnvelope`), so the wave shrinks along a fade.
    let clipDurationMs: Double
    let fadeIn: V2AudioFade?
    let fadeOut: V2AudioFade?

    static let lineWidth: CGFloat = 1
    static let gap: CGFloat = 0
    static let gain: CGFloat = 0.9
    /// Exponent applied to the scaled peak: 1 = linear, smaller lifts quiet parts (0.6 keeps a real recording's median column near 0.3).
    static let curve: Double = 0.5
    static let color = Color.cyan

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0, pxPerMs > 0 else { return }
            let step = max(Self.lineWidth + Self.gap, 0.5)
            let columns = Int((size.width / step).rounded(.up))
            let values = envelope.values
            let mid = size.height / 2
            let msPerPoint = 1 / pxPerMs
            let bucketMs = envelope.bucketMs
            let reference = max(envelope.peak, 0.0001)
            var path = Path()
            for column in 0..<columns {
                let localX = localRange.lowerBound + CGFloat(column) * step
                let startMs = trimStartMs + Double(localX) * msPerPoint
                let lower = max(Int(startMs / bucketMs), 0)
                let upper = min(max(Int((startMs + Double(step) * msPerPoint) / bucketMs), lower), values.count - 1)
                guard lower < values.count else { break }
                var peak: Float = 0
                for i in lower...upper { peak = max(peak, values[i]) }
                let scaled = CGFloat(pow(Double(min(peak / reference, 1)), Self.curve))
                let fade = AudioFadeEnvelope.gain(elapsedMs: Double(localX) * msPerPoint, durationMs: clipDurationMs, fadeIn: fadeIn, fadeOut: fadeOut)
                let h = max(scaled * Self.gain * CGFloat(fade) * mid, 0.25)
                path.addRect(CGRect(x: CGFloat(column) * step, y: mid - h, width: Self.lineWidth, height: 2 * h))
            }
            context.fill(path, with: .color(Self.color))
        }
        .frame(width: max(localRange.upperBound - localRange.lowerBound, 0), height: height)
        .allowsHitTesting(false)
    }
}
