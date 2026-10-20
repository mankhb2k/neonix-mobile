import AVFoundation

/// A finely sampled loudness envelope of an audio file for the **peak waveform** (the timeline's audio clips, user 2026-10-17):
/// `values[i]` is the loudest sample in the `i`-th slice of `bucketMs`, as a fraction of full scale (0...1, not scaled to the file);
/// `peak` is the loudest value of all - the drawing scales to it, so no peak is ever cut off.
struct PeakEnvelope {
    /// 220 samples at 44.1 kHz.
    static let bucketMs = 220.0 / 44.1
    let values: [Float]
    let peak: Float
    var bucketMs: Double { Self.bucketMs }

    init(values: [Float]) {
        self.values = values
        peak = values.max() ?? 0
    }
}

/// Decodes a file once into a `PeakEnvelope` (about 200 values per second, ~0.8 KB per second of audio), off the main thread, cached in
/// memory and on disk (`Caches/PeakWaveformCache`, keyed by file name like `WaveformCache`). The older `WaveformCache` keeps 600 values per
/// file - fine for a smoothed thumbnail, far too coarse for one hairline per point. Streamed: the decoded audio is never held whole.
@MainActor
final class PeakWaveformCache {
    static let shared = PeakWaveformCache()

    private static let samplesPerBucket = 220
    /// Bump when the format or scaling changes; old cache files are then simply not found.
    private static let fileExtension = "peaks2"
    private var cache: [String: PeakEnvelope] = [:]

    func envelope(url: URL) async -> PeakEnvelope? {
        let key = url.lastPathComponent
        if let hit = cache[key] { return hit }
        if let stored = Self.read(key: key) {
            cache[key] = stored
            return stored
        }
        guard let values = await Self.extract(url: url) else { return nil }
        let envelope = PeakEnvelope(values: values)
        cache[key] = envelope
        Self.write(key: key, values: values)
        return envelope
    }

    // MARK: Disk

    private static func fileURL(key: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("PeakWaveformCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(key).appendingPathExtension(fileExtension)
    }

    private static func read(key: String) -> PeakEnvelope? {
        guard let url = fileURL(key: key), let data = try? Data(contentsOf: url), data.count >= MemoryLayout<Float>.size else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        return PeakEnvelope(values: data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) })
    }

    private static func write(key: String, values: [Float]) {
        guard let url = fileURL(key: key) else { return }
        try? values.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url)
    }

    // MARK: Decode

    /// Mono 16-bit PCM at 44.1 kHz (the reader converts), so every bucket is exactly `samplesPerBucket` samples = `PeakEnvelope.bucketMs`.
    nonisolated private static func extract(url: URL) async -> [Float]? {
        await Task.detached(priority: .utility) { () -> [Float]? in
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let reader = try? AVAssetReader(asset: asset) else { return nil }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            reader.startReading()

            var peaks: [Float] = []
            var bucketPeak: Int32 = 0
            var inBucket = 0
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                var bytes = [UInt8](repeating: 0, count: length)
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)
                bytes.withUnsafeBytes { raw in
                    for sample in raw.bindMemory(to: Int16.self) {
                        bucketPeak = max(bucketPeak, abs(Int32(sample)))   // Int32: abs(Int16.min) would overflow Int16
                        inBucket += 1
                        if inBucket == samplesPerBucket {
                            peaks.append(Float(bucketPeak) / Float(Int16.max))
                            bucketPeak = 0
                            inBucket = 0
                        }
                    }
                }
            }
            if inBucket > 0 { peaks.append(Float(bucketPeak) / Float(Int16.max)) }
            guard !peaks.isEmpty else { return nil }
            return peaks
        }.value
    }
}
