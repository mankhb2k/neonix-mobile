import AVFoundation

/// How much real source footage exists behind a video clip — needed so a
/// drag-to-trim handle (`TimelineView`'s `FilmstripClipView`) knows how far
/// it's allowed to *extend* a clip (reveal more of the asset), not just how
/// far it can shrink one. `timing.duration`/`trimStart`/`trimEnd` alone only
/// describe what's currently in use, never the asset's own total length.
///
/// In-memory only, keyed by filename (not a disk tier like `WaveformCache`'s
/// — a single `AVURLAsset.load(.duration)` call is cheap, nothing here is
/// worth persisting across launches).
@MainActor
final class AssetDurationCache {
    static let shared = AssetDurationCache()
    private var cache: [String: Double] = [:]

    func durationMs(url: URL) async -> Double? {
        let key = url.lastPathComponent
        if let cached = cache[key] { return cached }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isValid, !duration.isIndefinite else { return nil }
        let ms = CMTimeGetSeconds(duration) * 1000
        cache[key] = ms
        return ms
    }
}
