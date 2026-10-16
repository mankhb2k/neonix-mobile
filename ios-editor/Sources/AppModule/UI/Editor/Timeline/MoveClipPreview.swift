import SwiftUI

/// The pictures on the floating copy of a lifted overlay clip (video filmstrip or photo tiles), like the clip shows on the timeline.
/// Cheap by design: it only reads what the timeline already made (`VideoFrameCache.baseThumbs`, `PhotoThumbnailCache`) - no
/// decoding, no detail frames, no duration load - and draws at most `maxWidth` pt from the clip's start, rasterised once
/// (`drawingGroup`) so the drag only moves a finished layer. Until a picture exists the flat colour under it shows.
struct MoveClipPreview: View {
    let layer: V2Layer
    let assetId: String?
    let assetURL: URL?
    let pxPerMs: Double
    let rowHeight: CGFloat
    /// The clip's full width on screen; the pictures stop at `maxWidth` of it.
    let clipWidth: CGFloat
    static let maxWidth: CGFloat = 1200

    @State private var photoTile: UIImage?

    private var width: CGFloat { min(clipWidth, Self.maxWidth) }

    var body: some View {
        Group {
            if layer.type == "video" {
                filmstrip
            } else {
                photo
            }
        }
        .frame(width: width, height: rowHeight, alignment: .leading)
        .clipped()
        .drawingGroup()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var filmstrip: some View {
        let mapping = VideoTimeMapping(layer: layer)
        let rate = mapping?.rate ?? 1
        let trimStartPx = (mapping?.trimStartMs ?? 0) * pxPerMs / rate
        let tileSourceMs = Double(rowHeight) * rate / pxPerMs
        let duration = assetURL.flatMap { AssetDurationCache.shared.cachedDurationMs(url: $0) }
        let baseStep = duration.map(FilmstripGrid.baseStepMs(durationMs:))
        let base = assetId.flatMap { VideoFrameCache.shared.baseThumbs[$0] } ?? [:]
        if let baseStep, !base.isEmpty,
           let tiles = FilmstripGrid.tiles(lower: 0, upper: Double(width), trimStartPx: trimStartPx, tileWidth: Double(rowHeight)) {
            HStack(spacing: 0) {
                ForEach(tiles, id: \.self) { k in
                    let center = Int((Double(k) * tileSourceMs / baseStep).rounded())
                    let image = (0...8).lazy.compactMap { base[center - $0] ?? base[center + $0] }.first
                    Group {
                        if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) } else { Color.clear }
                    }
                    .frame(width: rowHeight, height: rowHeight)
                    .clipped()
                }
            }
            .offset(x: CGFloat(tiles.lowerBound) * rowHeight - CGFloat(trimStartPx))
            .frame(width: width, height: rowHeight, alignment: .leading)
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let photoTile {
            Image(uiImage: photoTile).resizable(resizingMode: .tile)
        } else {
            Color.clear.task(id: assetURL) {
                guard let assetURL else { return }
                photoTile = await PhotoThumbnailCache.tile(for: assetURL, side: rowHeight)   // a cache hit: the timeline built it
            }
        }
    }
}
