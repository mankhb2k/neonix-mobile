import AVFoundation
import UIKit

/// Extracts a still frame from a video asset at an arbitrary time, driven by
/// the app's own custom clock (not a separate `AVPlayer` timeline) — see the
/// "Video preview" decision in the editor-document plan: this keeps every
/// layer, shape or video, sampled by the same clock, at the cost of being
/// less smooth than real decoded playback.
///
/// `@MainActor`-isolated so the generator/image dictionaries never need
/// their own locking; `frame(assetId:url:atSeconds:)` is `async` specifically
/// because scrubbing calls this on every slider tick — the old synchronous
/// `copyCGImage(at:)` blocked the main thread (and therefore the SwiftUI
/// render loop) on every single one, which is what made scrubbing feel
/// janky. `await`ing the real async generation API suspends instead of
/// blocking: the actual decode/seek happens off the main thread, and the
/// render loop keeps drawing the previous frame (see `PreviewCanvas.swift`'s
/// `LayerContentView`, which keeps its last `cachedImage` on screen while a
/// new one is still loading) until the new one is ready.
@MainActor
@Observable
final class VideoFrameCache {
    static let shared = VideoFrameCache()

    /// How finely scrubbing resolves to a distinct frame request. Coarser
    /// than real playback framerate on purpose: while dragging, many slider
    /// ticks land in the same bucket and reuse one cached result instead of
    /// triggering a fresh decode each time — human eyes can't tell a ~65ms
    /// (~15fps) scrub resolution from a continuous one anyway.
    static let scrubBucketMs: Double = 65

    @ObservationIgnored private var generators: [String: AVAssetImageGenerator] = [:]
    @ObservationIgnored private var cache: [String: UIImage] = [:]

    /// Base filmstrip thumbnails per source video: index `i` is the frame at source
    /// time `i × FilmstripGrid.baseStepMs`. Belongs to the video, not to a clip, so
    /// trimming, splitting or extending a clip never regenerates anything. Observed:
    /// a clip view re-renders as thumbnails arrive.
    private(set) var baseThumbs: [String: [Int: UIImage]] = [:]
    @ObservationIgnored private var baseRequested: Set<String> = []

    /// Rounds a time to this cache's scrub resolution — also used by
    /// `PreviewCanvas.swift` as a SwiftUI `.task(id:)` key so a new decode
    /// only kicks off when scrubbing actually crosses into a new bucket,
    /// rather than on every sub-bucket layout pass.
    static func scrubBucket(forMs ms: Double) -> Int {
        Int((ms / scrubBucketMs).rounded())
    }

    func frame(assetId: String, url: URL, atSeconds seconds: Double) async -> UIImage? {
        let bucket = Self.scrubBucket(forMs: seconds * 1000)
        let key = "\(assetId):\(bucket)"
        if let cached = cache[key] { return cached }

        let generator = generator(for: assetId, url: url, tier: .stage)
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        let image = UIImage(cgImage: result.image)
        cache[key] = image
        return image
    }

    /// Starts (once per video) the whole-video base filmstrip: one thumbnail every
    /// `FilmstripGrid.baseStepMs`, requested nearest-to-`priorityMs` first so the
    /// part of the video a clip shows fills in before the rest. Results land in
    /// `baseThumbs`. A video whose duration is unknown is skipped.
    func ensureBaseThumbnails(assetId: String, url: URL, durationMs: Double, priorityMs: Double) {
        guard durationMs > 0, !baseRequested.contains(assetId) else { return }
        baseRequested.insert(assetId)
        let step = FilmstripGrid.baseStepMs(durationMs: durationMs)
        let indices = (0...Int(durationMs / step)).sorted {
            abs(Double($0) * step - priorityMs) < abs(Double($1) * step - priorityMs)
        }
        Task {
            let times = indices.map { Double($0) * step / 1000 }
            for await (offset, image) in filmstripImages(assetId: assetId, url: url, times: times, tier: .filmstripBase) {
                if let image { baseThumbs[assetId, default: [:]][indices[offset]] = image }
            }
        }
    }

    /// Batch thumbnail generation — one `generateCGImagesAsynchronously` call for
    /// every time a caller needs (AVFoundation's own API for filmstrips), instead
    /// of one independent `image(at:)` per tile.
    ///
    /// Returns an `AsyncStream` so each `(index, image)` is delivered the moment its
    /// own decode finishes — awaiting the whole batch left the filmstrip blank for
    /// seconds (simulator, 2026-10-08). Keyed by the caller's array index; the
    /// requested `CMTime` echoed back by AVFoundation maps a completion to its
    /// index. Nothing is written to `cache` (an unbounded dictionary of every
    /// thumbnail grew the app from 29 MB to 316 MB in a 115 s run on a phone);
    /// callers keep only what they show.
    ///
    /// Each tier has its own generator, so abandoning a detail batch
    /// (`onTermination` cancels its generator) never cancels the base one.
    func filmstripImages(assetId: String, url: URL, times: [Double], tier: GeneratorTier = .filmstripDetail) -> AsyncStream<(index: Int, image: UIImage?)> {
        AsyncStream { continuation in
            guard !times.isEmpty else {
                continuation.finish()
                return
            }
            let generator = self.generator(for: assetId, url: url, tier: tier)
            let requestTimes = times.map { CMTime(seconds: max($0, 0), preferredTimescale: 600) }
            var indexByKey: [String: Int] = [:]
            for (index, time) in requestTimes.enumerated() {
                indexByKey["\(time.value):\(time.timescale)"] = index
            }
            let remaining = FilmstripRemainingCount(times.count)
            // A batch the caller abandoned (window moved, pinch changed the tile
            // count) must stop decoding: left running it keeps the hardware
            // decoder busy for thumbnails nobody will see.
            continuation.onTermination = { _ in generator.cancelAllCGImageGeneration() }
            generator.generateCGImagesAsynchronously(forTimes: requestTimes.map { NSValue(time: $0) }) { requestedTime, cgImage, _, result, _ in
                guard let index = indexByKey["\(requestedTime.value):\(requestedTime.timescale)"] else { return }
                let image = result == .succeeded ? cgImage.map(UIImage.init(cgImage:)) : nil
                // Not written to `cache`: nothing reads filmstrip thumbnails back
                // from it (only the cover image's `frame(...)` uses it), and an
                // unbounded dictionary of every thumbnail ever fetched grew the
                // app from 29 MB to 316 MB in a 115 s measured run on a phone
                // (T3, real footage, zoom + scrub). `FilmstripClipView` keeps the
                // tiles of the window it is showing.
                continuation.yield((index, image))
                if remaining.decrementAndIsDone() {
                    continuation.finish()
                }
            }
        }
    }

    enum GeneratorTier: String {
        /// Cover and stage stills (`frame(...)`).
        case stage
        /// Whole-video base filmstrip: coarse, so a loose tolerance (nearest
        /// keyframe) keeps it fast.
        case filmstripBase
        /// Window-only detail when zoomed in past the base spacing.
        case filmstripDetail
    }

    private func generator(for assetId: String, url: URL, tier: GeneratorTier) -> AVAssetImageGenerator {
        let key = "\(assetId)#\(tier.rawValue)"
        if let cached = generators[key] { return cached }
        let asset = AVURLAsset(url: url)
        let created = AVAssetImageGenerator(asset: asset)
        created.appliesPreferredTrackTransform = true
        // Thumbnails only: a filmstrip tile is 48 pt (144 px), so decoding at the
        // source's 1080×1920 held ~8 MB per tile.
        created.maximumSize = tier == .stage ? CGSize(width: 320, height: 320) : CGSize(width: 288, height: 288)
        // Exact-frame tolerance (`.zero`) forces a slow precise seek on every
        // request; a tolerance lets AVFoundation return the nearest already-decoded
        // frame — that is what fixed the scrubbing jank.
        let toleranceSeconds = tier == .filmstripBase ? 0.5 : Self.scrubBucketMs / 1000
        let tolerance = CMTime(seconds: toleranceSeconds, preferredTimescale: 600)
        created.requestedTimeToleranceBefore = tolerance
        created.requestedTimeToleranceAfter = tolerance
        generators[key] = created
        return created
    }
}

/// The filmstrip's fixed source-time grid, as pure functions (unit-tested).
/// A tile is `tileWidth` pt wide and anchored to *source* time 0, so a clip is a
/// window onto one strip: trimming only moves the window and the strip never
/// slides or regenerates.
enum FilmstripGrid {
    /// One base thumbnail per second of source, but never more than `baseThumbnailCap`
    /// per video (a long video gets a coarser step, in whole seconds).
    static let baseStepFloorMs = 1000.0
    static let baseThumbnailCap = 240.0
    /// Detail steps are the base step halved up to this many times (1 s → 31 ms).
    static let detailHalvings = 5

    static func baseStepMs(durationMs: Double) -> Double {
        max(baseStepFloorMs, (durationMs / baseThumbnailCap / 1000).rounded(.up) * 1000)
    }

    /// Detail spacing for a zoom where one tile spans `tileSourceMs` of source:
    /// the coarsest halving of the base step that still gives each tile its own
    /// frame. `nil` when the base grid is already as fine as a tile.
    static func detailStepMs(baseStepMs: Double, tileSourceMs: Double) -> Double? {
        guard tileSourceMs < baseStepMs else { return nil }
        for n in 1...detailHalvings {
            let step = baseStepMs / Double(1 << n)
            if step <= tileSourceMs { return step }
        }
        return baseStepMs / Double(1 << detailHalvings)
    }

    /// Tile indices covering clip-local x in `lower..<upper`, when the strip is
    /// shifted left by `trimStartPx` (the clip's `trimStart` in points).
    static func tiles(lower: Double, upper: Double, trimStartPx: Double, tileWidth: Double) -> ClosedRange<Int>? {
        guard upper > lower, tileWidth > 0 else { return nil }
        let first = max(Int(((lower + trimStartPx) / tileWidth).rounded(.down)), 0)
        let last = max(Int(((upper + trimStartPx) / tileWidth).rounded(.up)) - 1, first)
        return first...last
    }
}

/// `generateCGImagesAsynchronously`'s completion handler fires on an
/// AVFoundation-owned queue, not necessarily serially and not on the
/// `@MainActor` — so knowing when the batch is fully done needs its own
/// lock rather than relying on `VideoFrameCache`'s own actor isolation
/// (that isolation only covers code that actually hops through one of its
/// `@MainActor` methods, not a raw escaping closure AVFoundation calls
/// directly). `@unchecked Sendable` is deliberate here: `NSLock` is what
/// actually makes decrementing `remaining` from arbitrary threads safe,
/// the compiler just can't see that through a plain class.
private final class FilmstripRemainingCount: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int

    init(_ count: Int) {
        remaining = count
    }

    func decrementAndIsDone() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        remaining -= 1
        return remaining <= 0
    }
}
