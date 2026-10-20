import Foundation

/// A named, discrete edit to the project — CLAUDE.md's "Command pattern,
/// not JSON Patch or CRDT" rule. `apply(to:)` builds a *new* `V2Project`:
/// every one of `V2Project`'s own stored properties is `let`
/// (`Protocol/V2Types.swift`), so in-place mutation isn't possible, only
/// reconstruction via its own memberwise init. Undo is handled separately
/// by `EditorHistory`'s whole-document snapshot — a command itself never
/// needs to know how to reverse what it did.
protocol EditorCommand {
    func apply(to project: V2Project) -> V2Project
}

/// Tỷ lệ khung hình — changes only `composition.width`/`height`. Layer
/// `frame`/`transform` values are left completely untouched — confirmed
/// with the user: this behaves like a crop, not a reflow. Existing layers
/// keep their authored absolute coordinates, which may now sit outside
/// the new canvas bounds, the same way cropping a photo can hide part of
/// what was already there — no automatic re-anchoring.
struct SetAspectRatioCommand: EditorCommand {
    let width: Double
    let height: Double

    func apply(to project: V2Project) -> V2Project {
        let composition = V2Composition(
            width: width, height: height, fps: project.composition.fps,
            background: project.composition.background,
            colorSpace: project.composition.colorSpace, view: project.composition.view
        )
        return project.withComposition(composition)
    }
}

/// Phông nền — changes only `composition.background` (a hex color string,
/// already rendered by `PreviewCanvas` — see CLAUDE.md's nav-tools note).
struct SetBackgroundColorCommand: EditorCommand {
    let hex: String

    func apply(to project: V2Project) -> V2Project {
        let composition = V2Composition(
            width: project.composition.width, height: project.composition.height, fps: project.composition.fps,
            background: hex, colorSpace: project.composition.colorSpace, view: project.composition.view
        )
        return project.withComposition(composition)
    }
}

/// Chỉnh sửa — splits one layer into two at `atMs`, the current playhead
/// position (matching CapCut: position the playhead where you want to
/// cut, then tap split). A no-op (returns `project` unchanged) if `atMs`
/// isn't strictly inside the clip's own time range, or the layer isn't
/// found — a command silently doing nothing on an invalid request matches
/// this app's established "no ported validator, fail closed/no-op, not a
/// crash" convention (see CLAUDE.md's "Valid by construction" rule) rather
/// than needing its own error-reporting path for what the UI should
/// already prevent (the panel only enables Split when the playhead is
/// actually inside the selected clip).
struct SplitClipCommand: EditorCommand {
    let layerId: String
    let atMs: Double
    /// Supplying the second half's id lets the editor select it after the split; nil keeps command-only callers self-contained.
    var secondLayerId: String? = nil

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let original = layers[index]
        guard atMs > original.timing.start, atMs < original.timing.start + original.timing.duration else { return project }

        let firstDuration = atMs - original.timing.start
        let secondDuration = original.timing.duration - firstDuration

        var first = original
        var second = original
        // A clip with a speed curve is cut where the *source* is at the cut; each half keeps its own piece of the curve.
        var curveCut: Double?
        if case .video(let payload) = original.payload, let points = payload.speedCurve, let last = points.last,
           let curve = SpeedCurve(points: points, span: last.sourceMs), let halves = curve.splitting(atSource: curve.sourceMs(atOutput: firstDuration)) {
            let cut = curve.sourceMs(atOutput: firstDuration)
            curveCut = cut   // the durations stay exactly what the timeline says; each curve's own length matches them to within a table cell
            if case .video(var a) = first.payload { a.speedCurve = halves.first.points; first.payload = .video(a) }
            if case .video(var b) = second.payload { b.speedCurve = halves.second.points; second.payload = .video(b) }
        }
        first.timing = V2Timing(start: original.timing.start, duration: firstDuration)
        second.id = secondLayerId ?? "\(original.id)-split-\(UUID().uuidString.prefix(8))"
        second.timing = V2Timing(start: original.timing.start + firstDuration, duration: secondDuration)
        // A video clip's second half must keep playing from where the
        // first half left off in the *source* file, not restart from the
        // original's own trim point — shift `trimStart` forward by exactly
        // the first half's duration.
        if case .video(var payload) = second.payload {
            // The first half covers `firstDuration x rate` ms of the source (rate 1 unless Speed changed it).
            payload.trimStart = (payload.trimStart ?? 0) + (curveCut ?? firstDuration * (payload.playbackRate ?? 1))
            second.payload = .video(payload)
        }

        // Keyframes: each half only keeps its own (the second one re-timed to its own start).
        let halves = TransformKeyframes.splitting(original, at: firstDuration)
        first.tracks = halves.first.tracks
        second.tracks = halves.second.tracks

        // Animations: In stays on the first half, Out goes to the second, a Combo plays on both. The copy must not stay nested in
        // the first half's wrappers.
        let animations = AnimationWrappers.applied(for: original.id, in: layers)
        second.parentLayerId = AnimationWrappers.baseParent(of: original, in: layers)
        layers[index] = first
        layers.insert(second, at: index + 1)
        var result = project.withLayers(layers)
        if !animations.isEmpty {
            result = AnimationWrappers.rebuilt(result, clipId: first.id, animations: animations.values.filter { $0.slot != .out })
            result = AnimationWrappers.rebuilt(result, clipId: second.id, animations: animations.values.filter { $0.slot != .in })
        }
        return result
    }
}

/// Chỉnh sửa — drag-to-trim via the Timeline's own left/right handles. Both
/// handles reuse this one command: `TimelineView`'s drag gesture computes
/// the new `timing`/`trimStart`/`trimEnd` (including clamping an *extend*
/// drag against the clip's real asset duration via `AssetDurationCache`,
/// confirmed with the user as the correct CapCut-matching behavior rather
/// than a shrink-only first pass) and this command just writes the result —
/// no clamping/validation here, matching this app's "no ported validator"
/// convention (the UI is responsible for only ever proposing values that
/// are already valid).
///
/// **`siblingStarts`** (added 2026-10-08, the "ripple reflow" feature): on
/// a push-lane (video/image — a main-track lane, which must never show a
/// gap, confirmed with the user), trimming one clip repositions *other*
/// clips in the same lane too — every clip after the dragged one glues to
/// whichever clip now precedes it, cascading down the whole lane in both
/// directions (not just the immediate neighbor), with each sibling's own
/// `timing.duration` left untouched — only its `timing.start` moves. This
/// dict is `TimelineView`'s own `reflowLane(...)` output; `[:]` for a
/// stop-lane trim (text etc., where a drag hard-clamps against the
/// neighbor's edge instead of pushing it, so nothing else ever needs to
/// move).
struct TrimClipCommand: EditorCommand {
    let layerId: String
    let start: Double
    let duration: Double
    let trimStart: Double?
    let trimEnd: Double?
    var siblingStarts: [String: Double] = [:]

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        var layer = layers[index]
        // A left trim (the end stays, the head moves): keyframes stay with the picture, so their local times move the other way.
        let oldEnd = layer.timing.start + layer.timing.duration
        if abs(oldEnd - (start + duration)) < 0.5 { layer = TransformKeyframes.shifting(layer, by: start - layer.timing.start) }
        layer.timing = V2Timing(start: start, duration: duration)
        if case .video(var payload) = layer.payload {
            payload.trimStart = trimStart
            payload.trimEnd = trimEnd
            // A clip with a speed curve loses/gains the matching piece of it at each edge: how far each edge moved in timeline ms says how
            // much source went with it, and the clip's own trim values follow from that.
            if let oldMapping = VideoTimeMapping(layer: layers[index]), oldMapping.curve != nil, let curve = oldMapping.curve {
                let head = oldMapping.headSource(forTimeline: start - layers[index].timing.start)
                let tail = oldMapping.tailSource(forTimeline: (start + duration) - oldEnd)
                if let trimmed = curve.trimmed(headSource: head, tailSource: tail) {
                    payload.speedCurve = trimmed.points
                    payload.trimStart = max(oldMapping.trimStartMs + head, 0)
                    payload.trimEnd = (payload.trimStart ?? 0) + trimmed.span
                }
            }
            layer.payload = .video(payload)
        }
        layers[index] = layer

        for (siblingId, newStart) in siblingStarts {
            guard let siblingIndex = layers.firstIndex(where: { $0.id == siblingId }) else { continue }
            var sibling = layers[siblingIndex]
            sibling.timing = V2Timing(start: newStart, duration: sibling.timing.duration)
            layers[siblingIndex] = sibling
        }
        return project.withLayers(layers)
    }
}

/// Chỉnh sửa — removes one layer entirely. No confirmation step here (the
/// UI layer's job, not the command's); undo already covers "I didn't mean
/// to delete that."
struct DeleteClipCommand: EditorCommand {
    let layerId: String

    func apply(to project: V2Project) -> V2Project {
        let mainOrder = primaryVideoLaneOrder(of: project.layers)
        let removed = project.layers.first { $0.id == layerId }
        let remaining = project.withLayers(project.layers.filter { $0.id != layerId })
        // Deleting a clip of the main lane leaves a hole there: close it (main-lane magnet).
        guard let mainOrder, let removed, isPushLane(removed), removed.order == mainOrder else { return remaining }
        return packLane(order: mainOrder, in: remaining)
    }
}

/// The main lane = the lowest `order` that holds a video **or a photo** clip of the main track (the lane pinned under the ruler). Stickers and
/// overlays are free clips and never make a lane the main one; a main lane with only photos (a video replaced by a photo) is still the main lane.
func primaryVideoLaneOrder(of layers: [V2Layer]) -> Int? {
    layers.filter { isPushLane($0) }.map(\.order).min()
}

/// Main-lane magnet (user decision 2026-10-12): the main lane never has a hole - its clips follow each other, the first
/// one at 0, in start order with their own durations. Run after a trim drag ends and after a delete. Text/overlay
/// lanes and audio are not touched (they may have gaps and keep their absolute times). No-op when already packed.
struct PackMainLaneCommand: EditorCommand {
    func apply(to project: V2Project) -> V2Project {
        guard let order = primaryVideoLaneOrder(of: project.layers) else { return project }
        return packLane(order: order, in: project)
    }
}

/// Lays the clips of lane `order` end to end from 0, in start order (ties keep array order). Returns `project`
/// itself when nothing moves.
func packLane(order: Int, in project: V2Project) -> V2Project {
    let clips = project.layers.enumerated()
        .filter { $0.element.order == order && $0.element.type != "group" }
        .sorted { ($0.element.timing.start, $0.offset) < ($1.element.timing.start, $1.offset) }
    var starts: [String: Double] = [:]
    var cursor = 0.0
    for (_, clip) in clips {
        let start = cursor
        starts[clip.id] = start
        cursor = start + clip.timing.duration
    }
    guard project.layers.contains(where: { layer in starts[layer.id].map { $0 != layer.timing.start } ?? false }) else { return project }
    let layers = project.layers.map { layer -> V2Layer in
        guard let start = starts[layer.id], start != layer.timing.start else { return layer }
        var moved = layer
        moved.timing = V2Timing(start: start, duration: layer.timing.duration)
        return moved
    }
    return TransitionWrappers.normalized(project.withLayers(layers))
}

extension V2Project {
    /// Every other field copied as-is — the one piece of boilerplate every
    /// project-level command above needs, factored out once rather than
    /// repeating the full memberwise reconstruction in each command.
    func withComposition(_ composition: V2Composition) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }

    func withLayers(_ layers: [V2Layer]) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }

    func withAssets(_ assets: [V2Asset]) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }

    func withAudio(_ audio: V2AudioDomain) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }

    func withFilters(_ filters: [V2Filter]?) -> V2Project {
        V2Project(
            format: format, formatVersion: formatVersion, id: id,
            composition: composition, assets: assets, markers: markers,
            clipPaths: clipPaths, masks: masks, filters: filters,
            paintServers: paintServers, layers: layers, audio: audio
        )
    }
}

/// Âm thanh — "Thêm nhạc", Hiệu ứng âm thanh (a one-tap sound-effect library
/// is the same action, just a bundled asset instead of a Files-app import —
/// see `SoundEffectCatalog`), *and* Trích xuất (pulling a video clip's own
/// audio out onto the audio lane — see `MediaImportService.extractAudio`):
/// appends `asset` to `project.assets` (skipped if an asset with that `id`
/// is already there — both `SoundEffectCatalog` and extraction mint a
/// stable id, so repeating the action reuses one asset entry instead of
/// appending a duplicate every time), then places a new `V2AudioClip` at
/// `atMs` on whichever existing track doesn't already have a clip
/// overlapping that range, or a brand-new track if every track does (or
/// none exist yet). No drag exists to propose a position this pass, so
/// unlike `TrimClipCommand` the command itself picks one — still no
/// clamping beyond that search, same "no ported validator" spirit.
struct AddAudioClipCommand: EditorCommand {
    let asset: V2AudioAsset
    let durationMs: Double
    let atMs: Double
    /// Trích xuất exports a video asset's *entire* audio track once (cached,
    /// reused across repeat extractions), so the resulting clip needs its
    /// own `trim` to show only the slice matching the video clip's own
    /// `trimStart`/duration — "Thêm nhạc"/Hiệu ứng âm thanh leave these at
    /// their defaults (0 / nil) since those assets are already exactly the
    /// right length.
    var trimStartMs: Double = 0
    var trimEndMs: Double? = nil

    func apply(to project: V2Project) -> V2Project {
        let clip = V2AudioClip(
            id: "audio-\(UUID().uuidString.prefix(8))",
            assetId: asset.id,
            timing: V2AudioClipTiming(start: atMs, duration: durationMs),
            trim: V2AudioClipTrim(start: trimStartMs, end: trimEndMs),
            playbackRate: 1
        )

        var tracks = project.audio.tracks
        let overlaps: (V2AudioTrack) -> Bool = { track in
            track.clips.contains { existing in
                let existingEnd = existing.timing.start + existing.timing.duration
                let newEnd = clip.timing.start + clip.timing.duration
                return clip.timing.start < existingEnd && existing.timing.start < newEnd
            }
        }

        if let index = tracks.firstIndex(where: { !overlaps($0) }) {
            tracks[index].clips.append(clip)
        } else {
            tracks.append(V2AudioTrack(id: "track-\(UUID().uuidString.prefix(8))", gainDb: nil, pan: 0, muted: false, clips: [clip]))
        }

        let assets = project.assets.contains { $0.id == asset.id } ? project.assets : project.assets + [.audio(asset)]
        return project
            .withAssets(assets)
            .withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}

/// Âm thanh — Xoá: removes one `V2AudioClip` by id from whichever track
/// holds it, and the track too when that was its last clip (no empty lanes).
struct DeleteAudioClipCommand: EditorCommand {
    let clipId: String

    func apply(to project: V2Project) -> V2Project {
        // A track left with no clip is dropped: an empty lane is not shown (user 2026-10-17).
        let tracks = project.audio.tracks.map { track in
            V2AudioTrack(id: track.id, gainDb: track.gainDb, pan: track.pan, muted: track.muted, clips: track.clips.filter { $0.id != clipId })
        }.filter { !$0.clips.isEmpty }
        return project.withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}

/// Âm thanh — volume slider: writes `gainDb` verbatim on one clip (the UI
/// converts its 0–100% slider to dB before calling this, same split
/// `TrimClipCommand` already uses between "UI proposes a valid value,
/// command just writes it").
struct SetAudioClipVolumeCommand: EditorCommand {
    let clipId: String
    let gainDb: Double

    func apply(to project: V2Project) -> V2Project {
        let tracks = project.audio.tracks.map { track -> V2AudioTrack in
            var track = track
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                track.clips[index].gainDb = gainDb
            }
            return track
        }
        return project.withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}

/// Văn bản — "Thêm chữ": builds a throwaway one-layer `EditorDocument` and
/// runs it through the real `compile(_:)`/`TextLayoutCompiler` pipeline
/// (`EditorDocument/PresetCompiler.swift`) — the same path
/// `ProjectsView.openEditorProject`'s "Trip to Paris" demo text lane
/// already uses — rather than hand-building a `V2TextLayerPayload`'s
/// resolved `chunks`/`spans` here, which only real Core Text shaping can
/// produce correctly (see CLAUDE.md's "Text layout stays atomic" note).
/// Font/size/color are fixed defaults for this first pass — no style
/// picker UI exists yet to author anything else.
///
/// **Lane placement** mirrors `AddAudioClipCommand`'s "reuse a track that
/// doesn't already overlap, else open a new one" search, applied to `order`
/// instead of a separate track array — matches the "lanes are homogeneous
/// by type, pack if non-overlapping" rule from CLAUDE.md's "Timeline lanes"
/// note, which text/overlay lanes were always meant to share with video.
struct AddTextLayerCommand: EditorCommand {
    let layerId: String
    let text: String
    let atMs: Double
    /// Font, size and colour of the new clip; nil = the fixed defaults (Helvetica 32, white).
    var style: TextStyleValues? = nil
    static let defaultDurationMs: Double = 3000

    func apply(to project: V2Project) -> V2Project {
        var textValues = style ?? TextStyleValues()
        textValues.text = text
        let document = EditorDocument(
            id: "doc-\(layerId)",
            composition: project.composition,
            assets: [],
            layers: [
                EditorLayer(
                    id: layerId, kind: "text",
                    frame: V2Frame(width: project.composition.width, height: TextStyleValues.frameHeight(for: textValues, width: project.composition.width)),
                    timing: V2Timing(start: atMs, duration: Self.defaultDurationMs),
                    text: textValues.editorText()
                )
            ]
        )
        guard var newLayer = compile(document).layers.first else { return project }
        TextIntentCache.shared.remember(textValues, for: newLayer)

        let textLayers = project.layers.filter { $0.type == "text" }
        func overlaps(_ order: Int) -> Bool {
            textLayers.contains { layer in
                layer.order == order
                    && newLayer.timing.start < layer.timing.start + layer.timing.duration
                    && layer.timing.start < newLayer.timing.start + newLayer.timing.duration
            }
        }
        let existingOrders = Set(textLayers.map(\.order))
        newLayer.order = existingOrders.first(where: { !overlaps($0) }) ?? ((project.layers.map(\.order).max() ?? -1) + 1)

        return project.withLayers(project.layers + [newLayer])
    }
}

/// Layer ids of stickers start with this (`isPushLane` treats them as free overlays); their asset ids start with `stickerAssetIdPrefix`.
let stickerLayerIdPrefix = "sticker-"
let stickerAssetIdPrefix = "sticker-"
/// Asset ids of the Sound FX library's sounds (`library-<api id>`); distinct from the old bundled `sfx-*` placeholders.
let soundAssetIdPrefix = "library-"

/// Stickers - drops a sticker picture on the canvas at the playhead: one image layer, centred, sized from the canvas,
/// 3 s long (`defaultDurationMs`), in its own lane. **Lane placement** reuses a lane of *stickers* that does not overlap
/// in time, else opens a new `order`: a sticker never shares a lane with a photo overlay (those are push lanes).
/// The asset is added to the project once however many stickers use it. No-op (fail closed) for a sticker whose asset
/// is not an image.
struct AddStickerCommand: EditorCommand {
    let layerId: String
    let asset: V2ImageAsset
    let atMs: Double
    var durationMs: Double = AddStickerCommand.defaultDurationMs
    /// Width of the sticker as a fraction of the canvas' shorter side.
    var sizeFraction: Double = 0.35
    static let defaultDurationMs: Double = 3000

    func apply(to project: V2Project) -> V2Project {
        let side = min(project.composition.width, project.composition.height) * sizeFraction
        let aspect = asset.height > 0 ? asset.width / asset.height : 1
        let frame = aspect >= 1 ? V2Frame(width: side, height: side / aspect) : V2Frame(width: side * aspect, height: side)
        let document = EditorDocument(
            id: "doc-\(layerId)",
            composition: project.composition,
            assets: [.image(asset)],
            layers: [EditorLayer(id: layerId, kind: "image", assetId: asset.id, frame: frame, timing: V2Timing(start: atMs, duration: durationMs))]
        )
        guard var layer = compile(document).layers.first else { return project }

        let stickers = project.layers.filter { $0.id.hasPrefix(stickerLayerIdPrefix) }
        func overlaps(_ order: Int) -> Bool {
            stickers.contains { other in
                other.order == order && layer.timing.start < other.timing.start + other.timing.duration
                    && other.timing.start < layer.timing.start + layer.timing.duration
            }
        }
        let usedOrders = Set(stickers.map(\.order))
        layer.order = usedOrders.sorted().first(where: { !overlaps($0) }) ?? ((project.layers.map(\.order).max() ?? -1) + 1)

        let assets = project.assets.contains { $0.id == asset.id } ? project.assets : project.assets + [.image(asset)]
        return project.withAssets(assets).withLayers(project.layers + [layer])
    }
}

/// Flips a layer left-right by negating `scale.x` (Transform keeps the sign, see `SetTransformCommand`).
struct MirrorLayerCommand: EditorCommand {
    let layerId: String

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let old = layers[index].transform
        layers[index].transform = V2Transform(
            translate: old.translate, scale: V2Vec3(x: -old.scale.x, y: old.scale.y, z: old.scale.z),
            rotate: old.rotate, skew: old.skew, anchor: old.anchor, perspective: old.perspective
        )
        layers[index] = TransformKeyframes.mirroring(layers[index])
        return project.withLayers(layers)
    }
}

/// Copies a free-overlay layer (a sticker) to start where the original ends, on the same lane when it is free there.
struct DuplicateOverlayCommand: EditorCommand {
    let layerId: String
    let newLayerId: String

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        var copy = layers[index]
        copy.id = newLayerId
        copy.timing = V2Timing(start: copy.timing.start + copy.timing.duration, duration: copy.timing.duration)
        let busy = layers.contains {
            $0.order == copy.order && $0.id != layerId && copy.timing.start < $0.timing.start + $0.timing.duration
                && $0.timing.start < copy.timing.start + copy.timing.duration
        }
        if busy { copy.order = (layers.map(\.order).max() ?? 0) + 1 }
        // The copy carries the same animations, in wrappers of its own (not nested in the original's).
        let animations = AnimationWrappers.applied(for: layerId, in: layers)
        copy.parentLayerId = AnimationWrappers.baseParent(of: layers[index], in: layers)
        layers.insert(copy, at: index + 1)
        let result = project.withLayers(layers)
        return animations.isEmpty ? result : AnimationWrappers.rebuilt(result, clipId: newLayerId, animations: Array(animations.values))
    }
}

/// Văn bản — editing an existing text clip's own content. Re-runs the same
/// `compile(_:)` step `AddTextLayerCommand` uses (a text edit can't just
/// poke the string in place — `chunks`/`spans` are resolved, shaped output,
/// not live text; see CLAUDE.md's "Text layout stays atomic" note), but
/// only replaces the existing layer's `payload` — `id`/`order`/`frame`/
/// `transform`/`timing` all stay exactly as authored, so editing text never
/// moves or resizes the clip. No-op (fail closed) if the layer isn't found
/// or isn't actually a text layer.
struct SetTextContentCommand: EditorCommand {
    let layerId: String
    let text: String

    func apply(to project: V2Project) -> V2Project {
        guard let layer = project.layers.first(where: { $0.id == layerId }), layer.textPayload != nil else { return project }
        var values = TextStyleValues(layer: layer, composition: project.composition)   // the words change, the look stays
        values.text = text
        return SetTextCommand(layerId: layerId, values: values).apply(to: project)
    }
}

/// Rewrites a text clip's words and look (font, size, colour, alignment, background) through the real text pipeline; position, duration
/// and lane never move. The frame is re-fitted to the text block (around the clip's centre). No-op (fail closed) for an unknown
/// layer or one that is not text.
struct SetTextCommand: EditorCommand {
    let layerId: String
    let values: TextStyleValues

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let original = layers[index]
        guard case .text = original.payload else { return project }

        let frame = V2Frame(width: original.frame.width, height: TextStyleValues.frameHeight(for: values, width: original.frame.width))
        let document = EditorDocument(
            id: "doc-edit-\(original.id)",
            composition: project.composition,
            assets: [],
            layers: [
                EditorLayer(
                    id: original.id, kind: "text",
                    frame: frame,
                    timing: original.timing,
                    text: values.editorText()
                )
            ]
        )
        guard let recompiled = compile(document).layers.first else { return project }

        var updated = original
        updated.payload = recompiled.payload
        updated.frame = frame
        TextIntentCache.shared.remember(values, for: updated)
        layers[index] = updated
        return project.withLayers(layers)
    }
}

/// Tuỳ chỉnh - the Adjust tool's values, neutral at `AdjustValues()`: `contrast`/`saturation` are multiplicative (1 = no
/// change), every other control is centred or one-sided around 0 (0 = no change). Exposure is in EV stops. The list
/// is the user's (2026-10-12): no Lightness, no Blur (Blur moves to the Effects tool).
struct AdjustValues: Equatable {
    // Light.
    var exposure: Double = 0
    var brilliance: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var contrast: Double = 1
    var brightness: Double = 0
    var blackPoint: Double = 0
    // Color.
    var saturation: Double = 1
    var vibrance: Double = 0
    var temperature: Double = 0
    var hue: Double = 0
    var tint: Double = 0
    // Curves - a real draggable tone-curve graph (`CurveGraphView`), 5 output values at fixed x-positions
    // `0, 0.25, 0.5, 0.75, 1`. The default is the identity curve (straight diagonal, no change).
    var curvePoints: [Double] = [0, 0.25, 0.5, 0.75, 1]
    // Detail / effects.
    var vignette: Double = 0
    var sharpen: Double = 0
    var clarity: Double = 0
    var noise: Double = 0

    var isNeutral: Bool { self == AdjustValues() }
}

/// Tuỳ chỉnh — writes every non-neutral slider as one compiled `V2Filter`
/// chain (via `EffectPresetKind`/`compileFilter`, see CLAUDE.md's "Tuỳ
/// chỉnh" note) under a **stable id derived from the layer id**
/// (`"adjust-<layerId>"`), so repeated slider drags replace the same
/// `project.filters[]` entry instead of accumulating a new one per tick.
/// All-neutral values clear `layer.filter` and remove the definition
/// entirely — a clip nobody has graded carries no dead-weight identity
/// filter. No-op for an unknown layer id.
///
/// **Only sliders that actually moved become a preset** — not "always emit
/// all 8 presets with neutral values" — so a clip that's only had its
/// Vignette touched compiles to exactly one `feVignette` primitive, not an
/// 8-preset chain of mostly-identity stages. Order matches the Tuỳ chỉnh
/// panel's own left-to-right slider order, which is also the order a real
/// photo editor applies these conceptually (tone/color first, detail/
/// effects last).
struct SetAdjustCommand: EditorCommand {
    let layerId: String
    let values: AdjustValues
    /// The picked Filter (a named bundle of Adjust values) and its strength. It is compiled *before* `values`, so the
    /// sliders keep working on top of the look; both end up in the one `adjust-<layerId>` filter.
    var filter: AppliedFilter? = nil

    private static func filterId(for layerId: String) -> String { "adjust-\(layerId)" }

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }

        let chromaKey = layers[index].filter.flatMap { filterId in
            project.filters?.first(where: { $0.id == filterId })?.primitives.first(where: {
                if case .feChromaKey = $0 { return true }
                return false
            })
        }
        let id = Self.filterId(for: layerId)
        var filters = (project.filters ?? []).filter { $0.id != id }

        var presets: [EffectPresetKind] = []
        if let filter, let preset = FilterCatalog.preset(id: filter.id) {
            presets += adjustPresets(for: preset.values.scaled(filter.intensity))
        }
        presets += adjustPresets(for: values)

        if presets.isEmpty, chromaKey == nil {
            layers[index].filter = nil
        } else {
            var compiled = compileFilter(id: id, presets: presets)
            if case .feChromaKey(let existingBase, let keyColor, let similarity, let smoothness, let shadow, let edgeCleanup)? = chromaKey {
                var base = existingBase
                base.in = compiled.primitives.last?.base.result ?? "SourceGraphic"
                compiled.primitives.append(.feChromaKey(base, keyColor: keyColor, similarity: similarity,
                                                        smoothness: smoothness, shadow: shadow, edgeCleanup: edgeCleanup))
            }
            filters.append(compiled)
            layers[index].filter = id
        }
        return project.withLayers(layers).withFilters(filters.isEmpty ? nil : filters)
    }
}

/// The `EffectPresetKind`s one set of Adjust values needs - only the groups that moved off neutral, in the order a photo
/// editor applies them: tone, colour, white balance, curves, then detail and effects.
func adjustPresets(for values: AdjustValues) -> [EffectPresetKind] {
    var presets: [EffectPresetKind] = []
    let neutral = AdjustValues()
    if values.exposure != neutral.exposure || values.brilliance != neutral.brilliance
        || values.highlights != neutral.highlights || values.shadows != neutral.shadows
        || values.contrast != neutral.contrast || values.brightness != neutral.brightness
        || values.blackPoint != neutral.blackPoint {
        presets.append(.toneAdjust(
            exposure: values.exposure, brilliance: values.brilliance, highlights: values.highlights,
            shadows: values.shadows, contrast: values.contrast, brightness: values.brightness,
            blackPoint: values.blackPoint
        ))
    }
    if values.saturation != neutral.saturation || values.vibrance != neutral.vibrance || values.hue != neutral.hue {
        presets.append(.colorGrade(saturation: values.saturation, vibrance: values.vibrance, hue: values.hue))
    }
    if values.temperature != neutral.temperature || values.tint != neutral.tint {
        presets.append(.whiteBalance(temperature: values.temperature, tint: values.tint))
    }
    if values.curvePoints != neutral.curvePoints {
        presets.append(.toneCurve(points: values.curvePoints))
    }
    if values.sharpen != neutral.sharpen {
        presets.append(.sharpen(amount: values.sharpen))
    }
    if values.clarity != neutral.clarity {
        presets.append(.clarity(amount: values.clarity))
    }
    if values.vignette != neutral.vignette {
        presets.append(.vignette(intensity: values.vignette, radius: 1))
    }
    if values.noise != neutral.noise {
        presets.append(.noise(scale: 4, amount: values.noise, opacity: 0.5, seed: 0))
    }
    return presets
}

/// Where the playhead lands after a trim drag: a left handle -> the clip's start; a right handle -> its end minus one
/// frame (user decision 2026-10-12). At exactly `start + duration` no clip is visible (`t < start + duration`), so the
/// last clip of the project would show an empty preview; one frame earlier shows the clip's final frame.
func trimLandingTimeMs(isLeadingHandle: Bool, layer: V2Layer, fps: Double) -> Double {
    if isLeadingHandle { return layer.timing.start }
    let frameMs = 1000 / max(fps, 1)
    return max(layer.timing.start, layer.timing.start + layer.timing.duration - frameMs)
}
