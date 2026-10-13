import SwiftUI
import AVFoundation

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
    /// The tool whose options replace the bottom row (nil = no tool open). Only tools with an options panel are
    /// ever set here; Edit instead selects the clip under the playhead.
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
    /// The Filter picked per clip (session-only, like `adjustIntents`) and the pre-gesture snapshot for its undo step.
    @State private var filterIntents: [String: AppliedFilter] = [:]
    @State private var filterDragOriginal: V2Project?
    @State private var showingFilterSheet = false
    @State private var showingStickerSheet = false
    @State private var showingGraphSheet = false
    /// The Transform values last synced from the playhead on a keyframed layer: an edit that equals them writes nothing.
    @State private var transformSynced: TransformValues?
    @State private var stickerStore = StickerStore()
    /// The selected video has a sound track (probed when the selection changes) - decides Volume / Extract Audio / Unlink.
    @State private var selectedHasAudio = false
    /// A tool that is only a button so far: the short "<tool> is coming soon" note over the stage.
    @State private var comingSoonTitle: String?
    /// Which ruler the Transform sheet opens on (the Opacity tool opens it on Opacity).
    @State private var transformFocus: TransformControl = .x
    /// Adjust and Transform are sheets over the lower part of the screen, not rows (see `AdjustSheet`/`TransformSheet`).
    @State private var showingAdjustSheet = false
    @State private var showingTransformSheet = false
    /// The Transform sheet's values for the selected layer; the sheet's rulers and the stage gestures both write here.
    @State private var transformValues = TransformValues()
    /// Same "one undo step per drag" shape as `adjustDragOriginal`.
    @State private var transformDragOriginal: V2Project?
    private let toolbarHeight: CGFloat = 58
    private let toolPanelHeight: CGFloat = 64
    /// The bottom row sits this much lower than the safe-area edge (into the home-indicator margin); the timeline gets the points.
    private let bottomBarDrop: CGFloat = 8

    /// The bottom of the editor is always ONE row; going deeper replaces it (CapCut style) and "«" comes back:
    ///   main tools -> the selected clip's tools -> a tool's own options.
    private enum BottomMode {
        case main
        case selection(SelectionToolbarView.Subject)
        case toolPanel(EditorTool)
    }

    private var bottomMode: BottomMode {
        if let selectedTool, selectedTool.hasOptionsPanel { return .toolPanel(selectedTool) }
        if let layer = project.layers.first(where: { $0.id == selectedLayerId }) { return .selection(.layer(layer)) }
        if project.audio.tracks.flatMap(\.clips).contains(where: { $0.id == selectedAudioClipId }) { return .selection(.audioClip) }
        return .main
    }

    private var bottomBarHeight: CGFloat {
        if case .toolPanel = bottomMode { return toolPanelHeight }
        return toolbarHeight
    }

    /// Set when the project came from a template: Export then spends the template's credits first.
    private let exportContext: TemplateExportContext?
    @State private var exportGate = ExportGate()

    init(project: V2Project, exportContext: TemplateExportContext? = nil) {
        self.exportContext = exportContext
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
    private func endTrim(edge: HorizontalEdge, layerId: String) {
        guard let original = trimDragOriginal else { return }
        // Main-lane magnet: a trim leaves a hole in the main lane; close it now, in the same undo step.
        let packed = PackMainLaneCommand().apply(to: project)
        withAnimation(.easeOut(duration: 0.2)) { setProject(packed) }
        history.record(current: original)
        trimDragOriginal = nil
        // The playhead goes to the edge that was dragged: a left handle -> the clip's head, a right handle -> its tail
        // minus one frame (after packing/rippling). The time floor lowered for a main-lane left trim is restored once it has landed.
        if let layer = packed.layers.first(where: { $0.id == layerId }) {
            let target = trimLandingTimeMs(isLeadingHandle: edge == .leading, layer: layer, fps: packed.composition.fps)
            engine.glide(toMs: target) { [engine] in engine.setTimeFloor(0) }
        } else {
            engine.setTimeFloor(0)
        }
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
        setProject(SetAdjustCommand(layerId: layerId, values: values, filter: filterIntents[layerId]).apply(to: project))
    }

    // MARK: Keyframes (Transform only; model in `Keyframes/TransformKeyframes.swift`)

    /// One frame of the composition: a keyframe within it of the playhead counts as "on" the playhead.
    private var keyframeSnapMs: Double { 1000 / max(project.composition.fps, 1) }

    /// The selected layer's keyframe at the playhead (clip-local ms), if there is one.
    private var keyframeAtPlayhead: Double? {
        selectedLayer.flatMap { TransformKeyframes.keyframe(of: $0, atMs: currentTimeMs, toleranceMs: keyframeSnapMs) }
    }

    /// A keyframe can be set while a layer is selected and the playhead is inside it.
    private var canToggleKeyframe: Bool {
        guard let layer = selectedLayer else { return false }
        return currentTimeMs >= layer.timing.start && currentTimeMs <= layer.timing.start + layer.timing.duration
    }

    /// One undo step each way.
    private func toggleKeyframe() {
        guard let id = selectedLayerId, canToggleKeyframe else { return }
        if keyframeAtPlayhead != nil {
            apply(RemoveKeyframeCommand(layerId: id, atMs: currentTimeMs, toleranceMs: keyframeSnapMs))
        } else {
            apply(AddKeyframeCommand(layerId: id, atMs: currentTimeMs, toleranceMs: keyframeSnapMs))
        }
    }

    /// Graph is live only while the playhead sits between two keyframes of the selection (clip-local start of that segment).
    private var graphSegmentStart: Double? {
        selectedLayer.flatMap { TransformKeyframes.segmentStart(of: $0, atMs: currentTimeMs) }
    }

    // MARK: Stickers

    /// Tapping a sticker copies its picture into the project's media (once) and puts it on the canvas at the playhead,
    /// selected, so Transform / Opacity / Delete are one tap away. The sheet stays open to add more.
    private func addSticker(_ sticker: APIStickerCatalogue.Sticker) {
        Task {
            guard let asset = try? await stickerStore.importAsset(for: sticker) else { return }
            let layerId = "\(stickerLayerIdPrefix)\(UUID().uuidString.prefix(8).lowercased())"
            apply(AddStickerCommand(layerId: layerId, asset: asset, atMs: currentTimeMs))
            selectedLayerId = layerId
            selectedAudioClipId = nil
        }
    }

    @ViewBuilder private var stickerSheet: some View {
        StickerSheet(store: stickerStore, onPick: addSticker)
    }

    // MARK: Filter

    private func beginFilter() {
        guard filterDragOriginal == nil else { return }
        filterDragOriginal = project
    }

    /// A filter pick or an Intensity tick: the picked look plus whatever the Adjust sliders hold, compiled together.
    private func updateFilter(layerId: String, filter: AppliedFilter?) {
        filterIntents[layerId] = filter
        setProject(SetAdjustCommand(layerId: layerId, values: adjustIntents[layerId] ?? AdjustValues(), filter: filter).apply(to: project))
    }

    private func endFilter() {
        guard let original = filterDragOriginal else { return }
        history.record(current: original)
        filterDragOriginal = nil
    }

    @ViewBuilder private var filterSheet: some View {
        if let id = selectedLayerId {
            FilterSheet(
                layerId: id, initial: filterIntents[id],
                sourceProvider: {
                    guard let layer = project.layers.first(where: { $0.id == id }) else { return nil }
                    return await FilterThumbnails.source(for: layer, project: project, atMs: currentTimeMs)
                },
                onBegin: beginFilter,
                onChange: { layerId, filter in updateFilter(layerId: layerId, filter: filter) },
                onEnd: endFilter
            )
        }
    }

    // MARK: Transform

    private var selectedLayer: V2Layer? { project.layers.first { $0.id == selectedLayerId } }

    private func openTransformSheet(focus: TransformControl = .x) {
        guard let layer = selectedLayer else { return }
        transformFocus = focus
        transformValues = TransformValues(layer: layer, atMs: currentTimeMs)   // before the flag, so `onChange` below ignores it
        transformSynced = transformValues
        showingTransformSheet = true
    }

    private func beginTransform() {
        guard transformDragOriginal == nil else { return }
        transformDragOriginal = project
    }

    /// Live: every change goes straight to the project (bypassing `apply(_:)`), like `updateAdjust`.
    private func updateTransform(_ values: TransformValues) {
        guard showingTransformSheet, let id = selectedLayerId, values != transformSynced else { return }
        transformSynced = nil
        setProject(SetTransformCommand(layerId: id, values: values, atMs: currentTimeMs).apply(to: project))
    }

    private func endTransform() {
        guard let original = transformDragOriginal else { return }
        history.record(current: original)
        transformDragOriginal = nil
    }

    @ViewBuilder private var adjustSheet: some View {
        if let id = selectedLayerId {
            AdjustSheet(
                layerId: id, initial: adjustIntents[id] ?? AdjustValues(),
                onBegin: beginAdjust,
                onChange: { layerId, values in updateAdjust(layerId: layerId, values: values) },
                onEnd: endAdjust
            )
        }
    }

    private var transformSheet: some View {
        TransformSheet(values: $transformValues, composition: project.composition, initialControl: transformFocus, onBegin: beginTransform, onEnd: endTransform)
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
        .alert(item: $exportGate.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingAdjustSheet) { adjustSheet }
        .sheet(isPresented: $showingFilterSheet) { filterSheet }
        .sheet(isPresented: $showingStickerSheet) { stickerSheet }
        .sheet(isPresented: $showingGraphSheet) {
            if let id = selectedLayerId, let layer = selectedLayer, let start = graphSegmentStart {
                GraphSheet(easing: LabEasing(v2: TransformKeyframes.easing(of: layer, segmentStart: start))) {
                    apply(SetKeyframeEasingCommand(layerId: id, segmentStartMs: start, easing: $0.v2))
                }
            }
        }
        .sheet(isPresented: $showingTransformSheet) { transformSheet }
        .onChange(of: transformValues) { _, new in updateTransform(new) }
        // Scrubbing with the Transform sheet open on a keyframed layer: show the values at the new playhead (no write).
        .onChange(of: currentTimeMs) { _, time in
            guard showingTransformSheet, let layer = selectedLayer, TransformKeyframes.isKeyframed(layer) else { return }
            let sampled = TransformValues(layer: layer, atMs: time)
            guard sampled != transformValues else { return }
            transformSynced = sampled
            transformValues = sampled
        }
        .task(id: selectedLayerId) { await probeSelectedAudio() }
        .overlay(alignment: .bottom) {
            if let title = comingSoonTitle {
                Text("\(title) is coming soon")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 96)
                    .transition(.opacity)
                    .accessibilityIdentifier("comingSoonToast")
            }
        }
        .animation(.easeOut(duration: 0.2), value: comingSoonTitle)
        .task(id: comingSoonTitle) {
            guard comingSoonTitle != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            comingSoonTitle = nil
        }
        #if DEBUG
        // Env-driven unattended metrics run (`PLAYBACK_METRICS_SCENARIO`); no-op otherwise.
        .task { await PlaybackMetrics.shared.autoRunIfRequested() }
        #endif
        .onDisappear { engine.pause() }
    }

    // MARK: Bottom bar (one row)

    @ViewBuilder
    private var bottomBar: some View {
        switch bottomMode {
        case .main:
            EditorToolbarView(onSelect: handleToolTap)
        case .selection(let subject):
            SelectionToolbarView(
                subject: subject,
                hasAudio: selectedHasAudio,
                canSplit: canSplitSelection,
                canGraph: graphSegmentStart != nil,
                onBack: { selectedLayerId = nil; selectedAudioClipId = nil },
                onTool: handleClipTool
            )
        case .toolPanel(let tool):
            HStack(spacing: 8) {
                BottomBarBackButton { selectedTool = nil }
                optionsPanel(for: tool)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
        }
    }

    /// One entry for every button of the selection row. Built tools do their job; the others only say they are coming
    /// (the UI exists first, each tool gets built one by one).
    private func handleClipTool(_ tool: ClipTool) {
        switch tool {
        case .split:
            guard let id = selectedLayerId else { return }
            apply(SplitClipCommand(layerId: id, atMs: currentTimeMs))
            selectedLayerId = nil
        case .transform: openTransformSheet()
        case .graph: if graphSegmentStart != nil { showingGraphSheet = true }
        case .opacity: openTransformSheet(focus: .opacity)
        case .adjust: showingAdjustSheet = true
        case .filter: showingFilterSheet = true
        case .editText: selectedTool = .text
        case .mirror:
            guard let id = selectedLayerId else { return }
            apply(MirrorLayerCommand(layerId: id))
        case .duplicate where selectedLayerId?.hasPrefix(stickerLayerIdPrefix) == true:
            guard let id = selectedLayerId else { return }
            let copyId = "\(id)-copy-\(UUID().uuidString.prefix(6).lowercased())"
            apply(DuplicateOverlayCommand(layerId: id, newLayerId: copyId))
            selectedLayerId = copyId
        case .volume:
            if selectedAudioClipId != nil { selectedTool = .audio } else { comingSoonTitle = tool.title }
        case .delete:
            if let id = selectedLayerId {
                apply(DeleteClipCommand(layerId: id))
                selectedLayerId = nil
            } else if let id = selectedAudioClipId {
                apply(DeleteAudioClipCommand(clipId: id))
                selectedAudioClipId = nil
            }
        default:
            comingSoonTitle = tool.title
        }
    }

    /// Whether the selected clip is a video whose file has a sound track.
    private func probeSelectedAudio() async {
        guard let layer = selectedLayer, case .video(let payload) = layer.payload,
              case .video(let asset)? = project.assets.first(where: { $0.id == payload.assetId }),
              let url = bundledURL(filename: asset.uri)
        else { selectedHasAudio = false; return }
        let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        selectedHasAudio = !(tracks ?? []).isEmpty
    }

    /// Split only makes sense strictly inside the clip's own range - at either edge it would leave a zero-length half.
    private var canSplitSelection: Bool {
        guard let layer = project.layers.first(where: { $0.id == selectedLayerId }) else { return false }
        return currentTimeMs > layer.timing.start && currentTimeMs < layer.timing.start + layer.timing.duration
    }

    private func handleToolTap(_ tool: EditorTool) {
        switch tool {
        case .edit: selectClipAtPlayhead()
        case .adjust:
            // Adjust needs a picture or a clip: pick the one under the playhead, then open its sheet.
            selectClipAtPlayhead()
            if let layer = project.layers.first(where: { $0.id == selectedLayerId }), layer.type == "video" || layer.type == "image" {
                showingAdjustSheet = true
            }
        case .stickers: showingStickerSheet = true
        case .filter:
            // Filter, like Adjust, needs a picture or a clip: pick the one under the playhead, then open its sheet.
            selectClipAtPlayhead()
            if let layer = project.layers.first(where: { $0.id == selectedLayerId }), layer.type == "video" || layer.type == "image" {
                showingFilterSheet = true
            }
        default: selectedTool = tool
        }
    }

    /// Edit: selects what is under the playhead (a video or photo first, then text, then an audio clip), which opens that
    /// thing's tools. Nothing there = nothing happens.
    private func selectClipAtPlayhead() {
        let t = currentTimeMs
        let rank = ["video": 0, "image": 1, "text": 2]
        let candidate = project.layers
            .filter { $0.type != "group" && t >= $0.timing.start && t < $0.timing.start + $0.timing.duration }
            .min { (rank[$0.type] ?? 3) < (rank[$1.type] ?? 3) }
        if let candidate {
            selectedLayerId = candidate.id
            selectedAudioClipId = nil
        } else if let clip = project.audio.tracks.flatMap(\.clips).first(where: { t >= $0.timing.start && t < $0.timing.start + $0.timing.duration }) {
            selectedAudioClipId = clip.id
            selectedLayerId = nil
        }
    }

    private func optionsPanel(for tool: EditorTool) -> some View {
        ToolOptionsPanel(
            tool: tool,
            composition: project.composition,
            selectedLayer: project.layers.first { $0.id == selectedLayerId },
            selectedAudioClip: project.audio.tracks.flatMap(\.clips).first { $0.id == selectedAudioClipId },
            onSetAspectRatio: { width, height in apply(SetAspectRatioCommand(width: width, height: height)) },
            onSetBackgroundColor: { hex in apply(SetBackgroundColorCommand(hex: hex)) },
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
            onComingSoon: { title in comingSoonTitle = title }
        )
    }

    private var windowedShell: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                // Stage: a square sized from width alone (see ui-design-note.md).
                let squareSide = geo.size.width
                let videoBoxSide = squareSide * 0.96
                let stageHeight = squareSide
                // Timeline: whatever's left after Stage/Titlebar/the one bottom row, no floor (see ui-design-note.md).
                let reservedHeight = titlebarHeight + stageHeight + bottomBarHeight
                let timelineHeight = max(geo.size.height - reservedHeight - 2, 0) + bottomBarDrop

                VStack(spacing: 0) {
                    StagePreview(
                        composition: project.composition,
                        assets: project.assets,
                        layers: project.layers,
                        filters: project.filters ?? [],
                        engine: engine
                    )
                    .frame(width: videoBoxSide, height: videoBoxSide)
                    .overlay {
                        // While the Transform sheet is open the stage can be dragged, pinched and twisted directly.
                        if showingTransformSheet, let layer = selectedLayer {
                            TransformGestureOverlay(
                                values: $transformValues, composition: project.composition, layerFrame: layer.frame,
                                onBegin: beginTransform, onEnd: endTransform
                            )
                        }
                    }
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
                        fps: project.composition.fps,
                        keyframeTimes: selectedLayer.map(TransformKeyframes.visibleTimelineTimes) ?? []
                    )
                    .frame(height: timelineHeight)
                    .clipped()
                    Divider()
                    bottomBar
                        .frame(height: bottomBarHeight)
                        .zIndex(1)
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
                    .padding(.bottom, 80)
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
                        .glassEffect(.regular, in: barShape)
                }
            } else {
                fullscreenControlBarContent
                    .background(.ultraThinMaterial, in: barShape)
            }
        }
        .frame(width: barWidth)
        // Short ease-out, no spring and no `.interactive()` glass (no press-grow): the bar
        // keeps its width and only gets taller (capsule → taller rectangle), while the
        // progress track grows into the space the two icons leave (user, 2026-10-10).
        .animation(.easeOut(duration: 0.15), value: isScrubbing)
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
    /// Each button fades out in place (`.transition(.opacity…)`, 0.18 s) — no slide:
    /// a `.move` transition carried the icons out of the capsule while they faded.
    private var fullscreenControlBarContent: some View {
        VStack(spacing: 6) {
            if isScrubbing {
                HStack {
                    Text(formattedTime(currentTimeMs, includeFraction: true))
                    Spacer()
                    Text(formattedTime(maxDurationMs, includeFraction: false))
                }
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.primary)
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                if !isScrubbing {
                    Button {
                        engine.togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .fontWeight(.regular)
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityIdentifier("fullscreen-play")
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
                }

                FullscreenScrubber(engine: engine, isDragging: $isScrubbing)

                if !isScrubbing {
                    Button {
                        isFullscreen = false
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.title3)
                            .fontWeight(.regular)
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                    }
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
                }
            }
        }
        .padding(.horizontal, 10)
        // Scrubbing turns the pill into a taller rounded rectangle: +8 pt (4 above, 4 below).
        .padding(.vertical, isScrubbing ? 14 : 10)
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
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var cancelButton: some View {
        let cancel = Button("Cancel") { dismiss() }.controlSize(.small)
        if #available(iOS 26.0, *) {
            cancel.buttonStyle(.glass)
        } else {
            cancel.foregroundColor(.primary)
        }
    }

    /// Charges first (template projects), shows a spinner meanwhile, and only then renders.
    @ViewBuilder
    private var exportButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: startExport) { exportLabel }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(exportGate.isWorking)
        } else {
            Button(action: startExport) { exportLabel }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(exportGate.isWorking)
        }
    }

    @ViewBuilder
    private var exportLabel: some View {
        if exportGate.isWorking { ProgressView().frame(minWidth: 44) } else { Text("Export") }
    }

    private func startExport() {
        Task {
            await exportGate.export(project: project, context: exportContext)
            if exportGate.completed { dismiss() }
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

                Spacer()

                HStack(spacing: 22) {
                    Button(action: toggleKeyframe) {
                        KeyframeIcon(hasKeyframeHere: keyframeAtPlayhead != nil)
                    }
                    .disabled(!canToggleKeyframe)
                    .accessibilityIdentifier("keyframe-toggle")
                    Button {
                        isFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.headline)
                            .fontWeight(.regular)
                    }
                    .accessibilityIdentifier("enter-fullscreen")
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
/// Relative scrubbing: the thumb never jumps to where the finger lands.
/// Touch-down switches the bar to its scrubbing state at once
/// (`DragGesture(minimumDistance: 0)`): the idle capsule is only a progress
/// preview, and since scrubbing is relative, touching it never moves the time.
/// It used to need a 0.2 s hold first
/// (`LongPressGesture.sequenced(before:)`), which failed outright when the finger
/// moved more than 10 pt during the hold — so grabbing the thumb and dragging
/// straight away never seeked.
private struct FullscreenScrubber: View {
    let engine: EditorPlaybackEngine
    @Binding var isDragging: Bool
    @Environment(\.colorScheme) private var colorScheme
    /// True while a touch owns the gesture. Unlike `onEnded`, a `@GestureState`
    /// also resets when the system cancels the gesture, so the bar can never stay
    /// stuck in its scrubbing state (see `.onChange` below).
    @GestureState private var touchActive = false
    /// Playhead time when the current scrub began.
    @State private var scrubStartMs = 0.0
    /// The finger has left the dead zone at least once in this scrub.
    @State private var scrubMoved = false

    private var fraction: Double {
        guard engine.maxDurationMs > 0 else { return 0 }
        return min(max(engine.currentTimeMs / engine.maxDurationMs, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Measured on the Photos player bar: the track is white (57 % on the light glass, 36 % on the dark),
                // the played part is the label colour (≈ black 27 % on light, ≈ white 90 % on dark).
                Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.36 : 0.57))
                Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.27))
                    .frame(width: geo.size.width * fraction)
            }
            // A fill narrower than the track's end cap is a thin bar that pokes out of
            // the rounded end; clipping keeps it inside the track.
            .clipShape(Capsule())
            .frame(height: isDragging ? 18 : 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                // Global: the bar widens the instant it is touched, which would shift a local space.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touchActive) { _, state, _ in state = true }
                    .onChanged { drag in
                        beginScrubbingIfNeeded()
                        // Relative: the time starts where it was and moves by the finger's
                        // travel (a full track width = the whole duration) — grabbing the
                        // track in the middle never jumps there.
                        seek(byTravel: drag.translation.width, trackWidth: geo.size.width)
                    }
                    .onEnded { _ in endScrubbing() }
            )
        }
        .frame(height: 24)
        .onChange(of: touchActive) { _, active in
            if !active { endScrubbing() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("fullscreen-scrubber")
        #if DEBUG
        .accessibilityValue(String(format: "%.0f", engine.currentTimeMs))
        #endif
    }

    private func endScrubbing() {
        guard isDragging else { return }
        isDragging = false
        engine.endScrub(velocityMsPerSecond: 0)
    }

    private func beginScrubbingIfNeeded() {
        guard !isDragging else { return }
        isDragging = true
        scrubStartMs = engine.currentTimeMs
        scrubMoved = false
        engine.beginScrub()
    }

    /// Finger travel that does not move the time: a touch always rolls 1–2 pt, and one
    /// point is ~0.26 s of an 89 s video. The dead zone is subtracted, so the time still
    /// starts from `t0` and moves continuously once the finger is past it.
    static let deadZone: CGFloat = 4

    private func seek(byTravel dx: CGFloat, trackWidth: CGFloat) {
        guard trackWidth > 0 else { return }
        let effective = dx.magnitude > Self.deadZone ? dx - Self.deadZone * (dx < 0 ? -1 : 1) : 0
        // A touch that has not left the dead zone sends no seek at all: the scrub seek is
        // coarse (0.2 s tolerance), so it would land the video on a frame before the exact
        // one it is resting on, and the exact seek on release would then jump it back.
        if effective == 0 && !scrubMoved { return }
        scrubMoved = true
        engine.scrub(toMs: min(max(scrubStartMs + Double(effective / trackWidth) * engine.maxDurationMs, 0), engine.maxDurationMs))
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
struct StagePreview: View {
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
