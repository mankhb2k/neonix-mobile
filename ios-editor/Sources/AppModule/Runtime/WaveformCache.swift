import AVFoundation

/// Decodes an audio file's raw PCM samples once and caches a downsampled
/// amplitude envelope, keyed by filename — not by asset id, since the
/// "attached audio" model this supports (see `CLAUDE.md`'s "Timeline
/// lanes"/audio design notes) reads a video asset's own
/// `V2VideoAudioDerivative.uri` directly, with no separate asset id of its
/// own. Decoding happens off the main thread (`Task.detached`) — the same
/// discipline `VideoFrameCache` already applies to video frame decoding,
/// for the same reason: a multi-megabyte file's PCM decode is real,
/// blocking work that must never run on the SwiftUI render loop's thread.
///
/// **Two-tier cache**: in-memory (lives only for this process) backed by
/// a small on-disk cache in `Caches/` (survives app relaunch). Without the
/// disk tier, every fresh app launch re-decoded the same file from
/// scratch — a real, measured ~8.5s cost for a several-minute file in a
/// Debug build (see this file's own verification history in
/// `ui-design-note.md`). The disk tier only ever stores the *downsampled
/// envelope* (≈600 floats, ~2.4KB), never the raw audio — cheap enough
/// that there's no eviction/size-limit logic here, unlike a real media
/// cache would need. `Caches/` (not `Documents/`) is the correct directory
/// for this on iOS: the system may purge it under storage pressure, and
/// doing so only costs a redecode, never real data loss — exactly the
/// "recomputable, not source-of-truth" category this belongs to.
@MainActor
final class WaveformCache {
    static let shared = WaveformCache()

    /// The whole file is downsampled once to this many buckets, cached —
    /// callers resample this cached envelope down further to however many
    /// bars they actually want to draw (the clip's own pixel width).
    /// Coarser than a real DAW's waveform (this is a timeline thumbnail,
    /// not an editing-precision view), fine enough that resampling further
    /// doesn't visibly lose shape.
    private static let bucketResolution = 600

    private var cache: [String: [Float]] = [:]

    func samples(url: URL) async -> [Float]? {
        // The filename alone, not the full path — a sandboxed app's
        // container path changes between installs/launches (a new UUID
        // each time), so the full `url.absoluteString` would never again
        // match a previous run's disk-cache entry. Bundled resource
        // filenames are already unique (flattened at the bundle root —
        // see `bundledURL(filename:)`'s own doc comment), so the filename
        // alone is a stable, correct key across relaunches.
        let key = url.lastPathComponent
        if let cached = cache[key] { return cached }
        if let onDisk = Self.readFromDisk(key: key) {
            cache[key] = onDisk
            return onDisk
        }
        guard let result = await Self.extract(url: url, bucketCount: Self.bucketResolution) else { return nil }
        cache[key] = result
        Self.writeToDisk(key: key, samples: result)
        return result
    }

    private static func cacheDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("WaveformCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheFileURL(key: String) -> URL? {
        cacheDirectory()?.appendingPathComponent(key).appendingPathExtension("waveform")
    }

    /// Raw `Float` bytes, not JSON — this is an internal cache file
    /// nothing else ever reads, so there's no reason to pay encoding
    /// overhead or spend bytes on a text format.
    private static func readFromDisk(key: String) -> [Float]? {
        guard let url = cacheFileURL(key: key), let data = try? Data(contentsOf: url) else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }

    private static func writeToDisk(key: String, samples: [Float]) {
        guard let url = cacheFileURL(key: key) else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: url)
    }

    private static func extract(url: URL, bucketCount: Int) async -> [Float]? {
        await Task.detached(priority: .utility) { () -> [Float]? in
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let reader = try? AVAssetReader(asset: asset) else { return nil }

            // 16-bit signed interleaved PCM — the simplest format to walk
            // byte-by-byte below, and plenty of precision for a peak-amplitude
            // envelope (not a lossless re-encode).
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            reader.startReading()

            var allSamples: [Int16] = []
            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var bytes = [UInt8](repeating: 0, count: length)
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &bytes)
                bytes.withUnsafeBytes { raw in
                    allSamples.append(contentsOf: raw.bindMemory(to: Int16.self))
                }
            }
            guard !allSamples.isEmpty else { return nil }

            let perBucket = max(allSamples.count / bucketCount, 1)
            var buckets: [Float] = []
            buckets.reserveCapacity(bucketCount)
            var index = 0
            while index < allSamples.count {
                let end = min(index + perBucket, allSamples.count)
                var peak: Int16 = 0
                for j in index..<end {
                    // `abs(Int16.min)` overflows Int16 — clamp instead of crashing.
                    let magnitude = allSamples[j] == Int16.min ? Int16.max : abs(allSamples[j])
                    if magnitude > peak { peak = magnitude }
                }
                buckets.append(Float(peak) / Float(Int16.max))
                index += perBucket
            }
            return buckets
        }.value
    }
}
