import SwiftUI

/// The Volume and Fade tools of a standalone audio clip in one popup (user 2026-10-17, after CapCut's Fade sheet): a NavigationStack with Reset and
/// Done, **sliders** on top and two round buttons under them - **Volume** and **Fade** - that switch the sliders in the same sheet. Volume: one slider
/// from 0 (silence) to 10 with the mark for 1 (the clip as recorded) in the middle of the track, where the thumb opens (`VolumeScale`), dragged both ways. Fade: **Fade in** and **Fade out**, each up to 10 s and never
/// longer than the clip (`AudioFadeLimit`). Live: the stage keeps playing while the sheet is open (background interaction on), so Play is heard as a
/// slider moves; the shell makes the whole session one undo step when the sheet closes.
struct VolumeSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case volume = "Volume", fade = "Fade"
        var id: String { rawValue }
        var symbol: String { self == .volume ? "speaker.wave.2" : "waveform.path" }
    }

    /// What opens the popup: the side to show first (a fresh request each time, so the sheet always starts on the side the tool asked for).
    struct Request: Identifiable {
        let id = UUID()
        let tab: Tab
    }

    let clipDurationMs: Double
    /// A video clip has Volume only (no Fade): under the slider two round icons that only show the state (sound on / muted) instead of the switch buttons.
    let showsFade: Bool
    let onGain: (Double) -> Void
    let onFade: (_ inMs: Double, _ outMs: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var position: Double
    @State private var fadeInSeconds: Double
    @State private var fadeOutSeconds: Double

    /// A video clip's sound: the Volume slider alone.
    init(gainDb: Double, onGain: @escaping (Double) -> Void) {
        self.init(gainDb: gainDb, fadeInMs: 0, fadeOutMs: 0, clipDurationMs: 0, tab: .volume, showsFade: false, onGain: onGain, onFade: { _, _ in })
    }

    init(gainDb: Double, fadeInMs: Double, fadeOutMs: Double, clipDurationMs: Double, tab: Tab, showsFade: Bool = true,
         onGain: @escaping (Double) -> Void, onFade: @escaping (_ inMs: Double, _ outMs: Double) -> Void) {
        let limit = AudioFadeLimit.maxMs(forClipDurationMs: clipDurationMs) / 1000
        _tab = State(initialValue: tab)
        _position = State(initialValue: VolumeScale.position(forMultiplier: VolumeScale.multiplier(forGainDb: gainDb)))
        _fadeInSeconds = State(initialValue: min((fadeInMs / 1000 * 10).rounded() / 10, limit))
        _fadeOutSeconds = State(initialValue: min((fadeOutMs / 1000 * 10).rounded() / 10, limit))
        self.clipDurationMs = clipDurationMs
        self.showsFade = showsFade
        self.onGain = onGain
        self.onFade = onFade
    }

    static let height = PresentationDetent.height(270)
    /// The sliders' area is as tall as the taller side (both are 86 pt of content), so the two buttons stay put when the tab changes; the buttons sit
    /// 14 pt under it (user 2026-10-17: the gap was about 47 pt on Volume and 55 on Fade).
    private static let contentHeight: CGFloat = 86
    private static let gap: CGFloat = 14

    private var multiplier: Double { VolumeScale.multiplier(forPosition: position) }
    private var fadeLimitSeconds: Double { AudioFadeLimit.maxMs(forClipDurationMs: clipDurationMs) / 1000 }

    var body: some View {
        NavigationStack {
            VStack(spacing: Self.gap) {
                Group {
                    switch tab {
                    case .volume: volume
                    case .fade: fade
                    }
                }
                .frame(height: Self.contentHeight, alignment: .top)
                if showsFade { buttons } else { soundState }
            }
            .padding(.top, 10)
            .navigationTitle(tab.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(tab == .volume ? multiplier == 1 : (fadeInSeconds == 0 && fadeOutSeconds == 0))
                        .accessibilityLabel("Reset")
                        .accessibilityIdentifier("volume-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("volumeDone")
                }
            }
        }
        .presentationDetents([Self.height])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: position) { _, _ in onGain(VolumeScale.gainDb(forMultiplier: multiplier)) }
        .onChange(of: fadeInSeconds) { _, _ in pushFade() }
        .onChange(of: fadeOutSeconds) { _, _ in pushFade() }
    }

    // MARK: Volume

    private var volume: some View {
        VStack(spacing: 8) {
            Text(VolumeScale.label(multiplier))
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .accessibilityIdentifier("volumeReadout")
            Slider(value: $position, in: 0...1)
                .background {
                    // The mark for 1x, in the middle of the track: the thumb covers it while the volume is unchanged.
                    Capsule().fill(Color.secondary).frame(width: 2, height: 18).accessibilityHidden(true)
                }
                .padding(.horizontal, 24)
                .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: multiplier == 1)   // a tick as the thumb reaches the mark
                .accessibilityIdentifier("volumeSlider")
            GeometryReader { proxy in
                let width = proxy.size.width - 48
                ZStack(alignment: .topLeading) {
                    Text("0").position(x: 24 + 4, y: 8)
                    Text("1").position(x: 24 + width * VolumeScale.unityPosition, y: 8)
                    Text("10").position(x: 24 + width - 8, y: 8)
                }
                .font(.caption2).foregroundColor(.secondary)
            }
            .frame(height: 16)
        }
    }

    // MARK: Fade

    private var fade: some View {
        VStack(spacing: 24) {
            fadeRow("Fade in", value: $fadeInSeconds, id: "fadeIn")
            fadeRow("Fade out", value: $fadeOutSeconds, id: "fadeOut")
        }
    }

    private func fadeRow(_ title: String, value: Binding<Double>, id: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline).foregroundColor(.secondary).frame(width: 68, alignment: .leading)
            Slider(value: value, in: 0...max(fadeLimitSeconds, 0.1), step: 0.1)
                .accessibilityIdentifier("\(id)Slider")
            Text(value.wrappedValue < 0.05 ? "Off" : String(format: "%.1f s", value.wrappedValue))
                .font(.subheadline.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
                .accessibilityIdentifier("\(id)Readout")
        }
        .padding(.horizontal, 24)
    }

    // MARK: Buttons, reset

    private var buttons: some View {
        HStack(spacing: 26) {
            ForEach(Tab.allCases) { item in
                let selected = tab == item
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(selected ? Color.accentColor : Color(.secondarySystemBackground))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                        Text(item.rawValue).font(.caption2).foregroundColor(selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("volumeMode-\(item.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A video's two round icons (user 2026-10-18): sound on and muted. Not buttons - they only show the state: the muted one lights up when the slider is at 0.
    private var soundState: some View {
        let muted = multiplier == 0
        return HStack(spacing: 26) {
            stateIcon("speaker.wave.2", title: "Sound", lit: !muted, id: "videoSoundOn")
            stateIcon("speaker.slash", title: "Muted", lit: muted, id: "videoSoundOff")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func stateIcon(_ symbol: String, title: String, lit: Bool, id: String) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(lit ? Color.accentColor : Color(.secondarySystemBackground))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundColor(lit ? .white : .primary))
            Text(title).font(.caption2).foregroundColor(lit ? .primary : .secondary)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    private func pushFade() { onFade(fadeInSeconds * 1000, fadeOutSeconds * 1000) }

    private func reset() {
        switch tab {
        case .volume: position = VolumeScale.unityPosition
        case .fade: fadeInSeconds = 0; fadeOutSeconds = 0
        }
    }
}
