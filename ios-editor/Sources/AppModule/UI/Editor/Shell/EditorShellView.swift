import SwiftUI
import AVFoundation

private struct TransitionPickerTarget: Identifiable {
    let outgoingId: String
    let incomingId: String
    let kind: TransitionKind?
    var durationMs: Double
    var id: String { "\(outgoingId)->\(incomingId)" }
}

/// The real Editor screen's shell — nav bar (`Huỷ`/`Xuất`), then Stage /
/// Titlebar / Timeline. See `ui-design-note.md` (repo root) for the full
/// layout rationale and bug history.
struct EditorShellView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var project: V2Project
    /// Cut-level authoring intent belongs to the editor document. V2 transition groups are built only for rendering.
    @State private var transitionIntents: [EditorTransitionIntent]
    /// Owns the playhead clock, Play/Pause, scrubbing + momentum
    /// (`Playback/EditorPlaybackEngine.swift`). This view only sends it
    /// commands and reads from it — it never writes the time.
    @State private var engine: EditorPlaybackEngine
    private var currentTimeMs: Double { engine.editorTimeMs }
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
    @State private var trimDragOriginalTransitions: [EditorTransitionIntent]?
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
    @State private var showingAnimationSheet = false
    @State private var showingCoverEditor = false
    @State private var coverImageOverride: UIImage?
    @State private var transitionPickerTarget: TransitionPickerTarget?
    @State private var showingSpeedSheet = false
    /// Crop: the full-length popup, the frame being edited and the still it is drawn on.
    @State private var cropSession: CropSession?
    @State private var cropDraft = CropDraft()
    @State private var cropStill: UIImage?
    @State private var cropLayerId: String?
    /// Mask: the shape row replaces the clip row (`showingMaskTools`), the popup (`maskSession`), and the project before the first live change of an edit
    /// (the undo step, taken lazily like the Volume and Speed sessions).
    @State private var showingMaskTools = false
    @State private var maskSession: MaskSession?
    @State private var maskSessionOriginal: V2Project?
    /// Remove BG (photo): its row (`showingRemoveBgTools`) and popup; the undo step shares `maskSessionOriginal`.
    @State private var showingRemoveBgTools = false
    @State private var removeBgSession: RemoveBackgroundSession?
    @State private var showingChromaKeySheet = false
    @State private var chromaKeyDraft = ChromaKeyDraft()
    @State private var chromaKeySessionOriginal: V2Project?
    /// The Volume / Fade popup, when open: the request carries which side to open (Volume tool -> Volume, Fade tool -> Fade).
    @State private var volumeRequest: VolumeSheet.Request?
    @State private var mediaPicker: MediaPickerPurpose?
    /// Freeze the insertion target when `+` is tapped; presenting the picker can clear timeline selection.
    @State private var mainLaneInsertAfterLayerId: String?
    @State private var importingMainLaneMedia = false
    /// Audio > Extract is working (the sound is being exported from the picked video).
    @State private var extractingAudio = false
    @State private var mediaError: String?
    @State private var textSessionTab: TextSheet.Tab = .font
    /// The project as it was when the Speed sheet opened: every ruler tick is computed from it, and it is the undo step.
    @State private var speedSessionOriginal: V2Project?
    /// The project before the Volume sheet's first change: that is the undo step (like `speedSessionOriginal`).
    @State private var volumeSessionOriginal: V2Project?
    @State private var showingStickerSheet = false
    @State private var showingSoundSheet = false
    @State private var showingRecorderSheet = false
    @State private var showingGraphSheet = false
    /// The Text sheet session: one undo step for everything done in it (like Transform), `textSessionOriginal` is the project before it.
    @State private var showingTextSheet = false
    @State private var textValues = TextStyleValues()
    @State private var textSessionOriginal: V2Project?
    @State private var textSessionInitial = TextStyleValues()
    @State private var textSessionLayerId: String?
    @State private var textSessionIsNew = false
    /// The Transform values last synced from the playhead on a keyframed layer: an edit that equals them writes nothing.
    @State private var transformSynced: TransformValues?
    @State private var stickerStore = StickerStore()
    @State private var soundStore = SoundStore()
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
    private let topBarButtonSize = CGSize(width: 68, height: 30)
    /// A tool's options row is exactly as tall as the other rows (user 2026-10-16: the Edit row's height).
    private var toolPanelHeight: CGFloat { toolbarHeight }
    /// The bottom row sits this much lower than the safe-area edge (into the home-indicator margin); the timeline gets the points.
    private let bottomBarDrop: CGFloat = 8

    /// The bottom of the editor is always ONE row; going deeper replaces it (CapCut style) and "«" comes back:
    ///   main tools -> the selected clip's tools -> a tool's own options.
    private enum BottomMode {
        case main
        case selection(SelectionToolbarView.Subject)
        case toolPanel(EditorTool)
        case maskTools
        case removeBgTools
    }

    private var bottomMode: BottomMode {
        if let selectedTool, selectedTool.hasOptionsPanel { return .toolPanel(selectedTool) }
        if showingMaskTools, let layer = selectedLayer, layer.type == "video" || layer.type == "image" { return .maskTools }
        if showingRemoveBgTools, let layer = selectedLayer, layer.type == "image" || layer.type == "video" { return .removeBgTools }
        if let layer = project.layers.first(where: { $0.id == selectedLayerId }) { return .selection(.layer(layer)) }
        if project.audio.tracks.flatMap(\.clips).contains(where: { $0.id == selectedAudioClipId }) { return .selection(.audioClip) }
        return .main
    }

    /// A clip picked on the timeline gives the bottom row to that clip's tools: an open tool panel (Audio's Extract / Music / Record ...) closes,
    /// otherwise `bottomMode` keeps showing the panel and the selection looks ignored.
    private func timelineSelection(_ selection: Binding<String?>) -> Binding<String?> {
        Binding(
            get: { selection.wrappedValue },
            set: { id in
                selection.wrappedValue = id
                if id != nil, selectedTool?.hasOptionsPanel == true { selectedTool = nil }
            }
        )
    }

    private var bottomBarHeight: CGFloat {
        if case .toolPanel = bottomMode { return toolPanelHeight }
        return toolbarHeight
    }

    /// Set when the project came from a template: Export then spends the template's credits first.
    private let exportContext: TemplateExportContext?
    @State private var exportGate = ExportGate()
    @State private var exportResolution: ExportResolution = .p1080
    @State private var exportFrameRate = 30
    @State private var exportBitrateMbps = 5
    @State private var showingExportQuality = false

    init(project: V2Project, exportContext: TemplateExportContext? = nil) {
        self.exportContext = exportContext
        let extracted = TransitionWrappers.extracting(from: project)
        _project = State(initialValue: extracted.project)
        _transitionIntents = State(initialValue: extracted.transitions)
        _engine = State(initialValue: EditorPlaybackEngine(project: extracted.project, transitions: extracted.transitions))
        let supportedFrameRates = [24, 25, 30, 50, 60]
        let sourceFrameRate = project.composition.fps
        let initialFrameRate = supportedFrameRates.min {
            abs(Double($0) - sourceFrameRate) < abs(Double($1) - sourceFrameRate)
        } ?? 30
        _exportFrameRate = State(initialValue: initialFrameRate)
    }

    /// Every write to `project` goes through here so the engine always sees
    /// the same layers the Stage and Timeline render.
    private func setProject(_ newProject: V2Project) {
        let normalized = AnimationWrappers.normalized(newProject)
        transitionIntents = TransitionWrappers.validIntents(transitionIntents, for: normalized)
        project = normalized
        engine.update(project: normalized, transitions: transitionIntents)
    }

    private func recordHistory(current: V2Project, transitions: [EditorTransitionIntent]? = nil) {
        history.record(current: current, transitions: transitions ?? transitionIntents)
    }

    /// The one path every edit must go through — see `EditorHistory`'s own
    /// doc comment on why this snapshots the whole document rather than
    /// asking each `EditorCommand` to carry its own inverse.
    private func apply(_ command: EditorCommand) {
        recordHistory(current: project)
        if let transitionCommand = command as? SetTransitionCommand {
            let candidate = EditorTransitionIntent(outgoingId: transitionCommand.outgoingId,
                                                   incomingId: transitionCommand.incomingId,
                                                   kind: transitionCommand.kind,
                                                   durationMs: transitionCommand.durationMs ?? 0)
            transitionIntents.removeAll { $0.incomingId == candidate.incomingId }
            if transitionCommand.durationMs != nil {
                let projection = TransitionWrappers.compiling([candidate], into: project)
                if let normalized = TransitionWrappers.applied(for: candidate.incomingId, in: projection.layers) {
                    transitionIntents.append(normalized)
                }
            }
            transitionIntents = TransitionWrappers.validIntents(transitionIntents, for: project)
            engine.update(project: project, transitions: transitionIntents)
            return
        }
        setProject(command.apply(to: project))
    }

    private func undo() {
        guard let previous = history.undo(current: project, transitions: transitionIntents) else { return }
        transitionIntents = previous.transitions
        setProject(previous.project)
    }

    private func redo() {
        guard let next = history.redo(current: project, transitions: transitionIntents) else { return }
        transitionIntents = next.transitions
        setProject(next.project)
    }

    /// Âm thanh — "Thêm nhạc": the file picker hands back a raw URL
    /// (already a temp copy, see `AudioFilePicker`'s own doc comment);
    /// this runs the real import (copy into the sandbox + read duration)
    /// off the main actor's own async context, then applies the result as
    /// one ordinary undoable command, same as every other edit.
    /// A take from the recorder popup: copied into the project's media like any picked audio, then the temp file goes.
    private func addRecording(from url: URL) {
        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let asset = try? await MediaImportService.importAudio(from: url) else { return }
            apply(AddAudioClipCommand(asset: asset, durationMs: asset.duration, atMs: currentTimeMs))
        }
    }

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
    // MARK: Text sheet

    /// "Add text" (new = true) puts a clip with the default words ("Hello") at the playhead and edits it live; "Edit text" opens the selected
    /// text clip. Closing the sheet with empty words undoes the whole session (a new clip disappears, an old one keeps its words).
    private func openTextSheet(new: Bool, tab: TextSheet.Tab = .font) {
        textSessionTab = tab
        let composition = project.composition
        textSessionOriginal = project
        textSessionIsNew = new
        if new {
            let layerId = "text-\(UUID().uuidString.prefix(8))"
            var values = TextStyleValues(composition: composition)
            values.text = TextStyleValues.defaultText
            setProject(AddTextLayerCommand(layerId: layerId, text: values.text, atMs: currentTimeMs, style: values).apply(to: project))
            selectedLayerId = layerId
            selectedAudioClipId = nil
            selectedTool = nil
            textValues = values
            textSessionLayerId = layerId
        } else {
            guard let layer = selectedLayer, layer.type == "text" else { textSessionOriginal = nil; return }
            textValues = TextStyleValues(layer: layer, composition: composition)
            textSessionLayerId = layer.id
        }
        textSessionInitial = textValues
        showingTextSheet = true
    }

    /// Live: every change goes straight to the clip (bypassing `apply(_:)`); empty words show the placeholder.
    private func updateText(_ values: TextStyleValues) {
        guard showingTextSheet, let id = textSessionLayerId else { return }
        var shown = values
        if shown.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { shown.text = TextStyleValues.placeholder }
        setProject(SetTextCommand(layerId: id, values: shown).apply(to: project))
    }

    private func finishTextSession() {
        guard let original = textSessionOriginal else { return }
        defer { textSessionOriginal = nil; textSessionLayerId = nil }
        let empty = textValues.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty {
            setProject(original)
            if textSessionIsNew { selectedLayerId = nil }
            return
        }
        if textSessionIsNew || textValues != textSessionInitial { recordHistory(current: original) }
    }

    /// Called once when a trim-handle drag starts — snapshots the
    /// pre-drag project so `endTrim()` can record *that* into history,
    /// not whatever the live-updated project happens to be by then.
    private func beginTrim() {
        guard trimDragOriginal == nil else { return }
        trimDragOriginal = project
        trimDragOriginalTransitions = transitionIntents
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
        recordHistory(current: original, transitions: trimDragOriginalTransitions)
        trimDragOriginal = nil
        trimDragOriginalTransitions = nil
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

    // MARK: Sound FX

    /// Use in the Sound FX sheet: copies the file into the project's media (once) and puts the sound on the audio lane at the playhead.
    /// The sheet stays open to add more; false when the file could not be fetched.
    private func addSoundEffect(_ sound: APISoundCatalogue.Sound) async -> Bool {
        guard let asset = try? await soundStore.importAsset(for: sound) else { return false }
        apply(AddAudioClipCommand(asset: asset, durationMs: asset.duration, atMs: currentTimeMs))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
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
        recordHistory(current: original)
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

    // MARK: Replace

    /// A photo or video was picked for Replace: copy it into the app, then apply the command (one undo step).
    private func usePickedMedia(_ picked: PickedMedia, for purpose: MediaPickerPurpose) async {
        let assetId = "media-\(UUID().uuidString.prefix(8).lowercased())"
        do {
            let asset = try await PhotoImporter.importMedia(picked.asset, kind: picked.kind, assetId: assetId)
            apply(ReplaceClipCommand(layerId: purpose.layerId, asset: asset))
            engine.refreshFrames()
        } catch {
            mediaError = error.localizedDescription
        }
    }

    /// Imports the selected batch and inserts it after the selected main-lane clip (or at the end) in one command/undo step.
    private func appendPickedMediaToMainLane(_ picked: [PickedMedia]) async {
        guard !picked.isEmpty else { return }
        importingMainLaneMedia = true
        defer { importingMainLaneMedia = false }

        let insertAfterLayerId = mainLaneInsertAfterLayerId
        mainLaneInsertAfterLayerId = nil
        let mainOrder = primaryVideoLaneOrder(of: project.layers)
        let selectedMainLaneClip = insertAfterLayerId.flatMap { selectedId in
            project.layers.first { $0.id == selectedId && $0.order == mainOrder && isPushLane($0) }
        }
        let mainClips = project.layers.filter { $0.order == mainOrder && isPushLane($0) }
        let insertionTime = selectedMainLaneClip.map { $0.timing.start + $0.timing.duration }
            ?? (mainClips.map { $0.timing.start + $0.timing.duration }.max() ?? 0)
        var items: [MainLaneMediaItem] = []
        var firstImportError: Error?
        for media in picked {
            let layerId = "main-\(UUID().uuidString.prefix(8).lowercased())"
            let assetId = "media-\(UUID().uuidString.prefix(8).lowercased())"
            do {
                let asset = try await PhotoImporter.importMedia(media.asset, kind: media.kind, assetId: assetId)
                items.append(MainLaneMediaItem(asset: asset, layerId: layerId))
            } catch {
                if firstImportError == nil { firstImportError = error }
            }
        }

        guard !items.isEmpty else {
            if let firstImportError { mediaError = firstImportError.localizedDescription }
            return
        }
        apply(AppendMainLaneMediaCommand(items: items, insertAfterLayerId: selectedMainLaneClip?.id))
        engine.refreshFrames()
        selectedAudioClipId = nil
        selectedLayerId = items.first?.layerId
        engine.beginScrub()
        engine.scrub(toMs: insertionTime)
        engine.endScrub(velocityMsPerSecond: 0)
        if firstImportError != nil { mediaError = "Some items couldn't be added. The other selected items were added." }
    }

    // MARK: Extract audio

    /// Audio > Extract: the picked video's sound goes to the audio lane at the playhead, as long as the video (one undo step). The video
    /// is read straight from the library (no copy); its audio is exported once to `extracted-<library id>.m4a` and reused.
    private func extractAudio(from picked: PickedMedia) async {
        extractingAudio = true
        defer { extractingAudio = false }
        guard let source = await PhotoLibrary().avAsset(for: picked.asset) else {
            mediaError = "Couldn't read that video"
            return
        }
        do {
            let key = picked.asset.localIdentifier.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
            let asset = try await MediaImportService.extractAudio(from: source, cacheKey: key)
            apply(AddAudioClipCommand(asset: asset, durationMs: asset.duration, atMs: currentTimeMs))
        } catch {
            mediaError = error.localizedDescription
        }
    }

    // MARK: Volume

    /// The popup works live: every tick of a slider writes the clip's `gainDb` or fades (no history entry); the project as it was before the first tick
    /// is the one undo step - volume and fade together - recorded when the popup closes.
    @ViewBuilder private func volumeSheet(_ request: VolumeSheet.Request) -> some View {
        if selectedAudioClipId == nil, let layer = selectedLayer, case .video(let payload) = layer.payload {
            // A video clip's own sound: Volume only.
            VolumeSheet(gainDb: payload.audio?.gainDb ?? 0) { gainDb in
                if volumeSessionOriginal == nil { volumeSessionOriginal = project }
                setProject(SetVideoClipVolumeCommand(layerId: layer.id, gainDb: gainDb).apply(to: project))
            }
        } else if let id = selectedAudioClipId, let clip = project.audio.tracks.flatMap(\.clips).first(where: { $0.id == id }) {
            VolumeSheet(
                gainDb: clip.gainDb ?? 0, fadeInMs: clip.fadeIn?.duration ?? 0, fadeOutMs: clip.fadeOut?.duration ?? 0,
                clipDurationMs: clip.timing.duration, tab: request.tab,
                onGain: { gainDb in
                    if volumeSessionOriginal == nil { volumeSessionOriginal = project }
                    setProject(SetAudioClipVolumeCommand(clipId: id, gainDb: gainDb).apply(to: project))
                },
                onFade: { inMs, outMs in
                    if volumeSessionOriginal == nil { volumeSessionOriginal = project }
                    setProject(SetAudioClipFadeCommand(clipId: id, fadeInMs: inMs, fadeOutMs: outMs).apply(to: project))
                }
            )
        }
    }

    private func finishVolumeSession() {
        guard let original = volumeSessionOriginal else { return }
        defer { volumeSessionOriginal = nil }
        func summary(_ project: V2Project) -> [[Double]] {
            let clips = project.audio.tracks.flatMap(\.clips).map { [$0.gainDb ?? 0, $0.fadeIn?.duration ?? 0, $0.fadeOut?.duration ?? 0] }
            let videos = project.layers.compactMap { layer -> [Double]? in
                if case .video(let payload) = layer.payload { return [payload.audio?.gainDb ?? 0] }
                return nil
            }
            return clips + videos
        }
        if summary(original) != summary(project) { recordHistory(current: original) }
    }

    // MARK: Mask

    /// The selected clip's mask as the tool edits it (read back out of `project.masks`; none when it has none).
    private var currentMaskDraft: MaskDraft {
        guard let layer = selectedLayer else { return MaskDraft() }
        return MaskDraft(layer: layer, masks: project.masks ?? [])
    }

    /// What the stage handles and the popup edit: reads the clip's mask, and every change writes it back live (no history entry; the session is one undo step).
    private var maskBinding: Binding<MaskDraft> {
        Binding(get: { currentMaskDraft }, set: { setMaskLive($0) })
    }

    private func setMaskLive(_ draft: MaskDraft) {
        guard let id = selectedLayerId, draft != currentMaskDraft else { return }
        if maskSessionOriginal == nil { maskSessionOriginal = project }
        setProject(SetLayerMaskCommand(layerId: id, draft: draft).apply(to: project))
    }

    /// A tap on a shape of the row: the shape the clip already has opens the popup; another one (or None) replaces the mask, one undo step.
    private func pickMaskShape(_ shape: MaskShape) {
        guard let id = selectedLayerId else { return }
        let current = currentMaskDraft
        if shape == current.shape, shape != .none { maskSession = MaskSession(); return }
        finishMaskSession()
        apply(SetLayerMaskCommand(layerId: id, draft: shape == .none ? MaskDraft() : MaskDraft(shape: shape, keeping: current)))
    }

    private func closeMaskTools() {
        finishMaskSession()
        showingMaskTools = false
    }

    /// The edit (handles or popup) is over: what changed since it began is one undo step.
    private func finishMaskSession() {
        guard let original = maskSessionOriginal else { return }
        defer { maskSessionOriginal = nil }
        let sameNames = original.layers.map(\.mask) == project.layers.map(\.mask)
        if !(sameNames && sameMaskGeometry(original, project)) { recordHistory(current: original) }
    }

    private func sameMaskGeometry(_ a: V2Project, _ b: V2Project) -> Bool {
        guard let first = a.masks, let second = b.masks else { return (a.masks == nil) == (b.masks == nil) }
        guard let encodedA = try? JSONEncoder().encode(first), let encodedB = try? JSONEncoder().encode(second) else { return false }
        return encodedA == encodedB
    }


    // MARK: Remove BG

    private var currentRemoveBgDraft: RemoveBackgroundDraft {
        guard let layer = selectedLayer else { return RemoveBackgroundDraft() }
        return RemoveBackgroundDraft(layer: layer, masks: project.masks ?? [])
    }

    private var removeBgBinding: Binding<RemoveBackgroundDraft> {
        Binding(get: { currentRemoveBgDraft }, set: { setRemoveBgLive($0) })
    }

    private func setRemoveBgLive(_ draft: RemoveBackgroundDraft) {
        guard let id = selectedLayerId, draft != currentRemoveBgDraft else { return }
        if maskSessionOriginal == nil { maskSessionOriginal = project }
        setProject(SetLayerSegmentationCommand(layerId: id, draft: draft).apply(to: project))
    }

    /// A tap on a tile of the row: the mode the clip already has opens the popup; another one (or None) replaces the mask, one undo step (Choose subject opens the popup at once - it needs the tap).
    private func pickRemoveBgMode(_ mode: RemoveBackgroundMode) {
        guard let id = selectedLayerId else { return }
        let current = currentRemoveBgDraft
        if mode == current.mode, mode != .none { removeBgSession = RemoveBackgroundSession(); return }
        finishMaskSession()
        var next = current
        next.mode = mode
        apply(SetRemoveBackgroundOptionCommand(layerId: id, draft: mode == .none ? RemoveBackgroundDraft() : next))
        if mode == .point { removeBgSession = RemoveBackgroundSession() }
    }

    private func closeRemoveBgTools() {
        finishMaskSession()
        showingRemoveBgTools = false
    }

    // MARK: Chroma key

    private var currentChromaKeyDraft: ChromaKeyDraft {
        guard let layer = selectedLayer else { return ChromaKeyDraft() }
        return ChromaKeyDraft(layer: layer, filters: project.filters ?? [])
    }

    private var chromaKeyBinding: Binding<ChromaKeyDraft> {
        Binding(get: { chromaKeyDraft }, set: { setChromaKeyLive($0) })
    }

    private func setChromaKeyLive(_ draft: ChromaKeyDraft) {
        guard let id = selectedLayerId, draft != currentChromaKeyDraft else { return }
        if chromaKeySessionOriginal == nil { chromaKeySessionOriginal = project }
        chromaKeyDraft = draft
        setProject(SetChromaKeyCommand(layerId: id, draft: draft).apply(to: project))
    }

    private func finishChromaKeySession() {
        guard let original = chromaKeySessionOriginal else { return }
        chromaKeySessionOriginal = nil
        guard let before = try? JSONEncoder().encode(original), let after = try? JSONEncoder().encode(project), before != after else { return }
        recordHistory(current: original)
    }

    private func openChromaKeySheet() {
        finishMaskSession()
        engine.pause()
        chromaKeyDraft = currentChromaKeyDraft
        showingChromaKeySheet = true
    }

    /// The selected picture's pixels (for the subject picker) and the asset key the cut-out cache uses.
    private var removeBgPicture: (key: String, image: CGImage?) {
        guard let layer = selectedLayer, case .image(let payload)? = layer.payload as V2LayerPayload?, let asset = project.assets.first(where: { $0.id == payload.assetId }) else { return ("", nil) }
        return (asset.uri, BundledImageCache.image(filename: asset.uri)?.cgImage)
    }


    // MARK: Remove BG on video

    /// The layers of video clips that have Remove BG (Auto), with the file and the source stretch each one plays.
    private var removeBgVideoLayers: [(layer: V2Layer, uri: String, from: Double, to: Double)] {
        project.layers.compactMap { layer in
            guard case .video(let payload) = layer.payload, let id = layer.mask, id.hasPrefix("removebg-"), id.hasSuffix("~auto"),
                  case .video(let asset)? = project.assets.first(where: { $0.id == payload.assetId }), let mapping = VideoTimeMapping(layer: layer) else { return nil }
            return (layer, asset.uri, mapping.trimStartMs / 1000, mapping.sourceMs(atTimelineMs: layer.timing.start + layer.timing.duration) / 1000)
        }
    }

    /// Changes whenever a clip needs a different job (a mask on or off, a trim, a replaced file).
    private var removeBgJobsSignature: String {
        removeBgVideoLayers.map { "\($0.layer.id)|\($0.uri)|\($0.from)|\($0.to)" }.joined(separator: ";")
    }

    private func syncRemoveBgJobs() {
        for item in removeBgVideoLayers {
            let mapping = VideoTimeMapping(layer: item.layer)
            let focus = (mapping?.sourceMs(atTimelineMs: currentTimeMs) ?? item.from * 1000) / 1000
            SegmentationJobs.shared.ensure(layerId: item.layer.id, assetURI: item.uri, range: item.from...max(item.to, item.from), focus: focus)
        }
        SegmentationJobs.shared.keepOnly(Set(removeBgVideoLayers.map(\.layer.id)))
    }

    /// The running job to show a card for: the selected clip's, else the first one.
    private var removeBgProgressLayer: (layerId: String, fraction: Double)? {
        let running = SegmentationJobs.shared.running
        guard !running.isEmpty else { return nil }
        let id = selectedLayerId.flatMap { running[$0] != nil ? $0 : nil } ?? running.keys.sorted()[0]
        return running[id].map { (id, $0.fraction) }
    }

    /// Cancel on the card: Remove BG comes off that clip (one undo step); the frames done stay in the cache.
    private func cancelRemoveBg(layerId: String) {
        SegmentationJobs.shared.cancel(layerId)
        apply(SetLayerSegmentationCommand(layerId: layerId, draft: RemoveBackgroundDraft()))
    }

    // MARK: Crop



    /// Opens the sheet on the selected picture or video clip: the frame starts where the clip's crop is (the whole picture when it has none).
    private func openCropSheet() {
        guard let layer = selectedLayer, layer.type == "video" || layer.type == "image" else { return }
        cropLayerId = layer.id
        cropDraft = CropDraft(crop: layer.crop)
        cropStill = nil
        cropSession = CropSession(video: cropVideo(for: layer))
        let snapshot = project
        let atMs = currentTimeMs
        Task { cropStill = await CropStill.image(for: layer, project: snapshot, atMs: atMs) }
    }

    /// The selected video clip as the popup plays it: its file, the stretch of footage the clip shows, its length.
    private func cropVideo(for layer: V2Layer) -> CropVideo? {
        guard case .video(let payload) = layer.payload,
              case .video(let asset)? = project.assets.first(where: { $0.id == payload.assetId }), let url = bundledURL(filename: asset.uri),
              let mapping = VideoTimeMapping(layer: layer)
        else { return nil }
        let start = layer.timing.start, duration = layer.timing.duration
        return CropVideo(
            url: url,
            startSourceMs: mapping.sourceMs(atTimelineMs: start), endSourceMs: mapping.sourceMs(atTimelineMs: start + duration),
            durationMs: duration, pictureAspect: asset.width / max(asset.height, 1),
            initialFraction: duration > 0 ? min(max((currentTimeMs - start) / duration, 0), 1) : 0
        )
    }

    /// The sheet closed (Done or swiped away): the frame is stored on the clip, one undo step; nothing changed = nothing recorded.
    private func finishCropSession() {
        defer { cropLayerId = nil; cropStill = nil }
        guard let id = cropLayerId, let layer = project.layers.first(where: { $0.id == id }) else { return }
        let next: V2Crop? = cropDraft.v2.isIdentity ? nil : cropDraft.v2
        guard next != layer.crop else { return }
        apply(SetClipCropCommand(layerId: id, crop: next))
    }

    // MARK: Speed

    private func openSpeedSheet() {
        guard let layer = selectedLayer, layer.type == "video" else { return }
        speedSessionOriginal = nil   // taken at the first change: that is the undo step
        showingSpeedSheet = true
    }

    /// The command works from the clip as it is now (the footage it plays is constant, only the rate changes), so every ruler tick can be
    /// applied to the current project; the project as it was before the first change is what Undo goes back to.
    @ViewBuilder private var speedSheet: some View {
        if let id = selectedLayerId, let layer = project.layers.first(where: { $0.id == id }) {
            let rate = VideoTimeMapping(layer: layer)?.rate ?? 1
            let span = sourceSpanMs(of: layer) ?? layer.timing.duration
            let mapping = VideoTimeMapping(layer: layer)
            let curvePoints: [V2SpeedPoint]? = { if case .video(let payload) = layer.payload { return payload.speedCurve } else { return nil } }()
            // Where the playhead is in the footage the clip plays, as a fraction of it.
            let playhead: Double? = mapping.flatMap { m in
                currentTimeMs >= layer.timing.start && currentTimeMs <= layer.timing.start + layer.timing.duration && span > 0
                    ? (m.sourceMs(atTimelineMs: currentTimeMs) - m.trimStartMs) / span : nil
            }
            SpeedSheet(
                rate: rate, curve: curvePoints, sourceSpanMs: span, fps: project.composition.fps, playheadFraction: playhead,
                onSeek: { fraction in
                    // The black line on the graph is a scrubber over the clip's footage.
                    guard let mapping else { return }
                    engine.beginScrub()
                    engine.scrub(toMs: mapping.timelineMs(atSourceMs: mapping.trimStartMs + fraction * span))
                },
                onSeekEnd: { engine.endScrub(velocityMsPerSecond: 0) },
                onRate: { newRate in
                    if speedSessionOriginal == nil { speedSessionOriginal = project }
                    setProject(SetClipSpeedCommand(layerId: id, rate: newRate).apply(to: project))
                },
                onCurve: { points in
                    if speedSessionOriginal == nil { speedSessionOriginal = project }
                    setProject(SetClipSpeedCurveCommand(layerId: id, points: points).apply(to: project))
                }
            )
        }
    }

    /// The whole session is one undo step - and only when something changed.
    private func finishSpeedSession() {
        guard let original = speedSessionOriginal else { return }
        defer { speedSessionOriginal = nil }
        let changed = zip(original.layers, project.layers).contains { $0.timing.duration != $1.timing.duration || $0.timing.start != $1.timing.start }
        if changed { recordHistory(current: original) }
    }

    // MARK: Animation

    @ViewBuilder private var animationSheet: some View {
        if let id = selectedLayerId, let layer = project.layers.first(where: { $0.id == id }) {
            AnimationSheet(
                initial: AnimationWrappers.applied(for: id, in: project.layers),
                clipDurationMs: layer.timing.duration,
                onPick: { slot, presetId, durationMs in
                    apply(SetAnimationCommand(layerId: id, slot: slot, presetId: presetId, durationMs: durationMs))
                    if presetId != nil { previewAnimation(of: id, slot: slot, durationMs: durationMs) }
                }
            )
        }
    }

    /// Plays the picked animation on the stage: an entrance from the clip's start, an exit just before its end, a combo from the start.
    private func previewAnimation(of id: String, slot: AnimationSlot, durationMs: Double) {
        guard let layer = project.layers.first(where: { $0.id == id }) else { return }
        let start = layer.timing.start, end = layer.timing.start + layer.timing.duration
        let from: Double, length: Double
        switch slot {
        case .in: from = max(start - 200, 0); length = durationMs + 600
        case .out: from = max(end - durationMs - 400, start); length = durationMs + 800
        case .combo: from = start; length = min(layer.timing.duration, 3000)
        }
        engine.pause()
        engine.glide(toMs: from, duration: 0.1) {
            engine.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + length / 1000) { if engine.isPlaying { engine.pause() } }
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
        recordHistory(current: original)
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
        recordHistory(current: original)
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
#if DEBUG
        .overlay(alignment: .top) { PlaybackMetricsHUD().padding(.top, 52) }
#endif
        .overlay {
            if exportGate.showsProgress {
                ExportProgressOverlay(progress: exportGate.progress, title: exportGate.progressTitle,
                                      isComplete: exportGate.completed)
            }
        }
        // Ignore `0` — a transient artifact during the cover's presentation
        // animation, not a real measurement (see ui-design-note.md).
        .onPreferenceChange(TitlebarHeightKey.self) { newValue in
            guard newValue > 0 else { return }
            titlebarHeight = newValue
        }
        .task { engine.prepare() }
        #if DEBUG
        // UI-test hook: `EDITOR_SELECT=<layer id>` selects that clip at launch and puts the playhead on it.
        .task {
            if let id = ProcessInfo.processInfo.environment["EDITOR_SELECT"], let layer = project.layers.first(where: { $0.id == id }) {
                selectedLayerId = id
                engine.beginScrub()   // onto the clip, so it shows on the stage
                engine.scrub(toMs: layer.timing.start + 300)
                engine.endScrub(velocityMsPerSecond: 0)
                // Measurement runs (`PLAYBACK_PIPELINE.md` section 9): `EDITOR_AUTO_REMOVEBG=1` puts Auto on that clip, `EDITOR_AUTOPLAY_AFTER=<s>` plays it for `EDITOR_AUTOPLAY_FOR` s (default 10).
                let environment = ProcessInfo.processInfo.environment
                if environment["EDITOR_AUTO_REMOVEBG"] != nil {
                    var draft = RemoveBackgroundDraft(); draft.mode = .auto
                    apply(SetLayerSegmentationCommand(layerId: id, draft: draft))
                }
                if let after = Double(environment["EDITOR_AUTOPLAY_AFTER"] ?? "") {
                    try? await Task.sleep(for: .seconds(after))
                    engine.togglePlay()
                    try? await Task.sleep(for: .seconds(Double(environment["EDITOR_AUTOPLAY_FOR"] ?? "") ?? 10))
                    if engine.isPlaying { engine.togglePlay() }
                }
            }
        }
        #endif
        #if DEBUG
        // UI-test hook: the first video clip is replaced by one of the project's photos at launch (the main lane then has no video).
        .task {
            guard ProcessInfo.processInfo.environment["EDITOR_REPLACE_MAIN_WITH_PHOTO"] != nil,
                  let photo = project.assets.first(where: { if case .image = $0 { return true } else { return false } }),
                  let main = project.layers.first(where: { $0.type == "video" }) else { return }
            apply(ReplaceClipCommand(layerId: main.id, asset: photo))
        }
        #endif
        .alert(item: $exportGate.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingAdjustSheet) { adjustSheet }
        .sheet(isPresented: $showingCoverEditor) {
            CoverEditorSheet(project: project, initialCover: coverImageOverride) { coverImageOverride = $0 }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(18)
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showingFilterSheet) { filterSheet }
        .sheet(isPresented: $showingAnimationSheet) { animationSheet }
        .sheet(item: $transitionPickerTarget) { target in
            TransitionSheet(
                initialKind: target.kind,
                initialDurationMs: target.durationMs,
                onPick: { kind, duration in
                    apply(SetTransitionCommand(outgoingId: target.outgoingId, incomingId: target.incomingId,
                                               kind: kind ?? .mix, durationMs: kind == nil ? nil : duration))
                }
            )
        }
        .sheet(isPresented: $showingSpeedSheet, onDismiss: finishSpeedSession) { speedSheet }
        .sheet(item: $maskSession, onDismiss: finishMaskSession) { _ in MaskSheet(draft: maskBinding) }
        .task(id: removeBgJobsSignature) { syncRemoveBgJobs() }
        .sheet(item: $removeBgSession, onDismiss: finishMaskSession) { _ in RemoveBackgroundSheet(draft: removeBgBinding, source: removeBgPicture.image, sourceKey: removeBgPicture.key) }
        .sheet(isPresented: $showingChromaKeySheet, onDismiss: finishChromaKeySession) { ChromaKeySheet(draft: chromaKeyBinding) }
        .sheet(item: $cropSession, onDismiss: finishCropSession) { session in CropSheet(draft: $cropDraft, image: cropStill, video: session.video) }
        .sheet(item: $volumeRequest, onDismiss: finishVolumeSession) { request in volumeSheet(request) }
        .sheet(item: $mediaPicker) { purpose in
            EditorMediaPickerView(purpose: purpose, onPick: { picked in
                mediaPicker = nil
                Task {
                    if purpose.mode == .extractAudio { await extractAudio(from: picked) } else { await usePickedMedia(picked, for: purpose) }
                }
            }, onAppend: { picked in
                mediaPicker = nil
                Task { await appendPickedMediaToMainLane(picked) }
            }, onCancel: {
                mediaPicker = nil
                mainLaneInsertAfterLayerId = nil
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.light)
        }
        .alert("Couldn't add that", isPresented: Binding(get: { mediaError != nil }, set: { if !$0 { mediaError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(mediaError ?? "") }
        .sheet(isPresented: $showingStickerSheet) { stickerSheet }
        .sheet(isPresented: $showingSoundSheet) { SoundSheet(store: soundStore, onUse: addSoundEffect) }
        .sheet(isPresented: $showingRecorderSheet) { RecorderSheet(onAdd: { addRecording(from: $0) }) }
        .sheet(isPresented: $showingTextSheet, onDismiss: finishTextSession) { TextSheet(values: $textValues, composition: project.composition, selectAllOnFirstFocus: textSessionIsNew, initialTab: textSessionTab) }
        .sheet(isPresented: $showingGraphSheet) {
            if let id = selectedLayerId, let layer = selectedLayer, let start = graphSegmentStart {
                GraphSheet(easing: LabEasing(v2: TransformKeyframes.easing(of: layer, segmentStart: start))) {
                    apply(SetKeyframeEasingCommand(layerId: id, segmentStartMs: start, easing: $0.v2))
                }
            }
        }
        .sheet(isPresented: $showingTransformSheet) { transformSheet }
        .onChange(of: transformValues) { _, new in updateTransform(new) }
        .onChange(of: textValues) { _, new in updateText(new) }
        // Scrubbing with the Transform sheet open on a keyframed layer: show the values at the new playhead (no write).
        .onChange(of: currentTimeMs) { _, time in
            guard showingTransformSheet, let layer = selectedLayer, TransformKeyframes.isKeyframed(layer) else { return }
            let sampled = TransformValues(layer: layer, atMs: time)
            guard sampled != transformValues else { return }
            transformSynced = sampled
            transformValues = sampled
        }
        .task(id: selectedLayerId) { await probeSelectedAudio() }
        .onChange(of: selectedLayerId) { _, _ in if showingMaskTools { closeMaskTools() }; if showingRemoveBgTools { closeRemoveBgTools() } }
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
        .overlay {
            if extractingAudio {
                ProgressView("Extracting audio…")
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("extractingAudio")
            }
        }
        .overlay {
            if importingMainLaneMedia {
                ProgressView("Adding clips…")
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("addingMainLaneMedia")
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
        case .maskTools:
            HStack(spacing: 0) {
                BottomBarBackButton { closeMaskTools() }
                    .padding(.trailing, 8)
                Divider().frame(height: 28)
                    .padding(.trailing, 4)
                MaskToolRow(current: currentMaskDraft.shape, onPick: pickMaskShape)
            }
            .padding(.horizontal, 12)

        case .removeBgTools:
            HStack(spacing: 0) {
                BottomBarBackButton { closeRemoveBgTools() }
                    .padding(.trailing, 8)
                Divider().frame(height: 28)
                    .padding(.trailing, 4)
                RemoveBackgroundToolRow(current: currentRemoveBgDraft.mode, modes: selectedLayer?.type == "video" ? [.none, .auto] : RemoveBackgroundMode.allCases, onPick: pickRemoveBgMode, chromaKeyEnabled: currentChromaKeyDraft.enabled, onChromaKey: openChromaKeySheet)
            }
            .padding(.horizontal, 12)
        case .toolPanel(let tool):
            // Same frame as the Edit row: back button, divider, then the tool's items from the left.
            HStack(spacing: 0) {
                BottomBarBackButton { selectedTool = nil }
                    .padding(.trailing, 8)
                Divider().frame(height: 28)
                    .padding(.trailing, 4)
                optionsPanel(for: tool)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
        }
    }

    /// One entry for every button of the selection row. Built tools do their job; the others only say they are coming
    /// (the UI exists first, each tool gets built one by one).
    private func handleClipTool(_ tool: ClipTool) {
        switch tool {
        case .split:
            if let audioId = selectedAudioClipId {
                apply(SplitAudioClipCommand(clipId: audioId, atMs: currentTimeMs))
                selectedAudioClipId = nil
                return
            }
            guard let id = selectedLayerId else { return }
            let secondLayerId = "\(id)-split-\(UUID().uuidString.prefix(8))"
            apply(SplitClipCommand(layerId: id, atMs: currentTimeMs, secondLayerId: secondLayerId))
            if project.layers.contains(where: { $0.id == secondLayerId }) {
                selectedLayerId = secondLayerId
                selectedAudioClipId = nil
            }
        case .transform: openTransformSheet()
        case .graph: if graphSegmentStart != nil { showingGraphSheet = true }
        case .opacity: openTransformSheet(focus: .opacity)
        case .adjust: showingAdjustSheet = true
        case .filter: showingFilterSheet = true
        case .animation: if selectedLayerId != nil { showingAnimationSheet = true }
        case .speed: openSpeedSheet()
        case .mask: if selectedLayer?.type == "video" || selectedLayer?.type == "image" { showingMaskTools = true }
        case .removeBackground: if selectedLayer?.type == "image" || selectedLayer?.type == "video" { showingRemoveBgTools = true }
        case .crop: openCropSheet()
        case .editText: openTextSheet(new: false)
        case .mirror:
            guard let id = selectedLayerId else { return }
            apply(MirrorLayerCommand(layerId: id))
        case .duplicate:
            guard let id = selectedLayerId else { return }
            let copyId = "\(id)-copy-\(UUID().uuidString.prefix(6).lowercased())"
            apply(DuplicateClipCommand(layerId: id, newLayerId: copyId))
            if project.layers.contains(where: { $0.id == copyId }) { selectedLayerId = copyId }
            engine.refreshFrames()
        case .style: openTextSheet(new: false, tab: .style)
        case .replace:
            guard let layer = selectedLayer else { return }
            mediaPicker = MediaPickerPurpose(layerId: layer.id, minVideoMs: layer.type == "video" ? (sourceSpanMs(of: layer) ?? layer.timing.duration) : 0)
        case .overlay:
            // The selected clip becomes a picture-in-picture layer too (a copy, half the size, in the middle).
            guard let id = selectedLayerId else { return }
            let copyId = "\(overlayLayerIdPrefix)\(UUID().uuidString.prefix(8).lowercased())"
            apply(CopyToOverlayCommand(layerId: id, newLayerId: copyId))
            if project.layers.contains(where: { $0.id == copyId }) { selectedLayerId = copyId }
            engine.refreshFrames()
        case .volume, .fade:
            if selectedAudioClipId != nil || (tool == .volume && selectedLayer?.type == "video") {
                volumeSessionOriginal = nil   // taken at the first change
                volumeRequest = VolumeSheet.Request(tab: tool == .fade ? .fade : .volume)
            } else {
                comingSoonTitle = tool.title
            }
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
        #if DEBUG
        // UI tests: the sample videos have no sound track; this lets the Volume popup be opened on one.
        if ProcessInfo.processInfo.environment["EDITOR_VIDEO_HAS_SOUND"] != nil { selectedHasAudio = true; return }
        #endif
        guard let layer = selectedLayer, case .video(let payload) = layer.payload,
              case .video(let asset)? = project.assets.first(where: { $0.id == payload.assetId }),
              let url = bundledURL(filename: asset.uri)
        else { selectedHasAudio = false; return }
        let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        selectedHasAudio = !(tracks ?? []).isEmpty
    }

    /// Split only makes sense strictly inside the clip's own range - at either edge it would leave a zero-length half.
    private var canSplitSelection: Bool {
        if let clip = project.audio.tracks.flatMap(\.clips).first(where: { $0.id == selectedAudioClipId }) {
            return currentTimeMs > clip.timing.start && currentTimeMs < clip.timing.start + clip.timing.duration
        }
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
            onSetAspectRatio: { width, height in apply(SetAspectRatioCommand(width: width, height: height)) },
            onSetBackgroundColor: { hex in apply(SetBackgroundColorCommand(hex: hex)) },
            onPickAudioFile: { url in addAudio(from: url) },
            onRecord: { showingRecorderSheet = true },
            onAddSoundEffect: { preset in
                apply(AddAudioClipCommand(asset: SoundEffectCatalog.asset(for: preset), durationMs: preset.durationMs, atMs: currentTimeMs))
            },
            onAddText: { openTextSheet(new: true) },
            onComingSoon: { title in comingSoonTitle = title },
            onExtractAudio: { mediaPicker = .extractAudio },
            onSoundFX: { showingSoundSheet = true }
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
                        layers: engine.previewLayers,
                        filters: project.filters ?? [],
                        masks: project.masks ?? [],
                        engine: engine
                    )
                    .frame(width: videoBoxSide, height: videoBoxSide)
                    .overlay {
                        // Mask tool: the picked mask's outline and handles sit on the live stage.
                        if showingMaskTools, let layer = selectedLayer, currentMaskDraft.shape != .none {
                            MaskGestureOverlay(
                                draft: maskBinding, composition: project.composition, layerFrame: layer.frame,
                                transform: TransformValues(layer: layer, atMs: currentTimeMs), onBegin: {}, onEnd: {}
                            )
                        }
                    }
                    .overlay {
                        // Remove BG on video: the progress ring + Cancel while the frames are being cut.
                        if let progress = removeBgProgressLayer {
                            RemoveBackgroundProgressCard(fraction: progress.fraction, onCancel: { cancelRemoveBg(layerId: progress.layerId) })
                        }
                    }
                    .overlay {
                        // While the Transform sheet is open the stage can be dragged, pinched and twisted directly.
                        if showingTransformSheet, let layer = selectedLayer {
                            TransformGestureOverlay(
                                values: $transformValues, composition: project.composition, layerFrame: layer.frame,
                                onBegin: beginTransform, onEnd: endTransform
                            )
                        }
                    }
                    .overlay {
                        if showingChromaKeySheet, let layer = selectedLayer, layer.type == "video" || layer.type == "image" {
                            ChromaKeyPickerOverlay(
                                layer: layer, project: project, composition: project.composition,
                                atMs: currentTimeMs,
                                onSample: { color in
                                    var next = currentChromaKeyDraft
                                    next.keyColor = color
                                    next.enabled = true
                                    setChromaKeyLive(next)
                                }
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
                        transitionIntents: transitionIntents,
                        engine: engine,
                        coverImageOverride: coverImageOverride,
                        onEditCover: { showingCoverEditor = true },
                        selectedLayerId: timelineSelection($selectedLayerId),
                        selectedAudioClipId: timelineSelection($selectedAudioClipId),
                        onTrimBegin: beginTrim,
                        onTrimUpdate: updateTrim,
                        onTrimEnd: endTrim,
                        fps: project.composition.fps,
                        keyframeTimes: selectedLayer.map(TransformKeyframes.visibleTimelineTimes) ?? [],
                        onMoveClip: apply,
                        onTransition: { outgoingId, incomingId in
                            let existing = transitionIntents.first { $0.incomingId == incomingId && $0.outgoingId == outgoingId }
                            transitionPickerTarget = TransitionPickerTarget(
                                outgoingId: outgoingId,
                                incomingId: incomingId,
                                kind: existing?.kind,
                                durationMs: existing?.durationMs ?? TransitionWrappers.defaultDurationMs
                            )
                        },
                        onAddMainLaneMedia: {
                            let order = primaryVideoLaneOrder(of: project.layers)
                            mainLaneInsertAfterLayerId = selectedLayerId.flatMap { selectedId in
                                project.layers.first { $0.id == selectedId && $0.order == order && isPushLane($0) }?.id
                            }
                            mediaPicker = .appendMainLane
                        }
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
                    layers: engine.previewLayers,
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
            exportQualityButton
            exportButton
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom)
        .background(Color(.systemBackground))
    }

    private var exportQualityButton: some View {
        Button { showingExportQuality = true } label: {
            HStack(spacing: 5) {
                Text(exportResolution.buttonTitle)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .regular))
            }
            .frame(width: topBarButtonSize.width, height: topBarButtonSize.height)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quality, \(exportResolution.title)")
        .accessibilityIdentifier("exportQualityButton")
        .popover(isPresented: $showingExportQuality, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ExportQualityPopover(
                selection: exportResolution,
                frameRate: exportFrameRate,
                bitrateMbps: exportBitrateMbps,
                onResolutionChange: { exportResolution = $0 },
                onFrameRateChange: { exportFrameRate = $0 },
                onBitrateChange: { exportBitrateMbps = $0 }
            )
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.light)
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button { dismiss() } label: {
            Text("Cancel")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: topBarButtonSize.width, height: topBarButtonSize.height)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    /// Charges first (template projects), shows a spinner meanwhile, and only then renders.
    private var exportButton: some View {
        Button(action: startExport) {
            exportLabel
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(width: topBarButtonSize.width, height: topBarButtonSize.height)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(exportGate.isWorking)
        .accessibilityIdentifier("exportButton")
    }

    @ViewBuilder
    private var exportLabel: some View {
        if exportGate.isWorking { ProgressView().tint(.black) } else { Text("Export") }
    }

    private func startExport() {
        Task {
            let renderProject = TransitionWrappers.compiling(transitionIntents, into: project)
            await exportGate.export(project: renderProject, context: exportContext,
                                    settings: ExportSettings(resolution: exportResolution,
                                                            frameRate: exportFrameRate,
                                                            bitrateMbps: exportBitrateMbps))
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
                .accessibilityIdentifier("playback-toggle")
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
        return min(max(engine.editorTimeMs / engine.maxDurationMs, 0), 1)
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
        .accessibilityValue(String(format: "%.0f", engine.editorTimeMs))
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
        scrubStartMs = engine.editorTimeMs
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

/// Wraps `PreviewCanvas`, reading the render-time clock and `engine.mode`
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
    var masks: [V2Mask] = []
    let engine: EditorPlaybackEngine

    var body: some View {
        PreviewCanvas(
            composition: composition,
            assets: assets,
            layers: layers,
            filters: filters,
            masks: masks,
            atMs: engine.currentTimeMs,
            transitionFramePlan: engine.transitionFramePlan,
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
