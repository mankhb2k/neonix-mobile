import SwiftUI

/// Timeline panel below Stage/Titlebar: a time ruler, one row per **lane**,
/// and a **fixed, horizontally-centered playhead** — matching CapCut's own
/// interaction model, not a moving-line-over-static-track design. Dragging
/// anywhere in the panel shifts the whole ruler+track content left/right
/// underneath the fixed playhead line; whatever frame lands under it becomes
/// `currentTimeMs`.
///
/// **Lanes, not 1-layer-per-row** (added 2026-10-08, see CLAUDE.md's
/// "Timeline lanes" note for the full design discussion): every layer
/// sharing one `order` value is the same timeline row — `order` identifies
/// the *lane*, not a per-clip sequence number. A lane only ever holds more
/// than one layer when they don't overlap in time (several clips authored
/// back-to-back on the main video lane, for instance); within a lane,
/// left-to-right position comes from each clip's own `timing.start`, never
/// from `order`. This generalizes what used to be a main-track-only
/// exception into one rule for every lane. `LaneRowView` renders one lane;
/// clips of `type == "video"` render as a real filmstrip (`FilmstripClipView`)
/// and everything else stays the flat color block (`TimelineClipView`) — no
/// thumbnail concept applies to text/audio/shape layers.
///
/// Shared by the selection "khung bao bọc" (bounding frame) stroke and
/// `TrimHandleView`'s own height, so the two always read as one unified
/// block (added 2026-10-08, per the user's own naming for these 3 pieces:
/// clip, tay nắm 2 bên / the two side handles, khung bao bọc / the
/// bounding frame drawn around a selected clip) — `.stroke(lineWidth:)`
/// paints half its width outside the shape's own bounds, so a selected
/// clip's visible bounding frame is actually `rowHeight +
/// selectionBorderWidth` tall, not `rowHeight`; the handles now match that
/// same height instead of the plain clip height, so they don't look
/// shorter than the frame they sit inside.
private let selectionBorderWidth: CGFloat = 2

struct TimelineView: View {
    let layers: [V2Layer]
    let assets: [V2Asset]
    /// Standalone audio tracks (`project.audio`) — a *separate* section
    /// below the visual lanes, not folded into `order`/lane grouping at
    /// all. Audio already had its own native multi-clip-per-track shape
    /// (`V2AudioTrack.clips: [V2AudioClip]`) before lanes existed, and the
    /// user explicitly scoped audio as its own exception when lanes were
    /// designed — see CLAUDE.md's "Timeline lanes" note.
    let audio: V2AudioDomain
    /// The playhead lives in the engine — this view only reads it and sends
    /// scrub gestures to it (`beginScrub`/`scrub`/`endScrub`).
    let engine: EditorPlaybackEngine
    /// Chỉnh sửa (Phase 2 of the "Bottom nav tools" roadmap) — which
    /// layer's clip is selected, if any. Only visual layers (`layers[]`)
    /// are selectable via this binding; standalone audio clips use their
    /// own `selectedAudioClipId` below (Âm thanh's own phase).
    @Binding var selectedLayerId: String?
    /// Âm thanh — which standalone `V2AudioClip` is selected, if any. A
    /// separate selection from `selectedLayerId` since audio clips live in
    /// `project.audio`, not `layers[]`, and tapping one deselects any
    /// selected layer and vice versa (`EditorShellView` clears the other
    /// whenever one changes) so the options panel never has to reconcile
    /// two simultaneous selections.
    @Binding var selectedAudioClipId: String?
    /// Drag-to-trim (added 2026-10-08, confirmed against a CapCut reference
    /// screenshot): a selected clip grows 2 draggable handles at its own
    /// left/right edges instead of a plain selection border. These 3
    /// closures are `EditorShellView`'s own `beginTrim`/`updateTrim`/
    /// `endTrim` — see their doc comments there for why a drag collapses
    /// into exactly one undo step instead of one per pixel moved.
    let onTrimBegin: () -> Void
    let onTrimUpdate: (EditorCommand) -> Void
    let onTrimEnd: () -> Void
    /// Composition frame rate — the finest zoom step is one frame.
    var fps: Double = 30

    /// Pinch-to-zoom scale. The playhead is pinned to the centre of the
    /// panel and the content slides under it (`contentOffsetX`), so changing
    /// this zooms around the playhead with no extra anchoring maths.
    @State private var pxPerMs: Double = TimelineZoom.defaultPxPerMs
    @State private var pinchBaseScale: Double?
    @State private var isPinching = false
    /// While two fingers are down the drag recogniser also reports the
    /// fingers' centroid moving; those events must not scrub, and when the
    /// pinch ends with one finger still down, the drag's translation (which
    /// kept growing) is re-based so the playhead doesn't jump.
    @State private var dragNeedsRebase = false
    @State private var dragRebaseX: CGFloat = 0
    /// Only fed while a metrics run is recording; see `ReleaseVelocityEstimator`.
    @State private var releaseEstimator = ReleaseVelocityEstimator()
    /// Only the main (primary video) lane uses this height — every other
    /// lane, including every standalone audio track, uses the smaller
    /// `otherRowHeight` instead. Confirmed with the user 2026-10-08: the
    /// main track is the one row that needs full-height filmstrip tiles/
    /// cover art; text/overlay/audio rows are thinner, matching CapCut's
    /// own visual hierarchy (one prominent row, everything else
    /// secondary). `otherRowHeight` is its own constant, not `rowHeight /
    /// 2` — set independently once 26 (not exactly half of 48) was asked for.
    private let rowHeight: CGFloat = 48
    private let otherRowHeight: CGFloat = 26
    private let rowSpacing: CGFloat = 6
    private let rulerHeight: CGFloat = 20
    private let rowsTopPadding: CGFloat = 6

    private var currentTimeMs: Double { engine.currentTimeMs }
    private var maxDurationMs: Double { engine.maxDurationMs }
    /// Placeholder: the mute button isn't wired to
    /// `V2VideoPayload.audio.enabled`; it only flips this local state.
    @State private var isMuted = false
    @State private var coverImage: UIImage?

    private var tracks: [V2Layer] {
        layers.filter { $0.type != "group" }
    }

    /// Every distinct lane (`order` value) present, ascending — lane 0
    /// renders topmost in this panel *and* bottommost in the render stack
    /// (`PreviewCanvas`'s `sorted { $0.order < $1.order }`), matching CapCut:
    /// the main video lane sits at the top of the timeline, with lanes added
    /// below it (higher `order`) compositing visually on top of it.
    private var laneOrders: [Int] {
        Set(tracks.map(\.order)).sorted()
    }

    /// A lane's own clips, sorted left-to-right by `timing.start` — never by
    /// `order`, which is shared by every clip in the lane and says nothing
    /// about their relative position in time.
    private func lane(for order: Int) -> [V2Layer] {
        tracks.filter { $0.order == order }.sorted { $0.timing.start < $1.timing.start }
    }

    /// The lane that gets the cover cell + mute button — the first lane
    /// (lowest `order`) that contains a video clip, matching the single
    /// "main track" this app supports authoring today.
    private var primaryVideoLaneOrder: Int? {
        laneOrders.first { lane(for: $0).contains { $0.type == "video" } }
    }

    private var contentWidth: CGFloat {
        max(CGFloat(maxDurationMs) * pxPerMs, 1)
    }

    private var rowCount: Int {
        laneOrders.count + audio.tracks.count
    }

    private var tracksHeight: CGFloat {
        guard rowCount > 0 else { return otherRowHeight }
        let hasMainLane = primaryVideoLaneOrder != nil
        let otherRowCount = rowCount - (hasMainLane ? 1 : 0)
        let rowsHeight = (hasMainLane ? rowHeight : 0) + CGFloat(otherRowCount) * otherRowHeight
        let spacingHeight = CGFloat(rowCount - 1) * rowSpacing
        return rowsHeight + spacingHeight
    }

    private var panelHeight: CGFloat {
        rulerHeight + rowsTopPadding + tracksHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                // Counted here, not in `body`: this closure is what re-runs
                // on every playhead change (it reads `currentTimeMs`).
                let _ = PlaybackMetrics.shared.count(.timelineBodyEvals)
                let centerX = geo.size.width / 2
                let contentOffsetX = centerX - CGFloat(currentTimeMs) * pxPerMs
                // Zoom level for the metrics log (cheap early-out when not recording).
                let _ = {
                    guard PlaybackMetrics.shared.isRecording else { return }
                    PlaybackMetrics.shared.gauge(.timelineScale, pxPerMs)
                    PlaybackMetrics.shared.gauge(.timelineViewportPx, Double(geo.size.width))
                    PlaybackMetrics.shared.gauge(.rulerMinorMs, TimelineZoom.rulerIntervals(pxPerMs: pxPerMs, fps: fps).minorMs)
                }()
                let windowMs = TimelineZoom.visibleWindowMs(currentTimeMs: currentTimeMs, viewportWidth: Double(geo.size.width), pxPerMs: pxPerMs)

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: rowsTopPadding) {
                        TimeRulerView(pxPerMs: pxPerMs, fps: fps, maxDurationMs: maxDurationMs, contentWidth: contentWidth, windowMs: windowMs)
                            .frame(height: rulerHeight)

                        VStack(alignment: .leading, spacing: rowSpacing) {
                            ForEach(laneOrders, id: \.self) { order in
                                let isMainLane = order == primaryVideoLaneOrder
                                LaneRowView(
                                    clips: lane(for: order),
                                    pxPerMs: pxPerMs,
                                    windowMs: windowMs,
                                    rowHeight: isMainLane ? rowHeight : otherRowHeight,
                                    centerX: centerX,
                                    showsCoverAndMute: isMainLane,
                                    coverImage: coverImage,
                                    isMuted: isMuted,
                                    onToggleMute: { isMuted.toggle() },
                                    resolveAsset: { layer in (assetId(for: layer), assetURL(for: layer)) },
                                    resolveAudioURL: { layer in audioDerivativeURL(for: layer) },
                                    selectedLayerId: selectedLayerId,
                                    onSelectLayer: { id in
                                        selectedLayerId = (selectedLayerId == id) ? nil : id
                                        selectedAudioClipId = nil
                                    },
                                    onTrimBegin: onTrimBegin,
                                    onTrimUpdate: onTrimUpdate,
                                    onTrimEnd: onTrimEnd
                                )
                            }

                            ForEach(audio.tracks, id: \.id) { track in
                                AudioTrackRowView(
                                    track: track,
                                    pxPerMs: pxPerMs,
                                    rowHeight: otherRowHeight,
                                    resolveAudioURL: { clip in audioClipURL(for: clip) },
                                    selectedClipId: selectedAudioClipId,
                                    onSelectClip: { id in
                                        selectedAudioClipId = (selectedAudioClipId == id) ? nil : id
                                        selectedLayerId = nil
                                    }
                                )
                            }
                        }
                    }
                    .offset(x: contentOffsetX)
                    .frame(width: geo.size.width, height: panelHeight, alignment: .topLeading)
                    .clipped()

                    // Only the playhead itself stays fixed — the cover cell
                    // and mute button scroll together with the filmstrip as
                    // ordinary content now (see `FilmstripRowView`), not a
                    // separate always-on-top overlay. Spans the panel's full
                    // height (not just `panelHeight`), same as the drag
                    // surface below — see this file's own note on why.
                    PlayheadOverlay(centerX: centerX, totalHeight: geo.size.height)
                }
                // The drag/hit-test area covers the *entire* panel height
                // handed to this view, not just the ruler+tracks' own
                // `panelHeight` — previously `.contentShape`/`.gesture` sat
                // on a ZStack whose implicit size was only as tall as its
                // content, so dragging anywhere in the (usually much
                // taller) leftover blank space below the filmstrip did
                // nothing. Scrubbing should work from a touch landing
                // anywhere in the timeline, not just exactly on the track.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("timeline")
                .accessibilityValue(String(format: "%.4f", pxPerMs))
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if !isPinching {
                                isPinching = true
                                pinchBaseScale = pxPerMs
                                // A scrub that was already under way ends here;
                                // the pinch owns the gesture from now on.
                                if engine.mode == .scrubbing { engine.endScrub(velocityMsPerSecond: 0) }
                            }
                            let base = pinchBaseScale ?? pxPerMs
                            pxPerMs = TimelineZoom.clamped(base * Double(value.magnification), fps: fps)
                            PlaybackMetrics.shared.count(.pinchEvents)
                            PlaybackMetrics.shared.gauge(.timelineScale, pxPerMs)
                        }
                        .onEnded { _ in
                            isPinching = false
                            pinchBaseScale = nil
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if isPinching {
                                dragNeedsRebase = true
                                return
                            }
                            if dragNeedsRebase {
                                dragRebaseX = value.translation.width
                                dragNeedsRebase = false
                            }
                            PlaybackMetrics.shared.count(.dragEvents)
                            if PlaybackMetrics.shared.isRecording {
                                // `value.time` is the touch's own timestamp; the
                                // handler's wall clock is useless here because
                                // SwiftUI delivers several touch events in one
                                // pass (their handler times differ by microseconds).
                                releaseEstimator.add(time: value.time.timeIntervalSinceReferenceDate,
                                                     x: Double(value.translation.width))
                            }
                            PlaybackMetrics.shared.measure(.inputHandlerMs) {
                                engine.beginScrub()
                                engine.scrub(deltaMs: -Double(value.translation.width - dragRebaseX) / pxPerMs)
                            }
                        }
                        .onEnded { value in
                            dragNeedsRebase = false
                            dragRebaseX = 0
                            guard !isPinching else { return }
                            let metrics = PlaybackMetrics.shared
                            if metrics.isRecording {
                                metrics.record(.releaseFingerPxPerSecond, ms: abs(Double(value.velocity.width)))
                                if let estimate = releaseEstimator.pointsPerSecond {
                                    metrics.record(.releaseEstimatedPxPerSecond, ms: abs(estimate))
                                }
                                if let hold = releaseEstimator.holdSeconds(now: value.time.timeIntervalSinceReferenceDate) {
                                    metrics.record(.releaseHoldMs, ms: hold * 1000)
                                }
                            }
                            releaseEstimator.reset()
                            // `.velocity` is points/sec (iOS 17+); negated and
                            // converted the same way as translation, so a
                            // release continues the direction/speed the
                            // finger was already moving.
                            engine.endScrub(velocityMsPerSecond: -Double(value.velocity.width) / pxPerMs)
                        }
                )
            }
            .frame(maxHeight: .infinity)
        }
        // Pinned to the *top* of whatever height `EditorShellView` hands
        // this panel, matching CapCut (ruler+filmstrip sits flush under the
        // titlebar divider, not vertically centered in the leftover space)
        // — a plain `VStack` with one fixed-height child centers it by
        // default once the parent gives it more height than it needs.
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
        .background(Color(.systemBackground))
        .task(id: coverAssetKey) {
            await loadCoverImage()
        }
    }

    /// The cover thumbnail always represents the primary video lane's
    /// *earliest* clip, regardless of how many clips share that lane.
    private var coverAssetKey: String? {
        guard let primaryVideoLaneOrder, let first = lane(for: primaryVideoLaneOrder).first else { return nil }
        return assetId(for: first)
    }

    private func loadCoverImage() async {
        guard let primaryVideoLaneOrder, let layer = lane(for: primaryVideoLaneOrder).first else { return }
        guard let assetId = assetId(for: layer), let url = assetURL(for: layer) else { return }
        let sourceMs = VideoTimeMapping(layer: layer)?.sourceMs(atTimelineMs: layer.timing.start) ?? 0
        coverImage = await VideoFrameCache.shared.frame(assetId: assetId, url: url, atSeconds: sourceMs / 1000)
    }

    private func assetId(for layer: V2Layer) -> String? {
        switch layer.payload {
        case .video(let payload): return payload.assetId
        case .image(let payload): return payload.assetId
        default: return nil
        }
    }

    private func assetURL(for layer: V2Layer) -> URL? {
        guard let id = assetId(for: layer), let asset = assets.first(where: { $0.id == id }) else { return nil }
        return bundledURL(filename: asset.uri)
    }

    /// "Attached audio" — see `CLAUDE.md`'s audio design note: a video
    /// layer's embedded audio is never its own `V2Layer`/lane; this just
    /// looks up the video asset's own `V2VideoAudioDerivative.uri` (an
    /// already-separate, independently seekable audio file extracted at
    /// import time) so `FilmstripClipView` can draw a waveform indicator
    /// riding along with the video clip's own row.
    private func audioDerivativeURL(for layer: V2Layer) -> URL? {
        guard case .video(let payload) = layer.payload,
              let asset = assets.first(where: { $0.id == payload.assetId }),
              case .video(let videoAsset) = asset,
              let derivative = videoAsset.audio
        else { return nil }
        return bundledURL(filename: derivative.uri)
    }

    /// A standalone `V2AudioClip`'s own asset — a real, independent
    /// `.audio` asset (not a video's embedded derivative).
    private func audioClipURL(for clip: V2AudioClip) -> URL? {
        guard let asset = assets.first(where: { $0.id == clip.assetId }),
              case .audio(let audioAsset) = asset
        else { return nil }
        return bundledURL(filename: audioAsset.uri)
    }
}

/// The one element that actually stays fixed on screen while the timeline
/// scrolls: a center vertical line spanning the full ruler+tracks height. A
/// plain white line disappears against this panel's own white background
/// wherever it isn't crossing colored track content, so a dark halo rides
/// underneath it to keep it visible everywhere along its height.
private struct PlayheadOverlay: View {
    let centerX: CGFloat
    let totalHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(width: 4, height: totalHeight)
                .offset(x: centerX - 2)
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: totalHeight)
                .offset(x: centerX - 1)
        }
    }
}

/// One lane (timeline row) — every layer sharing 1 `order` value, already
/// sorted by `timing.start` by the caller. Each clip positions itself
/// independently (`FilmstripClipView`/`TimelineClipView` both self-offset by
/// their own `timing.start`), since a lane can hold several non-overlapping
/// clips, not just one. Mute button + cover-image cell (only on the primary
/// video lane, `showsCoverAndMute`) sit immediately before the lane's
/// *earliest* clip, in the same coordinate space as every clip — they
/// scroll together as ordinary content, not a fixed overlay (see
/// `ui-design-note.md`'s 2026-10-07 entry on this reversal).
private struct LaneRowView: View {
    let clips: [V2Layer]
    let pxPerMs: Double
    /// The slice of the timeline that is actually built (see
    /// `TimelineZoom.visibleWindowMs`); filmstrips only create tiles in it.
    let windowMs: ClosedRange<Double>
    let rowHeight: CGFloat
    /// Half the viewport's own width — a per-geometry layout constant (from
    /// `GeometryReader`'s `geo.size.width / 2`, recomputed only when the
    /// panel itself resizes), not a scroll-position value like
    /// `visibleRange`. Used to center the mute/cover group in the screen's
    /// left half symmetrically (see `prefixOffsetX`) without reintroducing
    /// the per-scroll-tick recalculation the user explicitly rejected.
    let centerX: CGFloat
    let showsCoverAndMute: Bool
    let coverImage: UIImage?
    let isMuted: Bool
    let onToggleMute: () -> Void
    let resolveAsset: (V2Layer) -> (id: String?, url: URL?)
    let resolveAudioURL: (V2Layer) -> URL?
    let selectedLayerId: String?
    let onSelectLayer: (String) -> Void
    let onTrimBegin: () -> Void
    let onTrimUpdate: (EditorCommand) -> Void
    let onTrimEnd: () -> Void

    private let prefixSpacing: CGFloat = 8

    /// The mute/cover group's own real rendered width (two `rowHeight`
    /// cells plus the one gap between them) — not inflated with any extra
    /// margin; the margin on both sides now comes from centering (see
    /// `prefixOffsetX`), not from a baked-in constant.
    private var groupWidth: CGFloat {
        2 * rowHeight + prefixSpacing
    }

    private var laneStartMs: Double {
        clips.first?.timing.start ?? 0
    }

    private var clipStartX: CGFloat {
        CGFloat(laneStartMs) * pxPerMs
    }

    /// Centers the mute/cover group in the screen's left half — the span
    /// from the viewport's own left edge to the playhead (at `centerX`) —
    /// symmetrically: equal blank space before the group and between the
    /// group and the clip/playhead. This is a *static* placement (per the
    /// user's own request 2026-10-08): it depends only on `centerX` (a
    /// per-geometry layout constant) and each clip's own fixed
    /// `timing.start`, never on `currentTimeMs`/`visibleRange` — so the
    /// group scrolls as ordinary lane content exactly like a clip does,
    /// it just rests at this centered position when the lane's own start
    /// lines up with the playhead (the common case, since the main lane
    /// always starts at `timing.start == 0`).
    private var prefixOffsetX: CGFloat {
        clipStartX - (centerX + groupWidth) / 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsCoverAndMute {
                HStack(spacing: prefixSpacing) {
                    MuteButtonCell(rowHeight: rowHeight, isMuted: isMuted, onToggleMute: onToggleMute)
                    CoverCell(rowHeight: rowHeight, coverImage: coverImage)
                }
                .offset(x: prefixOffsetX)
            }

            ForEach(clips, id: \.id) { layer in
                let resolved = resolveAsset(layer)
                let isSelected = layer.id == selectedLayerId
                if layer.type == "video" {
                    FilmstripClipView(
                        layer: layer,
                        laneClips: clips,
                        assetId: resolved.id,
                        assetURL: resolved.url,
                        audioURL: resolveAudioURL(layer),
                        pxPerMs: pxPerMs,
                        windowMs: windowMs,
                        rowHeight: rowHeight,
                        isSelected: isSelected,
                        onTrimBegin: onTrimBegin,
                        onTrimUpdate: onTrimUpdate,
                        onTrimEnd: onTrimEnd
                    )
                    .onTapGesture { onSelectLayer(layer.id) }
                } else {
                    TimelineClipView(
                        layer: layer,
                        laneClips: clips,
                        pxPerMs: pxPerMs,
                        rowHeight: rowHeight,
                        isSelected: isSelected,
                        onTrimBegin: onTrimBegin,
                        onTrimUpdate: onTrimUpdate,
                        onTrimEnd: onTrimEnd
                    )
                    .onTapGesture { onSelectLayer(layer.id) }
                }
            }
        }
        .frame(height: rowHeight, alignment: .topLeading)
    }
}

/// A standalone audio track's row — one `V2AudioTrack`, each of its own
/// `clips` rendered independently (clips never overlap within a real
/// track, same non-overlap invariant as a visual lane). Unlike visual
/// lanes, an audio track is never shared with another track in one row —
/// `V2AudioDomain` already models "multiple tracks, each with multiple
/// clips" natively, so there's no lane-grouping to do here at all.
private struct AudioTrackRowView: View {
    let track: V2AudioTrack
    let pxPerMs: Double
    let rowHeight: CGFloat
    let resolveAudioURL: (V2AudioClip) -> URL?
    let selectedClipId: String?
    let onSelectClip: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.clips, id: \.id) { clip in
                AudioClipView(clip: clip, audioURL: resolveAudioURL(clip), pxPerMs: pxPerMs, rowHeight: rowHeight, isSelected: clip.id == selectedClipId)
                    .onTapGesture { onSelectClip(clip.id) }
            }
        }
        .frame(height: rowHeight, alignment: .topLeading)
    }
}

/// One standalone audio clip — a real decoded waveform (reusing
/// `WaveformCache`/`WaveformCurveView`, the same mechanism
/// `FilmstripClipView` uses for embedded video audio) inside a cyan-keyed
/// block. Cyan, not plain `.blue` — `FilmstripClipView`'s own border is
/// already `.blue`, so reusing it here would make the video and audio
/// lanes read as the same color; cyan stays in the "blue" family the user
/// asked for while keeping the two lane types visually distinct.
private struct AudioClipView: View {
    let clip: V2AudioClip
    let audioURL: URL?
    let pxPerMs: Double
    let rowHeight: CGFloat
    /// Âm thanh (added once standalone audio clips became selectable) —
    /// same bounding-frame stroke `TimelineClipView`/`FilmstripClipView`
    /// already use for a selected visual clip, reused rather than
    /// reinvented. No drag-to-trim handles yet (see the roadmap plan) —
    /// just the selection indicator.
    var isSelected: Bool = false

    private var clipWidth: CGFloat {
        max(CGFloat(clip.timing.duration) * pxPerMs, 28)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Flat solid-ish block, no border — matches the reference
            // CapCut screenshot's "1 color block" look for a non-video
            // clip (confirmed with the user 2026-10-08). A touch more
            // opaque than the old 0.18 so it reads as a solid block
            // rather than a faint tint, while staying translucent enough
            // for the waveform drawn on top to still show.
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.cyan.opacity(0.45))
            if let audioURL {
                // "Splitting" the old symmetric wave in half means the
                // visible half keeps the *same proportions* it always
                // had — half the row's height, not stretched to fill the
                // whole row — bottom-aligned within the full row.
                WaveformStripView(audioURL: audioURL, pointCount: min(max(Int(clipWidth / 8), 1), 1500), color: .cyan.opacity(0.8))
                    .frame(width: clipWidth, height: rowHeight / 2)
                    .frame(width: clipWidth, height: rowHeight, alignment: .bottom)
            }
            Image(systemName: "waveform")
                .font(.caption2)
                .foregroundColor(.cyan)
                .padding(4)
        }
        .frame(width: clipWidth, height: rowHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(isSelected ? RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(white: 0.2), lineWidth: selectionBorderWidth) : nil)
        .offset(x: CGFloat(clip.timing.start) * pxPerMs)
        .zIndex(isSelected ? 1 : 0)
    }
}

private struct MuteButtonCell: View {
    let rowHeight: CGFloat
    let isMuted: Bool
    let onToggleMute: () -> Void

    var body: some View {
        Button(action: onToggleMute) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundColor(.white)
                .frame(width: rowHeight, height: rowHeight)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

/// Placeholder — no "set cover" screen exists yet, and tapping does nothing.
private struct CoverCell: View {
    let rowHeight: CGFloat
    let coverImage: UIImage?

    var body: some View {
        Button {
        } label: {
            ZStack {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.3)
                }
                Image(systemName: "pencil.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .frame(width: rowHeight, height: rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white, lineWidth: 1.5)
            )
        }
    }
}

/// A simple tick+label ruler drawn with `Canvas` (one draw pass, no per-
/// tick view) — a minor tick every second, a `mm:ss` label every 2 seconds,
/// matching the reference CapCut screenshot's spacing.
private struct TimeRulerView: View {
    let pxPerMs: Double
    let fps: Double
    let maxDurationMs: Double
    let contentWidth: CGFloat
    /// Only ticks inside this slice are drawn — at full zoom-in the ruler is
    /// ~45 000 pt wide, far past what a single `Canvas` layer should be.
    let windowMs: ClosedRange<Double>

    var body: some View {
        let intervals = TimelineZoom.rulerIntervals(pxPerMs: pxPerMs, fps: fps)
        let majorEvery = max(Int((intervals.majorMs / intervals.minorMs).rounded()), 1)
        let firstMs = max(windowMs.lowerBound, 0)
        let lastMs = min(windowMs.upperBound, maxDurationMs)
        let originX = CGFloat(firstMs) * pxPerMs
        let width = max(CGFloat(lastMs - firstMs) * pxPerMs, 1)
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                var index = max(Int((firstMs / intervals.minorMs).rounded(.down)), 0)
                var ms = Double(index) * intervals.minorMs
                while ms <= lastMs {
                    let x = CGFloat(ms) * pxPerMs - originX
                    let isMajor = index % majorEvery == 0
                    let tickHeight: CGFloat = isMajor ? 7 : 4
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        },
                        with: .color(.secondary),
                        lineWidth: 1
                    )
                    if isMajor {
                        context.draw(
                            Text(TimelineZoom.rulerLabel(ms: ms, majorMs: intervals.majorMs, fps: fps)).font(.caption2).foregroundColor(.secondary),
                            at: CGPoint(x: x + 2, y: size.height / 2 - 6),
                            anchor: .leading
                        )
                    }
                    index += 1
                    ms = Double(index) * intervals.minorMs
                }
            }
            .frame(width: width)
            .offset(x: originX)
        }
        .frame(width: contentWidth, alignment: .topLeading)
    }
}

/// A video track's clip, rendered as a real filmstrip — one square tile per
/// `rowHeight`-wide slice of the clip, each showing the actual decoded
/// frame at that point. Every tile's thumbnail is fetched in **one batch**
/// (`VideoFrameCache.filmstripImages`, AVFoundation's own
/// `generateCGImagesAsynchronously` API) when the clip appears or its width
/// changes, rather than each tile firing its own independent decode —
/// real editors build filmstrips this way (see CLAUDE.md's scrubbing-lag
/// investigation, 2026-10-08). Not yet windowed to only on-screen tiles —
/// fine for this app's short sample clips; a very long clip would want
/// that back (see `VideoFrameCache.filmstripImages`'s own doc comment).
///
/// When `audioURL` is present (the video asset has an embedded-audio
/// derivative — see `TimelineView.audioDerivativeURL(for:)`), a thin
/// waveform strip is drawn along the bottom edge, *inside* the clip's own
/// `rowHeight` bounding box (not a taller row) — the simplest way to show
/// "audio rides along with this video clip" without reworking every lane's
/// height math for one row type. See `CLAUDE.md`'s audio design note.
private struct FilmstripClipView: View {
    let layer: V2Layer
    /// The whole lane's clips (including this one), read fresh every
    /// render — needed for the ripple reflow (`reflowLane(...)`), since a
    /// video clip is always a push-lane type (see `isPushLaneType(_:)`).
    let laneClips: [V2Layer]
    let assetId: String?
    let assetURL: URL?
    let audioURL: URL?
    let pxPerMs: Double
    let windowMs: ClosedRange<Double>
    let rowHeight: CGFloat
    let isSelected: Bool
    let onTrimBegin: () -> Void
    let onTrimUpdate: (EditorCommand) -> Void
    let onTrimEnd: () -> Void

    /// The clip's own layer state at the moment a trim drag began — deltas
    /// are computed against this fixed origin every `onChanged` tick
    /// (absolute, not incremental), the same reasoning `TimelineView`'s own
    /// scrub-drag already uses. `nil` whenever no trim drag is in progress.
    @State private var dragStartLayer: V2Layer?
    /// The source video's own real duration (`AssetDurationCache`), loaded
    /// once a clip becomes selected — the right handle needs this to know
    /// how far it's allowed to *extend* (reveal more unused footage) rather
    /// than only being able to shrink. `nil` until loaded, in which case an
    /// extend-right drag is simply not clamped yet (matches this app's
    /// "fail closed to a no-op, not a crash" convention elsewhere — it just
    /// means the drag does nothing past the known-safe range until the
    /// duration arrives, which is normally near-instant).
    @State private var assetDurationMs: Double?
    /// Every tile's decoded thumbnail, fetched in one batch (see
    /// `VideoFrameCache.filmstripImages`) rather than per-tile — keyed by
    /// tile index, matching the order `tileSeconds(_:)` produces.
    @State private var tileImages: [Int: UIImage] = [:]
    /// Which layout (`tileCount`/trim/rate) `tileImages` belongs to — an
    /// index means a different moment once any of those change.
    @State private var imagesLayout: FilmstripBatchKey?
    private let minDurationMs: Double = 200
    /// Thumbnails kept beyond the window, in tiles, before they are dropped.
    private let tileRetention = 24

    private var clipWidth: CGFloat {
        max(CGFloat(layer.timing.duration) * pxPerMs, 28)
    }

    private var tileCount: Int {
        max(Int((clipWidth / rowHeight).rounded(.up)), 1)
    }

    /// The tiles that fall inside `windowMs`; `nil` when the clip is entirely
    /// outside it. At full zoom-in a clip is hundreds of tiles wide, and only
    /// these are ever created or fetched.
    private var visibleTiles: ClosedRange<Int>? {
        let tileMs = Double(rowHeight) / pxPerMs
        let start = layer.timing.start
        let first = max(Int(((windowMs.lowerBound - start) / tileMs).rounded(.down)), 0)
        let last = min(Int(((windowMs.upperBound - start) / tileMs).rounded(.up)), tileCount - 1)
        return first <= last ? first...last : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                if let tiles = visibleTiles {
                    Color.clear.frame(width: CGFloat(tiles.lowerBound) * rowHeight, height: rowHeight)
                    ForEach(tiles, id: \.self) { index in
                        FilmstripTileView(image: tileImages[index])
                            .frame(width: tileWidth(index), height: rowHeight)
                            .clipped()
                    }
                }
            }

            if let audioURL {
                WaveformStripView(audioURL: audioURL, pointCount: min(max(Int(clipWidth / 8), 1), 1500))
                    .frame(height: 16)
                    .background(Color.black.opacity(0.4))
            }
        }
        .frame(width: clipWidth, height: rowHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        // No default border — a plain color block/filmstrip is the resting
        // state (confirmed against a CapCut reference screenshot
        // 2026-10-08). Selection is communicated by the handles plus this
        // thin gray frame connecting them (iOS Photos trim style, added
        // 2026-10-08, replacing the earlier plain white wash).
        .overlay(isSelected ? RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(white: 0.2), lineWidth: selectionBorderWidth) : nil)
        .overlay(alignment: .leading) {
            if isSelected {
                TrimHandleView(rowHeight: rowHeight, corners: [.topLeft, .bottomLeft], edge: .leading).gesture(leftHandleDrag)
            }
        }
        .overlay(alignment: .trailing) {
            if isSelected {
                TrimHandleView(rowHeight: rowHeight, corners: [.topRight, .bottomRight], edge: .trailing).gesture(rightHandleDrag)
            }
        }
        .offset(x: CGFloat(layer.timing.start) * pxPerMs)
        // Boosts the selected clip (and its handles) above neighboring
        // clips in the shared lane ZStack so a drag never gets visually
        // occluded by the clip next door (2026-10-08 fix).
        .zIndex(isSelected ? 1 : 0)
        .task(id: isSelected) {
            guard isSelected, let assetURL else { return }
            assetDurationMs = await AssetDurationCache.shared.durationMs(url: assetURL)
        }
        // Batches every tile's thumbnail in one `generateCGImagesAsynchronously`
        // call (see `VideoFrameCache.filmstripImages`) instead of each tile
        // firing its own request — keyed on `assetId`/`tileCount` so a trim
        // that changes the clip's own width re-fetches the (now different)
        // tile times, but ordinary re-renders (e.g. selection toggling)
        // don't re-trigger it. Consumes the stream tile-by-tile (not one
        // final collected dictionary) so tiles fill in as each decode
        // actually finishes, not all at once after the whole batch settles.
        .task(id: FilmstripWindowKey(layout: batchKey, tiles: visibleTiles)) {
            guard let assetId, let assetURL, let tiles = visibleTiles else { return }
            // Debounced: while a pinch is in progress `tileCount` changes on
            // every frame, and each change restarts this task — only the
            // value the zoom settles on should trigger a thumbnail batch.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            if imagesLayout != batchKey {
                tileImages = [:]
                imagesLayout = batchKey
            }
            let keep = (tiles.lowerBound - tileRetention)...(tiles.upperBound + tileRetention)
            tileImages = tileImages.filter { keep.contains($0.key) }
            let missing = tiles.filter { tileImages[$0] == nil }
            guard !missing.isEmpty else { return }
            let times = missing.map(tileSeconds)
            for await (offset, image) in VideoFrameCache.shared.filmstripImages(assetId: assetId, url: assetURL, times: times) {
                if let image { tileImages[missing[offset]] = image }
            }
        }
    }

    /// Left handle: moves the clip's own *start* while its end stays fixed
    /// — except a video is always on a push-lane, so the "fixed end" is
    /// only as fixed as the ripple reflow allows (see `reflowLane(...)`'s
    /// own doc comment on the 0-floor clamp): if cascading the push
    /// backward would send the lane's first clip below `0`, the resolved
    /// start snaps back toward the original, which is also why the final
    /// `trimStart`/`duration` are derived from the *resolved* start (the
    /// actual applied delta), not the raw requested one.
    private var leftHandleDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartLayer == nil {
                    dragStartLayer = layer
                    onTrimBegin()
                }
                guard let original = dragStartLayer else { return }
                let deltaMs = Double(value.translation.width) / pxPerMs
                let originalEnd = original.timing.start + original.timing.duration

                var candidateStart: Double
                if case .video(let payload) = original.payload {
                    let originalTrimStart = payload.trimStart ?? 0
                    let clampedTrimStart = max(originalTrimStart + deltaMs, 0)
                    candidateStart = original.timing.start + (clampedTrimStart - originalTrimStart)
                } else {
                    candidateStart = original.timing.start + deltaMs
                }
                candidateStart = max(candidateStart, 0)

                let (resolvedStart, siblingStarts) = reflowLane(
                    laneClips: laneClips,
                    draggedLayerId: original.id,
                    newDraggedStart: candidateStart,
                    newDraggedDuration: originalEnd - candidateStart
                )
                let appliedDelta = resolvedStart - original.timing.start
                let newDuration = originalEnd - resolvedStart
                guard newDuration >= minDurationMs else { return }

                var newTrimStart: Double?
                var newTrimEnd: Double?
                if case .video(let payload) = original.payload {
                    newTrimStart = max((payload.trimStart ?? 0) + appliedDelta, 0)
                    newTrimEnd = payload.trimEnd
                }
                onTrimUpdate(TrimClipCommand(layerId: original.id, start: resolvedStart, duration: newDuration, trimStart: newTrimStart, trimEnd: newTrimEnd, siblingStarts: siblingStarts))
            }
            .onEnded { _ in
                dragStartLayer = nil
                onTrimEnd()
            }
    }

    /// Right handle: moves the clip's own *end*, start stays fixed (a
    /// video is the dragged clip on its own push-lane, and extending
    /// rightward always has room — time has no upper bound — so the
    /// start-side of the reflow never needs the 0-floor clamp the left
    /// handle does). Dragging right extends (reveals later source
    /// footage, clamped to the asset's own real duration once known, and
    /// pushes every later clip in the lane later by the same amount);
    /// dragging left shrinks (and pulls every later clip back closer).
    private var rightHandleDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartLayer == nil {
                    dragStartLayer = layer
                    onTrimBegin()
                }
                guard let original = dragStartLayer else { return }
                let deltaMs = Double(value.translation.width) / pxPerMs

                var newTrimEnd: Double?
                var candidateDuration: Double
                if case .video(let payload) = original.payload {
                    let originalTrimEnd = payload.trimEnd ?? ((payload.trimStart ?? 0) + original.timing.duration)
                    var clampedTrimEnd = originalTrimEnd + deltaMs
                    if let assetDurationMs { clampedTrimEnd = min(clampedTrimEnd, assetDurationMs) }
                    newTrimEnd = clampedTrimEnd
                    candidateDuration = original.timing.duration + (clampedTrimEnd - originalTrimEnd)
                } else {
                    candidateDuration = original.timing.duration + deltaMs
                }
                guard candidateDuration >= minDurationMs else { return }

                let (resolvedStart, siblingStarts) = reflowLane(
                    laneClips: laneClips,
                    draggedLayerId: original.id,
                    newDraggedStart: original.timing.start,
                    newDraggedDuration: candidateDuration
                )

                var newTrimStart: Double?
                if case .video(let payload) = original.payload { newTrimStart = payload.trimStart }
                onTrimUpdate(TrimClipCommand(layerId: original.id, start: resolvedStart, duration: candidateDuration, trimStart: newTrimStart, trimEnd: newTrimEnd, siblingStarts: siblingStarts))
            }
            .onEnded { _ in
                dragStartLayer = nil
                onTrimEnd()
            }
    }

    private var batchKey: FilmstripBatchKey {
        let mapping = VideoTimeMapping(layer: layer)
        return FilmstripBatchKey(assetId: assetId, tileCount: tileCount, trimStartMs: mapping?.trimStartMs, rate: mapping?.rate)
    }

    private func tileWidth(_ index: Int) -> CGFloat {
        let start = CGFloat(index) * rowHeight
        return min(rowHeight, clipWidth - start)
    }

    /// Source time (inside the asset file) shown at this tile's left edge —
    /// not timeline time, which ignored `trimStart` and showed the wrong
    /// footage for trimmed clips or any clip not starting at source 0.
    private func tileSeconds(_ index: Int) -> Double {
        let localMs = Double(index) * Double(rowHeight) / pxPerMs
        let timelineMs = layer.timing.start + localMs
        return (VideoTimeMapping(layer: layer)?.sourceMs(atTimelineMs: timelineMs) ?? timelineMs) / 1000
    }

}

/// Drag-to-trim handle — restyled 2026-10-08 to match the iOS Photos app's
/// own video-trim control (a dark gray block spanning the full track
/// height, two thin white grip lines, rounded only on its outer corner) in
/// place of the earlier CapCut-style free-floating white bar. Lives inside
/// a wider invisible tappable area (so a finger doesn't have to land
/// pixel-perfectly on the visible block to grab it), used by both
/// `FilmstripClipView` and `TimelineClipView` whenever a clip is selected.
private struct TrimHandleView: View {
    let rowHeight: CGFloat
    /// Which outer corners get rounded — only the edge facing away from the
    /// clip (Photos' handles are flush/square against the selection body so
    /// the connecting top/bottom border reads as one continuous frame).
    let corners: UIRectCorner
    /// Which edge of the clip this handle sits on — used to straddle the
    /// clip's own boundary (half the hit area inside, half outside) instead
    /// of sitting flush against it. `.overlay(alignment: .leading/.trailing)`
    /// on its own anchors the handle's *own* edge to the clip's edge, which
    /// leaves the whole handle sitting fully inside the clip body — not a
    /// real bug in logic, but a real visual miss versus CapCut/Photos, where
    /// the handle visibly grips the cut line itself (caught from a
    /// screenshot 2026-10-08, fixed with this self-offset rather than
    /// requiring every call site to remember it).
    let edge: HorizontalEdge
    private let visibleWidth: CGFloat = 14
    private let hitWidth: CGFloat = 28
    private let gripColor = Color.white.opacity(0.85)
    /// Matches the selection bounding frame's own visible height
    /// (`rowHeight + selectionBorderWidth` — see that constant's doc
    /// comment), not just the bare clip height, so the handle reads as
    /// part of the same block as the frame instead of looking shorter.
    private var handleHeight: CGFloat { rowHeight + selectionBorderWidth }

    var body: some View {
        RoundedCornerShape(radius: 6, corners: corners)
            .fill(Color(white: 0.2))
            .overlay(gripLine)
            .frame(width: visibleWidth, height: handleHeight)
            .frame(width: hitWidth, height: handleHeight)
            .contentShape(Rectangle())
            .offset(x: edge == .leading ? -hitWidth / 2 : hitWidth / 2)
    }

    private var gripLine: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(gripColor)
            .frame(width: 2, height: handleHeight * 0.35)
    }
}

/// A rectangle rounded on only a chosen subset of its corners — SwiftUI has
/// no built-in for this (`RoundedRectangle` always rounds all four), needed
/// so `TrimHandleView` can round just its outer edge.
private struct RoundedCornerShape: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

/// A lane whose clips must never show a gap — the main video/image track
/// (confirmed with the user 2026-10-08): trimming one clip's edge here
/// *pushes* (or, when shrinking, *pulls*) every other clip in the lane to
/// stay glued, rather than stopping cold at the neighbor the way a text/
/// overlay lane does. Lanes are homogeneous by type (see this file's top
/// doc comment), so checking the dragged layer's own type is enough —
/// no need to inspect siblings.
func isPushLaneType(_ type: String) -> Bool {
    type == "video" || type == "image"
}

/// The "ripple reflow" — given a push-lane's clips in their *current*
/// (pre-this-tick) form and one clip's freshly-dragged `start`/`duration`,
/// computes the `timing.start` every *other* clip in the lane must adopt
/// to stay glued to the dragged clip with zero gaps/overlap, cascading
/// outward in both directions (not just the immediate neighbor) — e.g.
/// extending clip A rightward pushes B later, which in turn pushes C
/// later, and so on down the lane; shrinking A instead *pulls* B (and C,
/// D, ...) back closer. Only positions move; every sibling keeps its own
/// `timing.duration` untouched — matches the user's own framing ("B chỉ
/// đang kéo dài duration, C và D mới là clip bị đẩy").
///
/// **Clamped at the lane's own leading edge**: if cascading backward would
/// push the lane's first clip below `0`, the deficit is applied back onto
/// the dragged clip's own resolved `start` instead — this is what makes a
/// clip that already has another clip packed tight in front of it refuse
/// to extend further left (there's no slack to push into without going
/// negative), while a clip with no clip before it (or genuine slack) can
/// still extend freely down to its own floor.
func reflowLane(
    laneClips: [V2Layer],
    draggedLayerId: String,
    newDraggedStart: Double,
    newDraggedDuration: Double
) -> (draggedStart: Double, siblingStarts: [String: Double]) {
    let ordered = laneClips.sorted { $0.timing.start < $1.timing.start }
    guard let draggedIndex = ordered.firstIndex(where: { $0.id == draggedLayerId }) else {
        return (newDraggedStart, [:])
    }

    var starts: [String: Double] = [draggedLayerId: newDraggedStart]

    var previousEnd = newDraggedStart + newDraggedDuration
    for layer in ordered[(draggedIndex + 1)...] {
        starts[layer.id] = previousEnd
        previousEnd += layer.timing.duration
    }

    var nextStart = newDraggedStart
    for layer in ordered[..<draggedIndex].reversed() {
        nextStart -= layer.timing.duration
        starts[layer.id] = nextStart
    }

    if let firstId = ordered.first?.id, let leadingStart = starts[firstId], leadingStart < 0 {
        let deficit = -leadingStart
        for key in starts.keys { starts[key, default: 0] += deficit }
    }

    let resolvedDraggedStart = starts[draggedLayerId] ?? newDraggedStart
    var siblingStarts = starts
    siblingStarts.removeValue(forKey: draggedLayerId)
    return (resolvedDraggedStart, siblingStarts)
}

/// Stop-lane clamp (text/overlay — gaps are allowed here, so a drag never
/// pushes a neighbor, it just can't cross it): the latest end any clip
/// before `layerId`, in time order, reaches — `nil` if there isn't one.
func previousClipEnd(in laneClips: [V2Layer], before layerId: String, originalStart: Double) -> Double? {
    laneClips
        .filter { $0.id != layerId && $0.timing.start < originalStart }
        .map { $0.timing.start + $0.timing.duration }
        .max()
}

/// Stop-lane clamp's mirror — the earliest start any clip after `layerId`
/// reaches — `nil` if there isn't one.
func nextClipStart(in laneClips: [V2Layer], after layerId: String, originalStart: Double) -> Double? {
    laneClips
        .filter { $0.id != layerId && $0.timing.start > originalStart }
        .map(\.timing.start)
        .min()
}

/// Pure display — the image it shows is fetched upstream by
/// `FilmstripClipView`'s own batch request (`VideoFrameCache.filmstripImages`),
/// not by this view itself; a `nil` image (not yet arrived, or the batch
/// request failed) just shows the gray placeholder.
private struct FilmstripTileView: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.gray.opacity(0.3)
        }
    }
}

/// `.task(id:)` key for `FilmstripClipView`'s batch thumbnail fetch —
/// re-fetches only when the tiles' *source* times change: a different
/// asset, tile count (the clip got wider/narrower), `trimStart` (a left
/// trim shifts which footage every tile shows) or rate. Deliberately not
/// keyed on `timing.start`: a ripple push moves the clip on the timeline
/// without changing what any tile shows.
private struct FilmstripBatchKey: Equatable {
    let assetId: String?
    let tileCount: Int
    let trimStartMs: Double?
    let rate: Double?
}

/// `FilmstripClipView`'s fetch key: the layout plus which tiles are in the
/// window, so scrolling re-fetches only when the window actually moves.
private struct FilmstripWindowKey: Equatable {
    let layout: FilmstripBatchKey
    let tiles: ClosedRange<Int>?
}

/// Loads a file's full-waveform envelope (`WaveformCache`, decoded once per
/// URL) and resamples it down to however many points this clip's own pixel
/// width calls for. Doesn't yet account for `trimStart`/`trimEnd` — this
/// first pass always shows the *whole* derivative file stretched across the
/// clip, a known simplification (see `CLAUDE.md`'s audio design note).
private struct WaveformStripView: View {
    let audioURL: URL
    let pointCount: Int
    var color: Color = .white.opacity(0.85)

    @State private var samples: [Float] = []

    var body: some View {
        WaveformCurveView(samples: samples, color: color)
            .task(id: audioURL) {
                guard let full = await WaveformCache.shared.samples(url: audioURL) else { return }
                samples = resample(full, to: pointCount)
            }
    }

    private func resample(_ source: [Float], to count: Int) -> [Float] {
        guard count > 0, !source.isEmpty else { return [] }
        return (0..<count).map { i in
            let index = min(Int(Double(i) / Double(count) * Double(source.count)), source.count - 1)
            return source[index]
        }
    }
}

/// A smooth, one-sided amplitude graph — a real curve through each sample
/// (Catmull-Rom spline converted to cubic Bezier segments, the standard way
/// to pass a smooth curve through an ordered point sequence without
/// overshooting wildly), with the area beneath it filled, not discrete
/// bars. Anchored at its own bottom edge (amplitude 0 → baseline) rather
/// than mirrored around a center line — confirmed with the user
/// 2026-10-08 specifically because these rows are short (22-26pt): a
/// symmetric wave would halve the usable height for no benefit once
/// there's no bar-separated look to preserve.
private struct WaveformCurveView: View {
    let samples: [Float]
    var color: Color = .white.opacity(0.85)

    /// The loudest peak only reaches this fraction of the available
    /// height, not the full 100% — matching how other video/audio editors
    /// render waveforms (confirmed with the user 2026-10-08): full-height
    /// peaks read as "clipping" against the row's own top edge, especially
    /// for already-loud/compressed source audio (a real, common case, not
    /// an edge case) where most of the clip would otherwise sit flush
    /// against the top the whole time.
    private let peakFraction: CGFloat = 0.8

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let points = samples.enumerated().map { index, amplitude -> CGPoint in
                let x = CGFloat(index) / CGFloat(samples.count - 1) * size.width
                let y = size.height - CGFloat(amplitude) * size.height * peakFraction
                return CGPoint(x: x, y: y)
            }

            var fillPath = smoothPath(through: points)
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(color.opacity(0.35)))
            context.stroke(smoothPath(through: points), with: .color(color), lineWidth: 1.5)
        }
    }

    /// Catmull-Rom → Bezier: for each segment `p1`→`p2`, the neighboring
    /// points `p0`/`p3` (clamped to the array's own ends) shape control
    /// points so the curve flows smoothly through every sample instead of
    /// just connecting them with straight lines.
    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 0..<(points.count - 1) {
            let p0 = i == 0 ? points[i] : points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

/// One clip block — a flat, color-keyed rectangle positioned/sized by the
/// layer's own timing. Still used for every non-video row (video rows use
/// `FilmstripClipView` instead — see this file's top doc comment).
private struct TimelineClipView: View {
    let layer: V2Layer
    /// The whole lane's clips (including this one), read fresh every
    /// render — only actually needed when `layer.type` is a push-lane type
    /// (`isPushLaneType(_:)`, i.e. "image"; "video" always uses
    /// `FilmstripClipView` instead) — a text/shape clip ignores this and
    /// hard-clamps against its immediate neighbor instead.
    let laneClips: [V2Layer]
    let pxPerMs: Double
    let rowHeight: CGFloat
    let isSelected: Bool
    let onTrimBegin: () -> Void
    let onTrimUpdate: (EditorCommand) -> Void
    let onTrimEnd: () -> Void

    /// Same fixed-origin-per-gesture pattern as `FilmstripClipView`'s own
    /// drag handles — see its doc comment.
    @State private var dragStartLayer: V2Layer?
    private let minDurationMs: Double = 200

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            // A solid color block, not a translucent tint + stroke — matches
            // the reference CapCut screenshot's flat text/audio blocks
            // (confirmed with the user 2026-10-08, same change as removing
            // `FilmstripClipView`'s permanent blue border). No type-color
            // stroke anymore either; the type is communicated by the fill
            // + icon/label alone.
            .fill(color)
            .overlay(isSelected ? RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(white: 0.2), lineWidth: selectionBorderWidth) : nil)
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                    Text(layer.type.capitalized)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    TrimHandleView(rowHeight: rowHeight, corners: [.topLeft, .bottomLeft], edge: .leading).gesture(leftHandleDrag)
                }
            }
            .overlay(alignment: .trailing) {
                if isSelected {
                    TrimHandleView(rowHeight: rowHeight, corners: [.topRight, .bottomRight], edge: .trailing).gesture(rightHandleDrag)
                }
            }
            .frame(width: max(CGFloat(layer.timing.duration) * pxPerMs, 28), height: rowHeight)
            .offset(x: CGFloat(layer.timing.start) * pxPerMs)
            .zIndex(isSelected ? 1 : 0)
    }

    /// No asset/`trimStart`/`trimEnd` concept for a non-video layer — a
    /// text/image/shape clip's "footage" is just its own authored time
    /// range, so extending either handle has no asset-duration ceiling the
    /// way `FilmstripClipView`'s right handle has. Two different floors,
    /// though (confirmed with the user 2026-10-08): on a push-lane
    /// (`isPushLaneType` — "image", sharing the main track's "never a gap"
    /// rule with video), extending ripples/pulls every other clip in the
    /// lane via `reflowLane(...)`, same as `FilmstripClipView`. On a
    /// stop-lane (text etc., where gaps are allowed), extending just
    /// hard-clamps at whichever neighbor is in the way — nothing else ever
    /// moves.
    private var leftHandleDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartLayer == nil {
                    dragStartLayer = layer
                    onTrimBegin()
                }
                guard let original = dragStartLayer else { return }
                let deltaMs = Double(value.translation.width) / pxPerMs
                let originalEnd = original.timing.start + original.timing.duration
                var candidateStart = max(original.timing.start + deltaMs, 0)

                var siblingStarts: [String: Double] = [:]
                var resolvedStart = candidateStart
                if isPushLaneType(original.type) {
                    let result = reflowLane(
                        laneClips: laneClips,
                        draggedLayerId: original.id,
                        newDraggedStart: candidateStart,
                        newDraggedDuration: originalEnd - candidateStart
                    )
                    resolvedStart = result.draggedStart
                    siblingStarts = result.siblingStarts
                } else if let floor = previousClipEnd(in: laneClips, before: original.id, originalStart: original.timing.start) {
                    candidateStart = max(candidateStart, floor)
                    resolvedStart = candidateStart
                }

                let newDuration = originalEnd - resolvedStart
                guard newDuration >= minDurationMs else { return }
                onTrimUpdate(TrimClipCommand(layerId: original.id, start: resolvedStart, duration: newDuration, trimStart: nil, trimEnd: nil, siblingStarts: siblingStarts))
            }
            .onEnded { _ in
                dragStartLayer = nil
                onTrimEnd()
            }
    }

    private var rightHandleDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartLayer == nil {
                    dragStartLayer = layer
                    onTrimBegin()
                }
                guard let original = dragStartLayer else { return }
                let deltaMs = Double(value.translation.width) / pxPerMs
                var candidateDuration = original.timing.duration + deltaMs

                var siblingStarts: [String: Double] = [:]
                var resolvedStart = original.timing.start
                if isPushLaneType(original.type) {
                    let result = reflowLane(
                        laneClips: laneClips,
                        draggedLayerId: original.id,
                        newDraggedStart: original.timing.start,
                        newDraggedDuration: candidateDuration
                    )
                    resolvedStart = result.draggedStart
                    siblingStarts = result.siblingStarts
                } else if let ceiling = nextClipStart(in: laneClips, after: original.id, originalStart: original.timing.start) {
                    candidateDuration = min(candidateDuration, ceiling - original.timing.start)
                }

                guard candidateDuration >= minDurationMs else { return }
                onTrimUpdate(TrimClipCommand(layerId: original.id, start: resolvedStart, duration: candidateDuration, trimStart: nil, trimEnd: nil, siblingStarts: siblingStarts))
            }
            .onEnded { _ in
                dragStartLayer = nil
                onTrimEnd()
            }
    }

    private var color: Color {
        switch layer.type {
        case "video": return .blue
        case "image": return .green
        case "text": return .orange
        case "audio": return .cyan
        case "shape", "path": return .pink
        default: return .gray
        }
    }

    private var icon: String {
        switch layer.type {
        case "video": return "video.fill"
        case "image": return "photo.fill"
        case "text": return "textformat"
        case "audio": return "waveform"
        case "shape", "path": return "square.on.circle"
        default: return "square"
        }
    }
}
