import SwiftUI

/// Design lab for how an audio clip's waveform is drawn. The reference (user 2026-10-17) is the dense **peak waveform** of sound libraries
/// (Freesound / SoundCloud): one hairline per pixel column, as tall as the loudest sample under it, so speech and transients show as spikes
/// instead of a smoothed curve. The editor wants only its **upper half** - the baseline sits at the bottom of the clip row and the lines
/// rise from it. Three drawings to compare on fake audio: **A** the smooth curve the timeline draws today, **B** peaks, top half only
/// (the new look), **C** peaks mirrored around the middle (the reference as is). Fake data only; the same drawing is shown big on a dark
/// panel, on a mock lane clip at the real row heights, and at any zoom (the clip's width).
struct AudioWaveLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case smooth = "A Smooth", top = "B Peaks · top", mirrored = "C Peaks · both"
        var id: String { rawValue }
        var summary: String {
            switch self {
            case .smooth: return "What the timeline draws now: a smoothed curve through the loudness, filled below"
            case .top: return "The reference's peaks, upper half only: hairlines rise from the baseline, as tall as the loudest sample under each"
            case .mirrored: return "The reference as it is: the same peaks mirrored around the middle line"
            }
        }
    }

    enum Profile: String, CaseIterable, Identifiable {
        case voice = "Voice", music = "Music", sample = "Sample file"
        var id: String { rawValue }
    }

    enum Tint: String, CaseIterable, Identifiable {
        case grey = "Grey", white = "White", cyan = "Cyan"
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .grey: return Color(white: 0.72)
            case .white: return .white
            case .cyan: return .cyan
            }
        }
    }

    enum RowHeight: String, CaseIterable, Identifiable {
        case half = "Half row", full = "Full row"
        var id: String { rawValue }
    }

    @State private var variant: Variant = .top
    @State private var profile: Profile = .voice
    @State private var tint: Tint = .grey
    @State private var rowHeight: RowHeight = .full
    @State private var lineWidth = 1.0
    @State private var gap = 0.0
    @State private var gain = 1.0
    /// Exponent on the scaled peak (1 = linear); the editor uses 0.6.
    @State private var curve = 0.6
    /// The bundled sample's real peaks (`PeakWaveformCache`), scaled to its loudest peak; nil until decoded.
    @State private var sampleFile: [Float]?
    @State private var clipWidth = 320.0

    private var samples: [Float] { profile == .sample ? (sampleFile ?? []) : LabWaveData.samples(profile) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Drawing", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            .accessibilityIdentifier("audioWaveVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    bigPanel
                    laneMock(title: "Lane clip, 30 pt row (text / audio rows)", height: 30)
                    laneMock(title: "Lane clip, 48 pt row (the main lane's height)", height: 48)
                    controls
                }
                .padding()
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task {
            guard let url = bundledURL(filename: "audio-demo.mp3"), let envelope = await PeakWaveformCache.shared.envelope(url: url) else { return }
            let reference = max(envelope.peak, 0.0001)
            sampleFile = envelope.values.map { $0 / reference }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("audioWaveClose")
            Spacer()
            Text("Audio waveform lab").font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
    }

    /// The reference's own setting: the wave on a dark panel, full width.
    private var bigPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On a dark panel").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            LabWaveform(samples: samples, variant: variant, lineWidth: lineWidth, gap: gap, gain: gain, curve: curve, color: tint.color)
                .frame(height: variant == .top || variant == .smooth ? 70 : 100)
                .padding(.horizontal, 10).padding(.vertical, 12)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("audioWaveBig")
        }
    }

    /// The wave inside a clip block like the timeline's (cyan tint on the lane's runway), at the zoom set below.
    private func laneMock(title: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(.secondarySystemBackground))
                        .frame(width: max(clipWidth + 80, 340), height: height)
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(Color.cyan.opacity(0.45))
                        LabWaveform(samples: samples, variant: variant, lineWidth: lineWidth, gap: gap, gain: gain, curve: curve, color: tint == .grey ? .cyan.opacity(0.9) : tint.color)
                            .frame(height: rowHeight == .half ? height / 2 : height - 4)
                            .padding(.bottom, 2)
                    }
                    .frame(width: clipWidth, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.leading, 8)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                picker("Audio", $profile)
                picker("Colour", $tint)
                picker("Height in a lane", $rowHeight)
            }
            slider("Zoom (clip width)", value: $clipWidth, range: 60...1200, format: "%.0f pt")
            slider("Line width", value: $lineWidth, range: 0.5...3, format: "%.1f pt")
            slider("Gap between lines", value: $gap, range: 0...3, format: "%.1f pt")
            slider("Gain (taller peaks)", value: $gain, range: 0.5...1.6, format: "%.2f×")
            slider("Curve (lifts quiet parts)", value: $curve, range: 0.3...1, format: "%.2f")
        }
    }

    private func picker<T: Hashable & CaseIterable & Identifiable & RawRepresentable>(_ title: String, _ selection: Binding<T>) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Picker(title, selection: selection) {
                ForEach(T.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

/// One waveform drawing; `samples` are loudness peaks 0...1, however many - they are bucketed to the columns the width gives.
/// Peaks: one hairline of `lineWidth` every `lineWidth + gap` pt, as tall as the loudest sample in its bucket (at least a hairline, so
/// silence still draws a baseline). `top`: the lines stand on the bottom edge; `mirrored`: they are centred; `smooth`: the timeline's current
/// curve (average loudness per column, smoothed, filled).
struct LabWaveform: View {
    let samples: [Float]
    let variant: AudioWaveLabView.Variant
    var lineWidth: Double = 1
    var gap: Double = 0
    var gain: Double = 1
    /// Exponent on each peak (1 = linear, smaller lifts quiet parts).
    var curve: Double = 1
    var color: Color = .gray
    /// A factor (0...1) per column, from the column's position along the width (0...1) - a fade; nil = none.
    var envelope: ((CGFloat) -> CGFloat)?

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty, size.width > 0, size.height > 0 else { return }
            let step = max(lineWidth + gap, 0.5)
            let columns = max(Int(size.width / step), 1)
            var peaks = [CGFloat](repeating: 0, count: columns)
            var means = [CGFloat](repeating: 0, count: columns)
            for column in 0..<columns {
                let lower = column * samples.count / columns
                let upper = min(max((column + 1) * samples.count / columns, lower + 1), samples.count)
                var peak: Float = 0, sum: Float = 0
                for i in lower..<upper { peak = max(peak, samples[i]); sum += samples[i] }
                let factor = envelope?(CGFloat(column) / CGFloat(max(columns - 1, 1))) ?? 1
                peaks[column] = min(CGFloat(pow(Double(peak), curve)) * CGFloat(gain), 1) * factor
                means[column] = min(CGFloat(pow(Double(sum / Float(upper - lower)), curve)) * CGFloat(gain) * 1.6, 1)
            }
            switch variant {
            case .top:
                for column in 0..<columns {
                    let h = max(peaks[column] * size.height, 0.5)
                    context.fill(Path(CGRect(x: CGFloat(column) * step, y: size.height - h, width: lineWidth, height: h)), with: .color(color))
                }
            case .mirrored:
                let mid = size.height / 2
                for column in 0..<columns {
                    let h = max(peaks[column] * mid, 0.25)
                    context.fill(Path(CGRect(x: CGFloat(column) * step, y: mid - h, width: lineWidth, height: 2 * h)), with: .color(color))
                }
            case .smooth:
                let points = (0..<columns).map { CGPoint(x: CGFloat($0) * step, y: size.height - means[$0] * size.height * 0.8) }
                var line = Path()
                line.move(to: points[0])
                for i in 1..<points.count {
                    let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
                    line.addQuadCurve(to: mid, control: points[i - 1])
                }
                if let last = points.last { line.addLine(to: last) }
                var fill = line
                fill.addLine(to: CGPoint(x: points.last?.x ?? 0, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                context.fill(fill, with: .color(color.opacity(0.35)))
                context.stroke(line, with: .color(color), lineWidth: 1.5)
            }
        }
        .drawingGroup()
    }
}

/// Fake loudness peaks with a seeded generator, so the lab shows the same audio every time. Voice: phrases with silence between and
/// sharp consonant spikes; Music: a steady body with a beat.
enum LabWaveData {
    private static var cache: [AudioWaveLabView.Profile: [Float]] = [:]

    static func samples(_ profile: AudioWaveLabView.Profile) -> [Float] {
        if let hit = cache[profile] { return hit }
        var state: UInt64 = profile == .voice ? 0x9E3779B97F4A7C15 : 0xD1B54A32D192ED03
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
        let count = 1400   // a few samples per column at phone widths, so neighbouring columns differ like real peaks do
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let envelope: Double
            switch profile {
            case .voice:
                // Four phrases, each a few syllable swells, with quiet gaps.
                let phrases: [(Double, Double)] = [(0.04, 0.22), (0.30, 0.46), (0.52, 0.74), (0.80, 0.93)]
                var e = 0.0
                for (a, b) in phrases where t >= a && t <= b {
                    let u = (t - a) / (b - a)
                    e = max(e, sin(u * .pi) * (0.55 + 0.45 * abs(sin(u * 23))))
                }
                envelope = e * 0.9 + 0.012
            case .music:
                envelope = 0.45 + 0.25 * sin(t * 41) + 0.2 * abs(sin(t * 190)) + 0.1 * sin(t * 7)
            case .sample:
                envelope = 0   // the real file's peaks are loaded by the lab, not generated
            }
            // A peak is the loudest of many samples: mostly near the envelope, now and then a spike above it.
            let spike = random() > 0.9 ? 0.9 + random() * 0.7 : pow(random(), 1.6)
            result[i] = Float(min(max(envelope * spike, 0), 1))
        }
        cache[profile] = result
        return result
    }
}
