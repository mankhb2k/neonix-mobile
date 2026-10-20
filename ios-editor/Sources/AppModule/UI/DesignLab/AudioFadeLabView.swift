import SwiftUI

/// Design lab for how a standalone audio clip shows its **fade in / fade out** (user 2026-10-17). No outline: the fade shows in the clip's own shapes.
/// **A** the waveform as it is (the fade then shows only in the body, with the two-tone body), **B** the waveform scaled down along the fade (what you
/// see is what you hear), **C** the scaled waveform and, on a dark or light body, the part above the curve darkened. The curve is the engine's own
/// equal-power shape (`sin` of a quarter turn), so the picture is the real fade. Also tried here: a darker clip body (the reference's) against the light one, and a
/// small badge for the clip's volume like CapCut's "1.1x" on video (shown only when it is not 1x, "Mute" when silent). Fake audio; sliders set both fades
/// (0...10 s, never longer than the clip - `AudioFadeLimit`), the clip's length and the zoom.
struct AudioFadeLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Style: String, CaseIterable, Identifiable {
        case plain = "A Wave as is", scaled = "B Scaled wave", both = "C Scaled + shade"
        var id: String { rawValue }
        var summary: String {
            switch self {
            case .plain: return "The waveform stays as it is; the fade shows only in the clip body (two-tone: its 45 % area curves down at the ends)"
            case .scaled: return "The waveform itself shrinks along the fade, so the picture is the loudness you hear"
            case .both: return "The shrinking waveform and, on a dark or light body, the part above the curve darkened (two-tone body already shows it)"
            }
        }
    }

    /// `twoTone` (user 2026-10-17): the whole clip is a 10 % cyan wash and a 45 % cyan area marks what is still audible - full height over the
    /// middle, curving down at the ends along the fade in / out, so the fade shows as the shape of the body itself.
    enum ClipBody: String, CaseIterable, Identifiable {
        case dark = "Dark body", light = "Light body", twoTone = "Two-tone 10/45"
        var id: String { rawValue }
    }

    enum Badge: String, CaseIterable, Identifiable {
        case none = "No badge", half = "0.5×", triple = "3×", mute = "Mute"
        var id: String { rawValue }
        var text: String? { self == .none ? nil : rawValue }
    }

    @State private var style: Style = .both
    @State private var clipBody: ClipBody = .twoTone
    @State private var badge: Badge = .triple
    @State private var profile: AudioWaveLabView.Profile = .music
    @State private var fadeIn = 3.0
    @State private var fadeOut = 2.0
    @State private var seconds = 20.0
    @State private var pointsPerSecond = 40.0

    private var fadeLimit: Double { AudioFadeLimit.maxMs(forClipDurationMs: seconds * 1000) / 1000 }
    private var samples: [Float] { LabWaveData.samples(profile == .sample ? .voice : profile) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Fade drawing", selection: $style) {
                ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            .accessibilityIdentifier("audioFadeStylePicker")
            Text(style.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    clipRow(title: "Lane clip, 30 pt row (text / audio rows)", height: 30)
                    clipRow(title: "Lane clip, 48 pt row (the main lane's height)", height: 48)
                    controls
                }
                .padding()
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onChange(of: seconds) { _, _ in
            fadeIn = min(fadeIn, fadeLimit)
            fadeOut = min(fadeOut, fadeLimit)
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("audioFadeClose")
            Spacer()
            Text("Audio fade lab").font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
    }

    private func clipRow(title: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(.secondarySystemBackground))
                        .frame(width: max(seconds * pointsPerSecond + 24, 340), height: height)
                    LabFadeClip(
                        samples: samples, width: seconds * pointsPerSecond, height: height, style: style, bodyStyle: clipBody,
                        fadeIn: fadeIn, fadeOut: fadeOut, seconds: seconds, badge: badge.text
                    )
                    .padding(.leading, 8)
                    .accessibilityIdentifier("audioFadeClip\(Int(height))")
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            segmented("Audio", $profile, cases: [.voice, .music])
            segmented("Clip body", $clipBody, cases: ClipBody.allCases)
            segmented("Volume badge", $badge, cases: Badge.allCases)
            slider("Fade in", value: $fadeIn, range: 0...max(fadeLimit, 0.1), step: 0.1, format: "%.1f s")
            slider("Fade out", value: $fadeOut, range: 0...max(fadeLimit, 0.1), step: 0.1, format: "%.1f s")
            slider("Clip length", value: $seconds, range: 4...60, step: 1, format: "%.0f s")
            slider("Zoom", value: $pointsPerSecond, range: 10...120, step: 1, format: "%.0f pt/s")
        }
    }

    private func segmented<T: Hashable & Identifiable & RawRepresentable>(_ title: String, _ selection: Binding<T>, cases: [T]) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Picker(title, selection: selection) {
                ForEach(cases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

/// One mock audio clip with its fades. The curve is the engine's equal-power fade (`AudioMixEngine.fadeCurveValue`).
struct LabFadeClip: View {
    let samples: [Float]
    let width: Double
    let height: Double
    let style: AudioFadeLabView.Style
    let bodyStyle: AudioFadeLabView.ClipBody
    let fadeIn: Double
    let fadeOut: Double
    let seconds: Double
    let badge: String?

    /// The fade's gain 0...1 at a fraction (0...1) of the clip.
    private func gain(at fraction: Double) -> Double {
        let t = fraction * seconds
        var g = 1.0
        if fadeIn > 0, t < fadeIn { g *= sin(min(max(t / fadeIn, 0), 1) * .pi / 2) }
        let remaining = seconds - t
        if fadeOut > 0, remaining < fadeOut { g *= sin(min(max(remaining / fadeOut, 0), 1) * .pi / 2) }
        return g
    }

    private var dark: Bool { bodyStyle == .dark }
    private var scalesWave: Bool { style == .scaled || style == .both }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch bodyStyle {
            case .dark: Rectangle().fill(Color(red: 0.10, green: 0.26, blue: 0.30))
            case .light: Rectangle().fill(Color.cyan.opacity(0.45))
            case .twoTone:
                ZStack {
                    Rectangle().fill(Color.cyan.opacity(0.10))
                    // The 45 % area: under the fade's envelope, so it curves down at the ends that fade.
                    Canvas { context, size in
                        let columns = max(Int(size.width / 2), 2)
                        var area = Path()
                        area.move(to: CGPoint(x: 0, y: size.height))
                        for i in 0...columns {
                            let fraction = Double(i) / Double(columns)
                            area.addLine(to: CGPoint(x: size.width * fraction, y: size.height * (1 - gain(at: fraction))))
                        }
                        area.addLine(to: CGPoint(x: size.width, y: size.height))
                        area.closeSubpath()
                        context.fill(area, with: .color(Color.cyan.opacity(0.45)))
                    }
                }
            }
            LabWaveform(
                samples: samples, variant: .mirrored, lineWidth: 1, gap: 0, gain: 0.9, curve: 0.6,
                color: dark ? Color(red: 0.36, green: 0.86, blue: 0.95) : .cyan,
                envelope: scalesWave ? { gain(at: Double($0)) } : nil
            )
            .frame(height: height - 4)
            .padding(.vertical, 2)
            Canvas { context, size in
                for isIn in [true, false] {
                    let seconds = isIn ? fadeIn : fadeOut
                    let fadeWidth = size.width * seconds / self.seconds
                    guard seconds > 0, fadeWidth >= 6 else { continue }   // too short to draw on screen
                    var curve = Path()
                    let steps = max(Int(fadeWidth / 2), 8)
                    for i in 0...steps {
                        let u = Double(i) / Double(steps)
                        let x = isIn ? fadeWidth * u : size.width - fadeWidth * u
                        let y = size.height * (1 - sin(u * .pi / 2))
                        i == 0 ? curve.move(to: CGPoint(x: x, y: y)) : curve.addLine(to: CGPoint(x: x, y: y))
                    }
                    if style == .both, bodyStyle != .twoTone {   // two-tone already shades it: the 10 % wash above the curve
                        // The part above the curve, darkened: what the fade takes away.
                        var shade = curve
                        shade.addLine(to: CGPoint(x: isIn ? 0 : size.width, y: 0))
                        shade.addLine(to: CGPoint(x: isIn ? fadeWidth : size.width - fadeWidth, y: 0))
                        shade.closeSubpath()
                        context.fill(shade, with: .color(.black.opacity(0.3)))
                    }
                }
            }
            .allowsHitTesting(false)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(3)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
