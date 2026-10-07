import SwiftUI

/// The real Editor screen's shell — nav bar (`Huỷ`/`Xuất`), then Stage /
/// Titlebar / Timeline. See `ui-design-note.md` (repo root) for the full
/// layout rationale and bug history.
struct EditorShellView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var project: V2Project
    @State private var currentTimeMs: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()
    /// Measured via `TitlebarHeightKey`; this is just the pre-first-layout guess.
    @State private var titlebarHeight: CGFloat = 60
    /// Toggled by the titlebar's "Enter Full Screen" button — swaps the
    /// whole Stage/Titlebar/Timeline shell for `fullscreenStage` below.
    @State private var isFullscreen = false
    /// Lifted out of `FullscreenScrubber` so `fullscreenControlBarContent`
    /// can react to it too (hide play/exit, show the time readout) — see
    /// ui-design-note.md.
    @State private var isScrubbing = false

    init(project: V2Project) {
        _project = State(initialValue: project)
    }

    private var maxDurationMs: Double {
        max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 1, 1)
    }

    var body: some View {
        Group {
            if isFullscreen {
                fullscreenStage
            } else {
                windowedShell
            }
        }
        // Ignore `0` — a transient artifact during the cover's presentation
        // animation, not a real measurement (see ui-design-note.md).
        .onPreferenceChange(TitlebarHeightKey.self) { newValue in
            guard newValue > 0 else { return }
            titlebarHeight = newValue
        }
        .onReceive(playbackTimer) { now in
            guard isPlaying else { return }
            let deltaMs = now.timeIntervalSince(lastTick) * 1000
            lastTick = now
            let next = currentTimeMs + deltaMs
            if next >= maxDurationMs {
                currentTimeMs = 0
                isPlaying = false
            } else {
                currentTimeMs = next
            }
        }
    }

    private var windowedShell: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                // Stage: a square sized from width alone (see ui-design-note.md).
                let squareSide = geo.size.width
                let videoBoxSide = squareSide * 0.96
                let stageHeight = squareSide
                // Timeline: whatever's left, no floor (see ui-design-note.md).
                let timelineHeight = max(geo.size.height - titlebarHeight - stageHeight - 1, 0)

                VStack(spacing: 0) {
                    // `.allowsHitTesting(false)` is load-bearing — see ui-design-note.md.
                    PreviewCanvas(
                        composition: project.composition,
                        assets: project.assets,
                        layers: project.layers,
                        atMs: currentTimeMs
                    )
                    .allowsHitTesting(false)
                    .frame(width: videoBoxSide, height: videoBoxSide)
                    .frame(width: squareSide, height: squareSide)
                    .background(Color(.systemBackground))

                    controlsRow
                        .background(GeometryReader { titlebarGeo in
                            Color.clear.preference(key: TitlebarHeightKey.self, value: titlebarGeo.size.height)
                        })
                    Divider()
                    TimelineView(
                        layers: project.layers,
                        currentTimeMs: $currentTimeMs,
                        maxDurationMs: maxDurationMs,
                        onScrub: { isPlaying = false }
                    )
                    .frame(height: timelineHeight)
                    .clipped()
                }
            }
        }
        .background(Color(.systemBackground))
    }

    /// Full-screen takeover triggered by the titlebar's "Enter Full Screen"
    /// button — video fills the entire screen (black letterbox, matching
    /// every standard video player's fullscreen convention, distinct from
    /// Stage's own light background), Huỷ/Xuất/Titlebar/Timeline are all
    /// hidden. `fullscreenControlBar` (bottom) is the only way back.
    /// Playback state (`currentTimeMs`/`isPlaying`) is shared with the
    /// windowed shell, so entering/exiting never interrupts it.
    private var fullscreenStage: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                PreviewCanvas(
                    composition: project.composition,
                    assets: project.assets,
                    layers: project.layers,
                    atMs: currentTimeMs
                )
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                fullscreenControlBar(screenWidth: geo.size.width)
                    .padding(.bottom, 60)
            }
        }
    }

    /// Photos-style player bar: play/pause, a scrubber, exit — one pill, not
    /// 3 separate bubbles (see `ui-design-note.md`). `GlassEffectContainer`
    /// wrapping a single `.glassEffect` is Apple's own recommended pattern
    /// even for one glass shape (correct sampling/merging), not just for
    /// multiple morphing shapes.
    ///
    /// Width stays fixed across both states — only the *content*'s height
    /// changes when scrubbing starts/ends (see
    /// `fullscreenControlBarContent`'s doc comment and `ui-design-note.md`).
    /// The shape itself (`barShape`) is now the same
    /// `RoundedRectangle` in both states, not a `Capsule` ↔
    /// `RoundedRectangle` swap — matching the real Photos app's own bar,
    /// which doesn't visibly change roundness when scrubbing starts either.
    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    @ViewBuilder
    private func fullscreenControlBar(screenWidth: CGFloat) -> some View {
        let barWidth = screenWidth - 40

        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    fullscreenControlBarContent
                        .glassEffect(.regular.interactive(), in: barShape)
                }
            } else {
                fullscreenControlBarContent
                    .background(.ultraThinMaterial, in: barShape)
            }
        }
        .frame(width: barWidth)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isScrubbing)
    }

    /// While scrubbing, play/exit are removed from the layout (not just
    /// faded) — matching the real Photos app, where the track visibly
    /// reclaims their space and grows to fill it, rather than leaving it
    /// reserved. `fraction`-based fill (see `FullscreenScrubber`) already
    /// recomputes against whatever width `GeometryReader` reports each
    /// render, so the filled portion always represents the correct % of
    /// `currentTimeMs`/`maxDurationMs` regardless of the track's current
    /// width — the pixel position is allowed to shift between states (it
    /// represents a %, not a frozen coordinate); only the underlying time
    /// value must stay unaffected by the resize, which it already is.
    /// `.transition(.move(edge: .top).combined(with: .opacity).animation(.easeOut(duration: 0.18)))`
    /// on each button gives the "slides up while fading away" exit (and the
    /// mirrored "drops down while fading in" entrance) — move and opacity
    /// run *together*, same curve, same duration, not one finishing before
    /// the other. The `.animation(_:)` wrapping the whole combined
    /// transition (not just one half of it) is what keeps both in sync
    /// while still making the *entire* exit quicker than the ambient
    /// `.spring(response: 0.25, ...)` driving the rest of the bar — short
    /// enough that both motion and fade are fully done before the icon
    /// would reach the bar's own clipped edge near the time-label row,
    /// instead of still being visible (and then abruptly clipped, not
    /// faded) right as it gets there.
    private var fullscreenControlBarContent: some View {
        VStack(spacing: 6) {
            if isScrubbing {
                HStack {
                    Text(formattedTime(currentTimeMs, includeFraction: true))
                    Spacer()
                    Text(formattedTime(maxDurationMs, includeFraction: false))
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                if !isScrubbing {
                    Button {
                        isPlaying.toggle()
                        lastTick = .init()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity).animation(.easeOut(duration: 0.18)))
                }

                FullscreenScrubber(
                    currentTimeMs: $currentTimeMs,
                    maxDurationMs: maxDurationMs,
                    isDragging: $isScrubbing,
                    onScrubStart: { isPlaying = false }
                )

                if !isScrubbing {
                    Button {
                        isFullscreen = false
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity).animation(.easeOut(duration: 0.18)))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func formattedTime(_ ms: Double, includeFraction: Bool) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        guard includeFraction else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
        let hundredths = Int((totalSeconds - totalSeconds.rounded(.down)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    /// `Huỷ`/`Xuất` — native Photos editor style; see ui-design-note.md.
    private var topBar: some View {
        HStack {
            cancelButton
            Spacer()
            exportButton
        }
        .padding()
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var cancelButton: some View {
        if #available(iOS 26.0, *) {
            Button("Huỷ") { dismiss() }
                .buttonStyle(.glass)
        } else {
            Button("Huỷ") { dismiss() }
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if #available(iOS 26.0, *) {
            Button("Xuất") { dismiss() }
                .buttonStyle(.glassProminent)
        } else {
            Button("Xuất") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Play/pause is centered via its own overlaid `HStack`, not shared
    /// `Spacer()`s with the side buttons — see ui-design-note.md.
    private var controlsRow: some View {
        ZStack {
            HStack {
                Spacer()
                Button {
                    isPlaying.toggle()
                    lastTick = .init()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .fontWeight(.regular)
                }
                Spacer()
            }

            HStack {
                Button {
                    isFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .fontWeight(.regular)
                }

                Spacer()

                HStack(spacing: 22) {
                    Button {} label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.headline)
                            .fontWeight(.regular)
                    }
                    .disabled(true)
                    Button {} label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.headline)
                            .fontWeight(.regular)
                    }
                    .disabled(true)
                }
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

/// The fullscreen player bar's progress track — grows taller while the
/// thumb is actively dragged, matching Photos' own scrubber feel, then
/// springs back on release. `isDragging` is a binding (not local `@State`)
/// so `fullscreenControlBarContent` can react to it too (hide play/exit,
/// show the time readout).
///
/// Entering scrub mode requires a genuine **hold**, not just touching the
/// track — `LongPressGesture(minimumDuration:).sequenced(before:
/// DragGesture(minimumDistance: 0))`, not a plain `DragGesture`. A bare
/// `DragGesture(minimumDistance: 0)` starts scrubbing on the very first
/// touch-down, which is too eager (an incidental tap/brush would yank
/// playback position); requiring a short hold first matches how the real
/// Photos app behaves and avoids that.
private struct FullscreenScrubber: View {
    @Binding var currentTimeMs: Double
    let maxDurationMs: Double
    @Binding var isDragging: Bool
    let onScrubStart: () -> Void

    private var fraction: Double {
        guard maxDurationMs > 0 else { return 0 }
        return min(max(currentTimeMs / maxDurationMs, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(Color.white)
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: isDragging ? 18 : 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.2)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .first(true), .second(true, nil):
                            beginScrubbingIfNeeded()
                        case .second(true, let drag?):
                            beginScrubbingIfNeeded()
                            seek(to: drag.location.x, trackWidth: geo.size.width)
                        default:
                            break
                        }
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 24)
    }

    private func beginScrubbingIfNeeded() {
        guard !isDragging else { return }
        isDragging = true
        onScrubStart()
    }

    private func seek(to x: CGFloat, trackWidth: CGFloat) {
        let fraction = min(max(x / trackWidth, 0), 1)
        currentTimeMs = fraction * maxDurationMs
    }
}

private struct TitlebarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// 9:16 (360x640), matching `ProjectsView`'s "Trip to Paris" sample.
#Preview {
    EditorShellView(project: compile(EditorDemoView.makeDocument(
        media: .videoPortrait, inOption: .none, outOption: .none,
        effectOption: .none, easingOption: .linear,
        composition: V2Composition(width: 360, height: 640, fps: 30, background: "#101820"),
        frame: V2Frame(width: 360, height: 640)
    )))
}
