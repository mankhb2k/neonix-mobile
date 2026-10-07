import SwiftUI

/// Timeline panel below Stage/Titlebar: a time ruler, one row per non-
/// `"group"` layer, and a **fixed, horizontally-centered playhead** —
/// matching CapCut's own interaction model, not a moving-line-over-static-
/// track design. Dragging anywhere in the panel shifts the whole ruler+
/// track content left/right underneath the fixed playhead line; whatever
/// frame lands under it becomes `currentTimeMs`. The video row renders as a
/// real filmstrip (`FilmstripClipView`), prefixed with a mute button + cover
/// cell (`FilmstripRowView`) that scroll along with it as ordinary content —
/// only the playhead line itself is a fixed overlay. Every other row stays
/// the flat color block (`TimelineClipView`) — no thumbnail concept applies
/// to text/audio/shape layers. See `ui-design-note.md` (repo root) for the
/// full design discussion this was built from.
struct TimelineView: View {
    let layers: [V2Layer]
    let assets: [V2Asset]
    @Binding var currentTimeMs: Double
    let maxDurationMs: Double
    let onScrub: () -> Void

    private let pxPerMs: Double = 0.2
    private let rowHeight: CGFloat = 40
    private let rowSpacing: CGFloat = 6
    private let rulerHeight: CGFloat = 20
    private let rowsTopPadding: CGFloat = 6

    /// Snapshot of `currentTimeMs` taken when a drag begins, so each
    /// `onChanged` computes an absolute new time from the gesture's total
    /// translation (not an incremental delta, which would drift if SwiftUI
    /// ever redelivers a `DragGesture` from a fresh zero translation).
    @State private var dragStartTimeMs: Double?
    /// Placeholder toggle — this editor doesn't play real audio at all yet
    /// (see `VideoFrameCache`'s doc comment: preview is driven by a custom
    /// clock, not `AVPlayer` playback), so there's nothing to actually mute.
    /// Wiring this to `V2VideoPayload.audio.enabled` is future work once a
    /// real audio engine exists.
    @State private var isMuted = false
    @State private var coverImage: UIImage?

    private var tracks: [V2Layer] {
        layers.filter { $0.type != "group" }.sorted { $0.order < $1.order }
    }

    private var videoRowIndex: Int? {
        tracks.firstIndex { $0.type == "video" }
    }

    private var contentWidth: CGFloat {
        max(CGFloat(maxDurationMs) * pxPerMs, 1)
    }

    private var tracksHeight: CGFloat {
        CGFloat(max(tracks.count, 1)) * rowHeight + CGFloat(max(tracks.count - 1, 0)) * rowSpacing
    }

    private var panelHeight: CGFloat {
        rulerHeight + rowsTopPadding + tracksHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let centerX = geo.size.width / 2
                let contentOffsetX = centerX - CGFloat(currentTimeMs) * pxPerMs
                let visibleLower = CGFloat(currentTimeMs) * pxPerMs - Double(centerX)
                let visibleRange: ClosedRange<Double> = visibleLower...(visibleLower + Double(geo.size.width))

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: rowsTopPadding) {
                        TimeRulerView(pxPerMs: pxPerMs, maxDurationMs: maxDurationMs, contentWidth: contentWidth)
                            .frame(height: rulerHeight)

                        VStack(alignment: .leading, spacing: rowSpacing) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, layer in
                                if layer.type == "video" {
                                    FilmstripRowView(
                                        layer: layer,
                                        assetId: assetId(for: layer),
                                        assetURL: assetURL(for: layer),
                                        pxPerMs: pxPerMs,
                                        rowHeight: rowHeight,
                                        visibleRange: visibleRange,
                                        showsCoverAndMute: index == videoRowIndex,
                                        coverImage: coverImage,
                                        isMuted: isMuted,
                                        onToggleMute: { isMuted.toggle() }
                                    )
                                } else {
                                    TimelineClipView(layer: layer, pxPerMs: pxPerMs, rowHeight: rowHeight)
                                }
                            }
                        }
                    }
                    .offset(x: contentOffsetX)
                    .frame(width: geo.size.width, height: panelHeight, alignment: .topLeading)
                    .clipped()

                    // Only the playhead itself stays fixed — the cover cell
                    // and mute button scroll together with the filmstrip as
                    // ordinary content now (see `FilmstripRowView`), not a
                    // separate always-on-top overlay.
                    PlayheadOverlay(centerX: centerX, totalHeight: panelHeight)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            onScrub()
                            let start = dragStartTimeMs ?? currentTimeMs
                            if dragStartTimeMs == nil { dragStartTimeMs = currentTimeMs }
                            let proposed = start - Double(value.translation.width) / pxPerMs
                            currentTimeMs = min(max(proposed, 0), maxDurationMs)
                        }
                        .onEnded { _ in dragStartTimeMs = nil }
                )
            }
            .frame(height: panelHeight)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .task(id: coverAssetKey) {
            await loadCoverImage()
        }
    }

    private var coverAssetKey: String? {
        guard let videoRowIndex else { return nil }
        return assetId(for: tracks[videoRowIndex])
    }

    private func loadCoverImage() async {
        guard let videoRowIndex else { return }
        let layer = tracks[videoRowIndex]
        guard let assetId = assetId(for: layer), let url = assetURL(for: layer) else { return }
        coverImage = await VideoFrameCache.shared.frame(assetId: assetId, url: url, atSeconds: layer.timing.start / 1000)
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

/// The video track's full row: mute button + cover-image cell (only on the
/// primary video row, `showsCoverAndMute`) immediately followed by the
/// filmstrip, all in one `HStack` so they scroll together as ordinary
/// content — not a fixed overlay (see `ui-design-note.md`'s 2026-10-07
/// entry on this reversal). One outer offset positions the whole row so the
/// filmstrip's own first tile still lands exactly at `layer.timing.start`,
/// matching every other track's positioning — the mute/cover cells just
/// occupy the extra space immediately before that point.
private struct FilmstripRowView: View {
    let layer: V2Layer
    let assetId: String?
    let assetURL: URL?
    let pxPerMs: Double
    let rowHeight: CGFloat
    let visibleRange: ClosedRange<Double>
    let showsCoverAndMute: Bool
    let coverImage: UIImage?
    let isMuted: Bool
    let onToggleMute: () -> Void

    private let prefixSpacing: CGFloat = 6

    private var prefixWidth: CGFloat {
        showsCoverAndMute ? 2 * rowHeight + 2 * prefixSpacing : 0
    }

    var body: some View {
        HStack(spacing: prefixSpacing) {
            if showsCoverAndMute {
                MuteButtonCell(rowHeight: rowHeight, isMuted: isMuted, onToggleMute: onToggleMute)
                CoverCell(rowHeight: rowHeight, coverImage: coverImage)
            }
            FilmstripClipView(
                layer: layer,
                assetId: assetId,
                assetURL: assetURL,
                pxPerMs: pxPerMs,
                rowHeight: rowHeight,
                visibleRange: visibleRange
            )
        }
        .offset(x: CGFloat(layer.timing.start) * pxPerMs - prefixWidth)
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
    let maxDurationMs: Double
    let contentWidth: CGFloat

    private let minorIntervalMs: Double = 1000
    private let majorIntervalMs: Double = 2000

    var body: some View {
        Canvas { context, size in
            var ms: Double = 0
            while ms <= maxDurationMs {
                let x = CGFloat(ms) * pxPerMs
                let isMajor = Int(ms) % Int(majorIntervalMs) == 0
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
                        Text(formattedTime(ms)).font(.caption2).foregroundColor(.secondary),
                        at: CGPoint(x: x + 2, y: size.height / 2 - 6),
                        anchor: .leading
                    )
                }
                ms += minorIntervalMs
            }
        }
        .frame(width: contentWidth)
    }

    private func formattedTime(_ ms: Double) -> String {
        let totalSeconds = Int(ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// A video track's clip, rendered as a real filmstrip — one square tile per
/// `rowHeight`-wide slice of the clip, each showing the actual decoded
/// frame at that point (reusing `VideoFrameCache`, the same cache
/// `PreviewCanvas` uses for scrub frames — no new decode path). Tiles
/// outside `visibleRange` stay a plain gray placeholder and never trigger a
/// decode, so the filmstrip can be arbitrarily long without decoding frames
/// that are off-screen.
private struct FilmstripClipView: View {
    let layer: V2Layer
    let assetId: String?
    let assetURL: URL?
    let pxPerMs: Double
    let rowHeight: CGFloat
    let visibleRange: ClosedRange<Double>

    private var clipWidth: CGFloat {
        max(CGFloat(layer.timing.duration) * pxPerMs, 28)
    }

    private var tileCount: Int {
        max(Int((clipWidth / rowHeight).rounded(.up)), 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tileCount, id: \.self) { index in
                FilmstripTileView(
                    assetId: assetId,
                    assetURL: assetURL,
                    atSeconds: tileSeconds(index),
                    isVisible: isTileVisible(index)
                )
                .frame(width: tileWidth(index), height: rowHeight)
                .clipped()
            }
        }
        .frame(width: clipWidth, height: rowHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.blue, lineWidth: 1))
    }

    private func tileWidth(_ index: Int) -> CGFloat {
        let start = CGFloat(index) * rowHeight
        return min(rowHeight, clipWidth - start)
    }

    private func tileSeconds(_ index: Int) -> Double {
        let localMs = Double(index) * Double(rowHeight) / pxPerMs
        return (layer.timing.start + min(localMs, layer.timing.duration)) / 1000
    }

    private func isTileVisible(_ index: Int) -> Bool {
        let tileStartX = layer.timing.start * pxPerMs + Double(index) * Double(rowHeight)
        let tileRange = tileStartX...(tileStartX + Double(rowHeight))
        return tileRange.overlaps(visibleRange)
    }
}

private struct FilmstripTileView: View {
    let assetId: String?
    let assetURL: URL?
    let atSeconds: Double
    let isVisible: Bool

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .task(id: isVisible) {
            guard isVisible, image == nil, let assetId, let assetURL else { return }
            image = await VideoFrameCache.shared.frame(assetId: assetId, url: assetURL, atSeconds: atSeconds)
        }
    }
}

/// One clip block — a flat, color-keyed rectangle positioned/sized by the
/// layer's own timing. Still used for every non-video row (video rows use
/// `FilmstripClipView` instead — see this file's top doc comment).
private struct TimelineClipView: View {
    let layer: V2Layer
    let pxPerMs: Double
    let rowHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 1))
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                    Text(layer.type.capitalized)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(color)
                .padding(.horizontal, 6)
            }
            .frame(width: max(CGFloat(layer.timing.duration) * pxPerMs, 28), height: rowHeight)
            .offset(x: CGFloat(layer.timing.start) * pxPerMs)
    }

    private var color: Color {
        switch layer.type {
        case "video": return .blue
        case "image": return .green
        case "text": return .orange
        case "audio": return .purple
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
