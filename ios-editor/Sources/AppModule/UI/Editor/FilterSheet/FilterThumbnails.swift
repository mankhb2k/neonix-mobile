import AVFoundation
import UIKit

/// The small pictures in the Filter grid: the clip's own frame (the one under the playhead, or the photo) run through
/// each preset's real filter chain, so what the grid shows is what the stage will show.
///
/// Kept cheap on purpose (measured with `FilterThumbnailBench`, Debug): the source is **a thumbnail the timeline's filmstrip
/// already made** (`VideoFrameCache.baseThumbs`) instead of a fresh frame decode, it is shrunk to `thumbnailPixels`, the
/// presets of the visible category render first, and results are cached per (source frame, preset).
enum FilterThumbnails {
    /// Longest side of a thumbnail, in pixels (a cell is about 90 pt wide).
    static let thumbnailPixels: CGFloat = 160

    /// The picture the grid is rendered from, and a key that changes whenever the picture does (for the cache).
    struct Source {
        let image: CGImage
        let key: String
    }

    // MARK: Source

    /// A small picture of `layer`: for a video the filmstrip thumbnail nearest the playhead's source time (falling back to a
    /// cached small decode when the filmstrip has not got there yet), for a photo the photo itself.
    @MainActor
    static func source(for layer: V2Layer, project: V2Project, atMs timelineMs: Double) async -> Source? {
        switch layer.payload {
        case .video(let payload):
            guard case .video(let asset)? = project.assets.first(where: { $0.id == payload.assetId }),
                  let url = bundledURL(filename: asset.uri)
            else { return nil }
            let sourceMs = VideoTimeMapping(layer: layer)?.sourceMs(atTimelineMs: timelineMs) ?? payload.trimStart ?? 0
            return await videoSource(assetId: payload.assetId, url: url, sourceMs: max(sourceMs, 0))
        case .image(let payload):
            guard case .image(let asset)? = project.assets.first(where: { $0.id == payload.assetId }),
                  let url = bundledURL(filename: asset.uri),
                  let image = UIImage(contentsOfFile: url.path)?.cgImage
            else { return nil }
            return Source(image: downscaled(image), key: "image:\(payload.assetId)")
        default:
            return nil
        }
    }

    @MainActor
    static func videoSource(assetId: String, url: URL, sourceMs: Double) async -> Source? {
        if let durationMs = await AssetDurationCache.shared.durationMs(url: url),
           let thumbs = VideoFrameCache.shared.baseThumbs[assetId], !thumbs.isEmpty {
            let step = FilmstripGrid.baseStepMs(durationMs: durationMs)
            let wanted = Int((sourceMs / step).rounded())
            if let index = thumbs.keys.min(by: { abs($0 - wanted) < abs($1 - wanted) }), let cg = thumbs[index]?.cgImage {
                return Source(image: downscaled(cg), key: "\(assetId)#\(index)")
            }
        }
        guard let frame = await VideoFrameCache.shared.frame(assetId: assetId, url: url, atSeconds: sourceMs / 1000)?.cgImage else { return nil }
        return Source(image: downscaled(frame), key: "\(assetId)@\(VideoFrameCache.scrubBucket(forMs: sourceMs))")
    }

    /// `image` shrunk so its longest side is at most `thumbnailPixels` (returned as is when already small).
    static func downscaled(_ image: CGImage, maxPixels: CGFloat = thumbnailPixels) -> CGImage {
        let k = min(maxPixels / CGFloat(max(image.width, image.height)), 1)
        guard k < 1 else { return image }
        let width = max(Int((CGFloat(image.width) * k).rounded()), 1), height = max(Int((CGFloat(image.height) * k).rounded()), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: Cache

    /// Rendered thumbnails by "<source key>|<preset id>". Bounded: oldest entries go first.
    @MainActor private static var cache: [String: UIImage] = [:]
    @MainActor private static var cacheOrder: [String] = []
    private static let cacheLimit = 96

    @MainActor
    static func cached(presetId: String, sourceKey: String) -> UIImage? { cache["\(sourceKey)|\(presetId)"] }

    @MainActor
    private static func store(_ image: UIImage, presetId: String, sourceKey: String) {
        let key = "\(sourceKey)|\(presetId)"
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = image
        while cacheOrder.count > cacheLimit { cache[cacheOrder.removeFirst()] = nil }
    }

    @MainActor
    static func clearCache() { cache = [:]; cacheOrder = [] }

    // MARK: Render

    /// Presets in the order a grid wants them: the visible category's first, then the rest.
    static func ordered(for category: FilterCategory) -> [FilterPreset] {
        let first = FilterCatalog.list(in: category)
        return first + FilterCatalog.presets.filter { preset in !first.contains { $0.id == preset.id } }
    }

    /// Renders `presets` on `source` (those already cached are delivered straight away, the rest rendered off the main
    /// actor in the given order), calling `deliver` as each one is ready.
    @MainActor
    static func render(source: Source, presets: [FilterPreset], deliver: @escaping @MainActor (String, UIImage) -> Void) async {
        var missing: [FilterPreset] = []
        for preset in presets {
            if let hit = cached(presetId: preset.id, sourceKey: source.key) { deliver(preset.id, hit) } else { missing.append(preset) }
        }
        let image = source.image, sourceKey = source.key
        // Delivered a row (4) at a time: one hop to the main actor per row instead of per picture (measured on an iPhone 13:
        // the per-picture hops and cache writes were ~25% of the grid's CPU).
        await Task.detached(priority: .userInitiated) {
            var batch: [(String, UIImage)] = []
            func flush() async {
                let ready = batch
                batch = []
                await MainActor.run {
                    for (id, image) in ready {
                        store(image, presetId: id, sourceKey: sourceKey)
                        deliver(id, image)
                    }
                }
            }
            for preset in missing {
                let filter = compileFilter(id: "thumb-\(preset.id)", presets: adjustPresets(for: preset.values))
                guard let rendered = FilterRenderer.apply(filter, to: image) else { continue }
                batch.append((preset.id, UIImage(cgImage: rendered)))
                if batch.count == 4 { await flush() }
            }
            if !batch.isEmpty { await flush() }
        }.value
    }
}
