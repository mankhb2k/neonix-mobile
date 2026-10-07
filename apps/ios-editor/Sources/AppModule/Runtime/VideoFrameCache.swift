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

    private func generator(for assetId: String, url: URL) -> AVAssetImageGenerator {
        if let cached = generators[assetId] { return cached }
        let asset = AVURLAsset(url: url)
        let created = AVAssetImageGenerator(asset: asset)
        created.appliesPreferredTrackTransform = true
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
