import SwiftUI

/// The real Editor screen's shell — nav bar (`Huỷ`/`Xuất`), then Stage /
/// Titlebar / Timeline. See `ui-design-note.md` (repo root) for the full
/// layout rationale and bug history.
struct EditorShellView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var project: V2Project
    /// Owns the playhead clock, Play/Pause, scrubbing + momentum
    /// (`Playback/EditorPlaybackEngine.swift`). This view only sends it
    /// commands and reads from it — it never writes the time.
    @State private var engine: EditorPlaybackEngine
    private var currentTimeMs: Double { engine.currentTimeMs }
    private var isPlaying: Bool { engine.isPlaying }
    private var maxDurationMs: Double { engine.maxDurationMs }
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
    /// Âm thanh — which standalone audio clip is selected, if any (see
    /// `TimelineView`'s own doc comment on why this is separate from
    /// `selectedLayerId`).
    @State private var selectedAudioClipId: String?
    /// Drag-to-trim's own undo snapshot — captured once when a trim drag
    /// *begins* (not per `history.record(_:)` call on every pixel moved),
    /// so an entire drag gesture collapses into a single undo step. `nil`
    /// whenever no trim drag is in progress.
    @State private var trimDragOriginal: V2Project?
    /// Tuỳ chỉnh — the last slider values set per layer this *session*
    /// (never persisted to `project`/exported). Needed because a compiled
    /// `V2Filter` has no cheap way to read brightness/contrast/saturation/
    /// exposure back out of it — see CLAUDE.md's "Tuỳ chỉnh" note on why
    /// this is a stated, deliberate limitation rather than a bug: the
    /// Stage/export always reflect the real persisted filter; only the
    /// slider *positions* reset to neutral after reopening the editor.
    @State private var adjustIntents: [String: AdjustValues] = [:]
    /// Same "one undo step per drag gesture" shape as `trimDragOriginal`.
    @State private var adjustDragOriginal: V2Project?
    private let toolbarHeight: CGFloat = 58
    private let toolPanelHeight: CGFloat = 64

    private var showsToolPanel: Bool {
        selectedTool?.hasOptionsPanel ?? false
    }

    init(project: V2Project) {
        _project = State(initialValue: project)
        _engine = State(initialValue: EditorPlaybackEngine(project: project))
    }

    /// Every write to `project` goes through here so the engine always sees
    /// the same layers the Stage and Timeline render.
    private func setProject(_ newProject: V2Project) {
        project = newProject
        engine.update(project: newProject)
    }

    /// The one path every edit must go through — see `EditorHistory`'s own
    /// doc comment on why this snapshots the whole document rather than
    /// asking each `EditorCommand` to carry its own inverse.
    private func apply(_ command: EditorCommand) {
        history.record(current: project)
        setProject(command.apply(to: project))
    }

    private func undo() {
        guard let previous = history.undo(current: project) else { return }
        setProject(previous)
    }

    private func redo() {
        guard let next = history.redo(current: project) else { return }
        setProject(next)
    }

    /// Âm thanh — "Thêm nhạc": the file picker hands back a raw URL
    /// (already a temp copy, see `AudioFilePicker`'s own doc comment);
    /// this runs the real import (copy into the sandbox + read duration)
    /// off the main actor's own async context, then applies the result as
    /// one ordinary undoable command, same as every other edit.
    private func addAudio(from url: URL) {
        Task {
            guard let asset = try? await MediaImportService.importAudio(from: url) else { return }
            apply(AddAudioClipCommand(asset: asset, durationMs: asset.duration, atMs: currentTimeMs))
        }
    }

    /// Văn bản — "Thêm chữ": generates the new layer's id here (not inside
    /// the command) so it can be selected immediately after — typing again
    /// right away edits the clip just added instead of creating a second
    /// one.
    private func addText(_ text: String) {
        let layerId = "text-\(UUID().uuidString.prefix(8))"
        apply(AddTextLayerCommand(layerId: layerId, text: text, atMs: currentTimeMs))
        selectedLayerId = layerId
        selectedAudioClipId = nil
    }

    /// Trích xuất — pulls the selected video layer's own audio out onto the
    /// audio lane, positioned to exactly line up with that clip (same
    /// `timing.start`/duration, `trim` matching the video's own `trimStart`)
    /// since `MediaImportService.extractAudio` always exports the *whole*
    /// source asset's audio, cached, not just the trimmed slice this one
    /// clip currently shows.
    private func extractAudio(fromLayerId layerId: String) {
        guard let layer = project.layers.first(where: { $0.id == layerId }),
              case .video(let payload) = layer.payload,
              let videoAsset = project.assets.first(where: { $0.id == payload.assetId }),
              case .video(let v) = videoAsset,
              let url = bundledURL(filename: v.uri)
        else { return }

        let trimStart = payload.trimStart ?? 0
        Task {
            guard let asset = try? await MediaImportService.extractAudio(from: url) else { return }
            apply(AddAudioClipCommand(
                asset: asset, durationMs: layer.timing.duration, atMs: layer.timing.start,
                trimStartMs: trimStart, trimEndMs: trimStart + layer.timing.duration
            ))
        }
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
        setProject(command.apply(to: project))
    }

    /// Called once when the drag ends — records the single pre-drag
    /// snapshot `beginTrim()` captured, collapsing the whole gesture into
    /// one undo step.
    private func endTrim() {
        guard let original = trimDragOriginal else { return }
        history.record(current: original)
        trimDragOriginal = nil
    }

    /// Tuỳ chỉnh — same "one undo step per gesture" shape as `beginTrim`,
    /// just triggered by `Slider`'s own `onEditingChanged(true)` instead of
    /// a custom `DragGesture.onChanged`'s first tick.
    private func beginAdjust() {
        guard adjustDragOriginal == nil else { return }
        adjustDragOriginal = project
    }

    /// Called on every slider tick — live preview, bypassing `apply(_:)`
    /// same as `updateTrim`, plus remembers the full 4-value tuple so a
    /// later edit to a *different* slider doesn't silently drop this one.
    private func updateAdjust(layerId: String, values: AdjustValues) {
        adjustIntents[layerId] = values
        setProject(SetAdjustCommand(layerId: layerId, values: values).apply(to: project))
    }

    private func endAdjust() {
        guard let original = adjustDragOriginal else { return }
        history.record(current: original)
        adjustDragOriginal = nil
    }

    var body: some View {
        let _ = PlaybackMetrics.shared.count(.shellBodyEvals)
        Group {
            if isFullscreen {
                fullscreenStage
            } else {
                windowedShell
            }
        }
        // Developer-only, hidden unless switched on in Account > Developer.
        // See PLAYBACK_PIPELINE.md.
        .overlay(alignment: .top) { PlaybackMetricsHUD().padding(.top, 52) }
        // Ignore `0` — a transient artifact during the cover's presentation
        // animation, not a real measurement (see ui-design-note.md).
        .onPreferenceChange(TitlebarHeightKey.self) { newValue in
            guard newValue > 0 else { return }
            titlebarHeight = newValue
        }
        .task { engine.prepare() }
        .onDisappear { engine.pause() }
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
                    StagePreview(
                        composition: project.composition,
                        assets: project.assets,
                        layers: project.layers,
                        filters: project.filters ?? [],
                        engine: engine
                    )
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
                        engine: engine,
                        selectedLayerId: $selectedLayerId,
                        selectedAudioClipId: $selectedAudioClipId,
                        onTrimBegin: beginTrim,
                        onTrimUpdate: updateTrim,
                        onTrimEnd: endTrim,
                        fps: project.composition.fps
                    )
                    .frame(height: timelineHeight)
                    .clipped()
                    Divider()
                    if let selectedTool, showsToolPanel {
                        ToolOptionsPanel(
                            tool: selectedTool,
                            composition: project.composition,
                            selectedLayer: project.layers.first { $0.id == selectedLayerId },
                            selectedAudioClip: project.audio.tracks.flatMap(\.clips).first { $0.id == selectedAudioClipId },
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
                            },
                            onExtractAudio: { layerId in extractAudio(fromLayerId: layerId) },
                            onPickAudioFile: { url in addAudio(from: url) },
                            onSetAudioVolume: { clipId, gainDb in apply(SetAudioClipVolumeCommand(clipId: clipId, gainDb: gainDb)) },
                            onDeleteAudio: { clipId in
                                apply(DeleteAudioClipCommand(clipId: clipId))
                                selectedAudioClipId = nil
                            },
                            onRecordingFinished: { url in addAudio(from: url) },
                            onAddSoundEffect: { preset in
                                apply(AddAudioClipCommand(asset: SoundEffectCatalog.asset(for: preset), durationMs: preset.durationMs, atMs: currentTimeMs))
                            },
                            onAddText: { text in addText(text) },
                            onSetTextContent: { layerId, text in apply(SetTextContentCommand(layerId: layerId, text: text)) },
                            adjustValues: selectedLayerId.flatMap { adjustIntents[$0] } ?? AdjustValues(),
                            onAdjustBegin: beginAdjust,
                            onAdjustChange: { layerId, values in updateAdjust(layerId: layerId, values: values) },
                            onAdjustEnd: endAdjust
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

                StagePreview(
                    composition: project.composition,
                    assets: project.assets,
                    layers: project.layers,
                    filters: project.filters ?? [],
                    engine: engine
                )
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
                        engine.togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity).animation(.easeOut(duration: 0.18)))
                }

                FullscreenScrubber(engine: engine, isDragging: $isScrubbing)

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
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
        } else {
            Button("Cancel") { dismiss() }
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if #available(iOS 26.0, *) {
            Button("Export") { dismiss() }
                .buttonStyle(.glassProminent)
        } else {
            Button("Export") { dismiss() }
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
                    engine.togglePlay()
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
    let engine: EditorPlaybackEngine
    @Binding var isDragging: Bool

    private var fraction: Double {
        guard engine.maxDurationMs > 0 else { return 0 }
        return min(max(engine.currentTimeMs / engine.maxDurationMs, 0), 1)
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
                    .onEnded { _ in
                        isDragging = false
                        engine.endScrub(velocityMsPerSecond: 0)
                    }
            )
        }
        .frame(height: 24)
    }

    private func beginScrubbingIfNeeded() {
        guard !isDragging else { return }
        isDragging = true
        engine.beginScrub()
    }

    private func seek(to x: CGFloat, trackWidth: CGFloat) {
        let fraction = min(max(x / trackWidth, 0), 1)
        engine.scrub(toMs: fraction * engine.maxDurationMs)
    }
}

/// Wraps `PreviewCanvas`, reading `engine.currentTimeMs`/`engine.mode`
/// itself instead of taking them as plain values from the caller. Observing
/// `@Observable` state inside a view's own `body` ties *that* view's
/// Observation dependency to the property, not the caller's — so by reading
/// the playhead here instead of in `EditorShellView.windowedShell`/
/// `fullscreenStage`, only this small view re-evaluates on every display
/// tick during Play/scrub, not all of `EditorShellView.body` (toolbar,
/// timeline, tool panel...). Same isolation `FullscreenScrubber` already
/// used for the scrub track below.
private struct StagePreview: View {
    let composition: V2Composition
    let assets: [V2Asset]
    let layers: [V2Layer]
    let filters: [V2Filter]
    let engine: EditorPlaybackEngine

    var body: some View {
        PreviewCanvas(
            composition: composition,
            assets: assets,
            layers: layers,
            filters: filters,
            atMs: engine.currentTimeMs,
            playerEngine: engine
        )
        // Load-bearing — see ui-design-note.md (PreviewCanvas has no
        // interactive content of its own; without this, its GeometryReader
        // + .scaleEffect silently absorbs taps meant for sibling buttons).
        .allowsHitTesting(false)
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
