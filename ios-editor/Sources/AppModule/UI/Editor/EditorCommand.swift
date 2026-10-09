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

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let original = layers[index]
        guard atMs > original.timing.start, atMs < original.timing.start + original.timing.duration else { return project }

        let firstDuration = atMs - original.timing.start
        let secondDuration = original.timing.duration - firstDuration

        var first = original
        first.timing = V2Timing(start: original.timing.start, duration: firstDuration)

        var second = original
        second.id = "\(original.id)-split-\(UUID().uuidString.prefix(8))"
        second.timing = V2Timing(start: atMs, duration: secondDuration)
        // A video clip's second half must keep playing from where the
        // first half left off in the *source* file, not restart from the
        // original's own trim point — shift `trimStart` forward by exactly
        // the first half's duration.
        if case .video(var payload) = second.payload {
            payload.trimStart = (payload.trimStart ?? 0) + firstDuration
            second.payload = .video(payload)
        }

        layers[index] = first
        layers.insert(second, at: index + 1)
        return project.withLayers(layers)
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
        layer.timing = V2Timing(start: start, duration: duration)
        if case .video(var payload) = layer.payload {
            payload.trimStart = trimStart
            payload.trimEnd = trimEnd
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
        project.withLayers(project.layers.filter { $0.id != layerId })
    }
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
/// holds it. Leaves an empty track in place rather than pruning it — no
/// user-visible difference, and simpler than re-deriving which tracks are
/// "real" vs. incidentally empty.
struct DeleteAudioClipCommand: EditorCommand {
    let clipId: String

    func apply(to project: V2Project) -> V2Project {
        let tracks = project.audio.tracks.map { track in
            V2AudioTrack(id: track.id, gainDb: track.gainDb, pan: track.pan, muted: track.muted, clips: track.clips.filter { $0.id != clipId })
        }
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
    static let defaultDurationMs: Double = 3000

    func apply(to project: V2Project) -> V2Project {
        let document = EditorDocument(
            id: "doc-\(layerId)",
            composition: project.composition,
            assets: [],
            layers: [
                EditorLayer(
                    id: layerId, kind: "text",
                    frame: V2Frame(width: project.composition.width, height: 80),
                    timing: V2Timing(start: atMs, duration: Self.defaultDurationMs),
                    text: EditorTextLayer(
                        text: text, fontFamily: "Helvetica", fontSize: 32, color: "#FFFFFFff",
                        layout: EditorTextLayoutIntent(textAlign: "center", wrap: "none")
                    )
                )
            ]
        )
        guard var newLayer = compile(document).layers.first else { return project }

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
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }
        let original = layers[index]
        guard case .text = original.payload else { return project }

        let document = EditorDocument(
            id: "doc-edit-\(original.id)",
            composition: project.composition,
            assets: [],
            layers: [
                EditorLayer(
                    id: original.id, kind: "text",
                    frame: original.frame,
                    timing: original.timing,
                    text: EditorTextLayer(
                        text: text, fontFamily: "Helvetica", fontSize: 32, color: "#FFFFFFff",
                        layout: EditorTextLayoutIntent(textAlign: "center", wrap: "none")
                    )
                )
            ]
        )
        guard let recompiled = compile(document).layers.first else { return project }

        var updated = original
        updated.payload = recompiled.payload
        layers[index] = updated
        return project.withLayers(layers)
    }
}

/// Tuỳ chỉnh — the 4 slider values, neutral at `AdjustValues()`. `brightness`
/// is additive (0 = no change), `contrast`/`saturation` are multiplicative
/// (1 = no change), `exposure` is EV stops (0 = no change) — matching
/// `EffectPresetKind.colorAdjust`'s own parameter shapes exactly, since this
/// struct exists only to carry those 4 numbers between the UI and
/// `SetAdjustCommand`.
struct AdjustValues: Equatable {
    // Light/color basics.
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var exposure: Double = 0
    // HSL (completes Hue/Saturation/Lightness — `saturation` above is
    // shared with the basics group, same slider drives both).
    var hue: Double = 0
    var lightness: Double = 0
    // White balance.
    var temperature: Double = 0
    var tint: Double = 0
    // Tone curve (Highlights/Shadows/Whites/Blacks — see
    // `EffectPresetKind.toneCurve`'s own doc comment on why these 4
    // sliders stand in for a real draggable curve graph this pass).
    var blacks: Double = 0
    var shadows: Double = 0
    var highlights: Double = 0
    var whites: Double = 0
    // Detail.
    var sharpen: Double = 0
    var clarity: Double = 0
    var blur: Double = 0
    // Effects.
    var vignette: Double = 0
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

    private static func filterId(for layerId: String) -> String { "adjust-\(layerId)" }

    func apply(to project: V2Project) -> V2Project {
        var layers = project.layers
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return project }

        let id = Self.filterId(for: layerId)
        var filters = (project.filters ?? []).filter { $0.id != id }

        if values.isNeutral {
            layers[index].filter = nil
        } else {
            var presets: [EffectPresetKind] = []
            let neutral = AdjustValues()
            if values.brightness != neutral.brightness || values.contrast != neutral.contrast
                || values.saturation != neutral.saturation || values.exposure != neutral.exposure
                || values.hue != neutral.hue || values.lightness != neutral.lightness {
                presets.append(.colorAdjust(
                    brightness: values.brightness, contrast: values.contrast, saturation: values.saturation,
                    exposure: values.exposure, hueRotate: values.hue, lightness: values.lightness
                ))
            }
            if values.temperature != neutral.temperature || values.tint != neutral.tint {
                presets.append(.whiteBalance(temperature: values.temperature, tint: values.tint))
            }
            if values.blacks != neutral.blacks || values.shadows != neutral.shadows
                || values.highlights != neutral.highlights || values.whites != neutral.whites {
                presets.append(.toneCurve(blacks: values.blacks, shadows: values.shadows, highlights: values.highlights, whites: values.whites))
            }
            if values.sharpen != neutral.sharpen {
                presets.append(.sharpen(amount: values.sharpen))
            }
            if values.clarity != neutral.clarity {
                presets.append(.clarity(amount: values.clarity))
            }
            if values.blur != neutral.blur {
                presets.append(.blur(radius: values.blur))
            }
            if values.vignette != neutral.vignette {
                presets.append(.vignette(intensity: values.vignette, radius: 1))
            }
            if values.noise != neutral.noise {
                presets.append(.noise(scale: 4, amount: values.noise, opacity: 0.5, seed: 0))
            }

            if presets.isEmpty {
                layers[index].filter = nil
            } else {
                filters.append(compileFilter(id: id, presets: presets))
                layers[index].filter = id
            }
        }

        return project.withLayers(layers).withFilters(filters.isEmpty ? nil : filters)
    }
}
