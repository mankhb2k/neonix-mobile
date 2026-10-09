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
final class VideoFrameCache {
    static let shared = VideoFrameCache()

    /// How finely scrubbing resolves to a distinct frame request. Coarser
    /// than real playback framerate on purpose: while dragging, many slider
    /// ticks land in the same bucket and reuse one cached result instead of
    /// triggering a fresh decode each time — human eyes can't tell a ~65ms
    /// (~15fps) scrub resolution from a continuous one anyway.
    static let scrubBucketMs: Double = 65

    private var generators: [String: AVAssetImageGenerator] = [:]
    private var cache: [String: UIImage] = [:]

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

        let generator = generator(for: assetId, url: url)
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        let image = UIImage(cgImage: result.image)
        cache[key] = image
        return image
    }

    /// Batch filmstrip generation — one `generateCGImagesAsynchronously`
    /// call for every tile a clip needs, instead of `FilmstripTileView`
    /// firing its own independent `image(at:)` request per tile. This is
    /// AVFoundation's own documented API for exactly this use case (a real
    /// editor builds its filmstrip this way, not N separate single-frame
    /// requests) — it lets the generator batch/order the underlying
    /// decodes itself.
    ///
    /// Returns an `AsyncStream`, not a single collected result — a first
    /// version awaited the *whole* batch before updating anything, which
    /// for a ~30-tile clip meant the entire filmstrip sat blank for several
    /// seconds and then populated all at once (caught on the simulator,
    /// 2026-10-08: logs showed all 34/34 tiles decoding successfully, just
    /// over ~3.7s, while the UI showed nothing the whole time). Streaming
    /// each `(index, image)` the moment its own completion fires lets
    /// `FilmstripClipView` fill tiles in as they individually finish,
    /// matching the old per-tile behavior's progressive feel while still
    /// using one batched underlying request.
    ///
    /// Keyed by the caller's own array index (not the requested second,
    /// which would need float-equality dictionary keys) — AVFoundation
    /// echoes back the exact `CMTime` requested, so a `"value:timescale"`
    /// string key maps each completion back to its index. Each image is
    /// also written into the same per-bucket `cache`
    /// `frame(assetId:url:atSeconds:)` reads, so a later single-frame
    /// request for a time this batch already covered returns instantly.
    ///
    /// Not yet windowed to only currently-visible tiles — a clip's full
    /// tile set is requested in one call regardless of scroll position,
    /// a deliberate simplification that's fine for this app's current
    /// (short, few-second) sample clips. A very long clip would want this
    /// batched per visible window instead; not implemented yet.
    func filmstripImages(assetId: String, url: URL, times: [Double]) -> AsyncStream<(index: Int, image: UIImage?)> {
        AsyncStream { continuation in
            guard !times.isEmpty else {
                continuation.finish()
                return
            }
            let generator = self.generator(for: assetId, url: url)
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

    private func generator(for assetId: String, url: URL) -> AVAssetImageGenerator {
        if let cached = generators[assetId] { return cached }
        let asset = AVURLAsset(url: url)
        let created = AVAssetImageGenerator(asset: asset)
        created.appliesPreferredTrackTransform = true
        // Thumbnails only: a filmstrip tile is ~54 pt, so decoding every one
        // at the source's 1080×1920 held ~8 MB per tile — fine for 34 tiles,
        // not for the hundreds a zoomed-in timeline asks for.
        created.maximumSize = CGSize(width: 320, height: 320)
        // Exact-frame tolerance (`.zero`) forces a slow precise seek on
        // every request; a tolerance matching one scrub bucket lets
        // AVFoundation return the nearest already-decoded frame instead,
        // which is what actually fixed the scrubbing jank — the async
        // API alone just moves the same slow work off the main thread.
        let tolerance = CMTime(seconds: Self.scrubBucketMs / 1000, preferredTimescale: 600)
        created.requestedTimeToleranceBefore = tolerance
        created.requestedTimeToleranceAfter = tolerance
        generators[assetId] = created
        return created
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
