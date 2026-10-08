import AVFoundation
import SwiftUI

/// Fires roughly at display refresh rate; while playing, `isPlaying`
/// advances `currentTimeMs` by the elapsed wall-clock delta between ticks.
/// Moved here 2026-10-08 from the old `ContentView` fixture picker when
/// that screen was deleted — this is the Editor's own real playback clock,
/// not demo-only code, so it stays even though the fixture UI around it
/// went away.
private let playbackTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

/// The real Editor screen's shell — nav bar (`Huỷ`/`Xuất`), then Stage /
/// Titlebar / Timeline. See `ui-design-note.md` (repo root) for the full
/// layout rationale and bug history.
struct EditorShellView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var project: V2Project
    @State private var currentTimeMs: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()
    /// Real decoded playback: while `isPlaying` and the playhead sits over a
    /// video layer, a real `AVPlayer` actually plays (`.play()`, not
    /// repeated seeks) and *drives* `currentTimeMs` from its own periodic
    /// time observer — the media clock is the master during playback, same
    /// as any player. The instant no video covers the current moment (a
    /// text-only stretch, or no video layer at all), playback falls back to
    /// the software `playbackTimer` clock. Paused/scrubbing never touches
    /// this player: the Stage reads cached decoded frames instead
    /// (`ScrubFrameView`/`ScrubFrameCache`), so during a scrub
    /// `currentTimeMs` is the only source of truth.
    @State private var playbackPlayer: AVPlayer?
    @State private var playbackAssetId: String?
    /// Source↔timeline mapping of the clip `playbackPlayer` was seeked for.
    @State private var playbackMapping: VideoTimeMapping?
    /// `false` from the moment a new playback session starts until its
    /// initial seek has actually completed. Until then the player isn't
    /// handed to the Stage (it would show its old frame or black) and its
    /// time observer is ignored (it can still report the *old* position,
    /// which used to yank `currentTimeMs` backward for a moment on Play).
    @State private var playbackSeekCompleted = false
    @State private var playbackTimeObserver: Any?
    /// One `AVPlayer` created up front per video asset (2026-10-08, at the
    /// user's own request — "nạp sẵn video vào RAM"), not lazily the first
    /// time `ensureRealPlayerPlaying` needs one. `AVPlayer(url:)`/
    /// `AVURLAsset` construction plus the asset's own `duration`/`tracks`
    /// metadata load takes real, measurable time on a cold start; doing
    /// that once for every asset as soon as the project opens means the
    /// very first Play press has nothing left to wait on — it reuses an
    /// already-warm player instead of constructing one from scratch.
    /// `ensureRealPlayerPlaying` reads from this dictionary instead of
    /// calling `AVPlayer(url:)` itself now.
    @State private var preloadedPlayers: [String: AVPlayer] = [:]
    /// Measured via `TitlebarHeightKey`; this is just the pre-first-layout guess.
    @State private var titlebarHeight: CGFloat = 60
    /// Toggled by the titlebar's "Enter Full Screen" button — swaps the
    /// whole Stage/Titlebar/Timeline shell for `fullscreenStage` below.
    @State private var isFullscreen = false
    /// Lifted out of `FullscreenScrubber` so `fullscreenControlBarContent`
    /// can react to it too (hide play/exit, show the time readout) — see
    /// ui-design-note.md.
    @State private var isScrubbing = false
    /// Bottom tool row's own highlighted tool — no per-tool screen exists
    /// yet (see `EditorTool.swift`), so this only drives which icon is
    /// highlighted, nothing else.
    @State private var selectedTool: EditorTool?
    /// Phase 1 of the "Bottom nav tools" roadmap — see
    /// `EditorCommand.swift`/`EditorHistory.swift`. Every edit goes through
    /// `apply(_:)` below so it's recorded for undo/redo, never a direct
    /// `project = ...` assignment elsewhere.
    @State private var history = EditorHistory()
    /// Phase 2 (Chỉnh sửa) — which clip is selected in the Timeline, if
    /// any. Only visual layers are selectable this pass (see
    /// `TimelineView`'s own doc comment on this).
    @State private var selectedLayerId: String?
    /// Drag-to-trim's own undo snapshot — captured once when a trim drag
    /// *begins* (not per `history.record(_:)` call on every pixel moved),
    /// so an entire drag gesture collapses into a single undo step. `nil`
    /// whenever no trim drag is in progress.
    @State private var trimDragOriginal: V2Project?
    private let toolbarHeight: CGFloat = 58
    private let toolPanelHeight: CGFloat = 64

    private var showsToolPanel: Bool {
        selectedTool?.hasOptionsPanel ?? false
    }

    init(project: V2Project) {
        _project = State(initialValue: project)
    }

    /// The one path every edit must go through — see `EditorHistory`'s own
    /// doc comment on why this snapshots the whole document rather than
    /// asking each `EditorCommand` to carry its own inverse.
    private func apply(_ command: EditorCommand) {
        history.record(current: project)
        project = command.apply(to: project)
    }

    private func undo() {
        guard let previous = history.undo(current: project) else { return }
        project = previous
    }

    private func redo() {
        guard let next = history.redo(current: project) else { return }
        project = next
    }

    /// Called once when a trim-handle drag starts — snapshots the
    /// pre-drag project so `endTrim()` can record *that* into history,
    /// not whatever the live-updated project happens to be by then.
    private func beginTrim() {
        guard trimDragOriginal == nil else { return }
        trimDragOriginal = project
    }

    /// Called on every `DragGesture.onChanged` tick while trimming —
    /// applies the live preview directly, deliberately bypassing
    /// `apply(_:)`/`history.record(_:)` so dragging doesn't spam the undo
    /// stack with one entry per pixel moved.
    private func updateTrim(_ command: EditorCommand) {
        project = command.apply(to: project)
    }

    /// Called once when the drag ends — records the single pre-drag
    /// snapshot `beginTrim()` captured, collapsing the whole gesture into
    /// one undo step.
    private func endTrim() {
        guard let original = trimDragOriginal else { return }
        history.record(current: original)
        trimDragOriginal = nil
    }

    private var maxDurationMs: Double {
        let layerEnds = project.layers.map { $0.timing.start + $0.timing.duration }
        let audioEnds = project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }
        return max((layerEnds + audioEnds).max() ?? 1, 1)
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
        .task { preloadVideoPlayers() }
        .onReceive(playbackTimer) { now in
            guard isPlaying else { return }
            defer { lastTick = now }
            if let active = activeVideoLayer(atMs: currentTimeMs) {
                // A real video covers this instant — let its own AVPlayer
                // actually play and drive the clock; the software tick
                // below is deliberately skipped for as long as this stays
                // true (see `playbackPlayer`'s own doc comment).
                ensureRealPlayerPlaying(for: active)
                return
            }
            releaseRealPlayer()
            let deltaMs = now.timeIntervalSince(lastTick) * 1000
            let next = currentTimeMs + deltaMs
            if next >= maxDurationMs {
                currentTimeMs = 0
                isPlaying = false
            } else {
                currentTimeMs = next
            }
        }
        .onChange(of: isPlaying) { _, playing in
            guard !playing else { return }
            releaseRealPlayer()
        }
    }

    /// Creates (and starts warming up) one `AVPlayer` per distinct video
    /// asset in the project, up front — called once from `.task` when the
    /// Editor first appears. Guarded by `preloadedPlayers[id] == nil` so
    /// calling this more than once (harmless) never recreates an already-
    /// warm player. `loadValuesAsynchronously` kicks off `AVURLAsset`'s own
    /// metadata load (duration/tracks/playable) in the background rather
    /// than leaving it to happen lazily on first seek/play.
    private func preloadVideoPlayers() {
        for layer in project.layers where layer.type == "video" {
            guard case .video(let payload) = layer.payload,
                  preloadedPlayers[payload.assetId] == nil,
                  let asset = project.assets.first(where: { $0.id == payload.assetId }),
                  case .video(let videoAsset) = asset,
                  let url = bundledURL(filename: videoAsset.uri)
            else { continue }
            let avAsset = AVURLAsset(url: url)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
            player.automaticallyWaitsToMinimizeStalling = false
            preloadedPlayers[payload.assetId] = player
            Task {
                _ = try? await avAsset.load(.duration, .tracks, .isPlayable)
            }
        }
    }

    /// The video layer (if any) whose own time range covers `ms` — at most
    /// one can be active at once, matching `PreviewCanvas.activePlayer`'s
    /// own single-asset shape (see its doc comment).
    private func activeVideoLayer(atMs ms: Double) -> (layer: V2Layer, assetId: String, url: URL)? {
        guard let layer = project.layers.first(where: { layer in
            layer.type == "video" && ms >= layer.timing.start && ms < layer.timing.start + layer.timing.duration
        }), case .video(let payload) = layer.payload,
              let asset = project.assets.first(where: { $0.id == payload.assetId }),
              case .video(let videoAsset) = asset,
              let url = bundledURL(filename: videoAsset.uri)
        else { return nil }
        return (layer, payload.assetId, url)
    }

    /// Creates (or reuses) the `AVPlayer` for whichever video layer is
    /// currently active and makes sure it's actually playing — seeking it
    /// only when entering a clip whose source mapping differs from the one
    /// already playing (`VideoTimeMapping.isContinuous`), so e.g. the two
    /// halves of a split play straight through without a re-seek, and the
    /// player's own clock is what advances `currentTimeMs` moment to moment.
    private func ensureRealPlayerPlaying(for active: (layer: V2Layer, assetId: String, url: URL)) {
        guard let mapping = VideoTimeMapping(layer: active.layer) else { return }
        if playbackAssetId == active.assetId, let player = playbackPlayer,
           let current = playbackMapping, current.isContinuous(with: mapping) {
            if player.rate == 0 { player.rate = Float(mapping.rate) }
            return
        }
        releaseRealPlayer()
        let player = preloadedPlayers[active.assetId] ?? AVPlayer(url: active.url)
        player.automaticallyWaitsToMinimizeStalling = false
        playbackPlayer = player
        playbackAssetId = active.assetId
        playbackMapping = mapping
        let sourceSeconds = mapping.sourceMs(atTimelineMs: currentTimeMs) / 1000
        playbackSeekCompleted = false
        player.seek(to: CMTime(seconds: sourceSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [self] finished in
            DispatchQueue.main.async {
                if finished, playbackPlayer === player { playbackSeekCompleted = true }
            }
        }
        let interval = CMTime(seconds: 1.0 / 60, preferredTimescale: 600)
        playbackTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            guard playbackSeekCompleted else { return }
            let timelineMs = mapping.timelineMs(atSourceMs: time.seconds * 1000)
            if timelineMs >= maxDurationMs {
                currentTimeMs = 0
                isPlaying = false
            } else {
                currentTimeMs = timelineMs
            }
        }
        player.rate = Float(mapping.rate)
    }

    /// Pauses and tears down the real playback player — called whenever
    /// playback stops entirely (pause, scrub, reaching the end) or when
    /// the playhead moves into a different clip/asset than the one
    /// currently playing.
    private func releaseRealPlayer() {
        guard let player = playbackPlayer else { return }
        player.pause()
        if let observer = playbackTimeObserver {
            player.removeTimeObserver(observer)
            playbackTimeObserver = nil
        }
        playbackPlayer = nil
        playbackAssetId = nil
        playbackMapping = nil
        playbackSeekCompleted = false
    }

    /// Handed to `PreviewCanvas` so its matching video layer shows the real
    /// player's live output on top of the cached still — `nil` whenever
    /// nothing is playing, and also until the session's initial seek has
    /// completed (see `playbackSeekCompleted`).
    private var activePlayerInfo: (assetId: String, player: AVPlayer)? {
        guard let playbackPlayer, let playbackAssetId, playbackSeekCompleted else { return nil }
        return (playbackAssetId, playbackPlayer)
    }

    private var windowedShell: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                // Stage: a square sized from width alone (see ui-design-note.md).
                let squareSide = geo.size.width
                let videoBoxSide = squareSide * 0.96
                let stageHeight = squareSide
                // Timeline: whatever's left after Stage/Titlebar/toolbar(/tool panel), no floor (see ui-design-note.md).
                let reservedHeight = titlebarHeight + stageHeight + toolbarHeight + (showsToolPanel ? toolPanelHeight : 0)
                let timelineHeight = max(geo.size.height - reservedHeight - (showsToolPanel ? 3 : 2), 0)

                VStack(spacing: 0) {
                    // `.allowsHitTesting(false)` is load-bearing — see ui-design-note.md.
                    PreviewCanvas(
                        composition: project.composition,
                        assets: project.assets,
                        layers: project.layers,
                        atMs: currentTimeMs,
                        activePlayer: activePlayerInfo
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
                        assets: project.assets,
                        audio: project.audio,
                        currentTimeMs: $currentTimeMs,
                        maxDurationMs: maxDurationMs,
                        onScrub: { isPlaying = false },
                        selectedLayerId: $selectedLayerId,
                        onTrimBegin: beginTrim,
                        onTrimUpdate: updateTrim,
                        onTrimEnd: endTrim
                    )
                    .frame(height: timelineHeight)
                    .clipped()
                    Divider()
                    if let selectedTool, showsToolPanel {
                        ToolOptionsPanel(
                            tool: selectedTool,
                            composition: project.composition,
                            selectedLayer: project.layers.first { $0.id == selectedLayerId },
                            currentTimeMs: currentTimeMs,
                            onSetAspectRatio: { width, height in apply(SetAspectRatioCommand(width: width, height: height)) },
                            onSetBackgroundColor: { hex in apply(SetBackgroundColorCommand(hex: hex)) },
                            onSplit: { layerId, atMs in
                                apply(SplitClipCommand(layerId: layerId, atMs: atMs))
                                selectedLayerId = nil
                            },
                            onDelete: { layerId in
                                apply(DeleteClipCommand(layerId: layerId))
                                selectedLayerId = nil
                            }
                        )
                        .frame(height: toolPanelHeight)
                        Divider()
                    }
                    EditorToolbarView(selectedTool: $selectedTool)
                        .frame(height: toolbarHeight)
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
                    atMs: currentTimeMs,
                    activePlayer: activePlayerInfo
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
                    Button(action: undo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.headline)
                            .fontWeight(.regular)
                    }
                    .disabled(!history.canUndo)
                    Button(action: redo) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.headline)
                            .fontWeight(.regular)
                    }
                    .disabled(!history.canRedo)
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
    EditorShellView(project: compile(SampleProjectBuilder.makeDocument(
        media: .videoPortrait, inOption: .none, outOption: .none,
        effectOption: .none, easingOption: .linear,
        composition: V2Composition(width: 360, height: 640, fps: 30, background: "#101820"),
        frame: V2Frame(width: 360, height: 640)
    )))
}
