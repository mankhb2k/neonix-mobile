import AVFoundation
import CoreImage
import Observation
import UIKit

/// Tunables for the scrub frame cache. Memory ≈ cached frames × one
/// `maxLongEdge`-sized BGRA image (640×360×4 B ≈ 0.9 MB); with these values
/// the cache holds at most ~(2 × `keepSeconds`) × `framesPerSecond` ≈ 180
/// frames ≈ 165 MB per asset in the worst case.
enum ScrubFrameTuning {
    static let framesPerSecond: Int32 = 15
    static let maxLongEdge: CGFloat = 640
    /// Decode window around the requested time, biased toward the direction
    /// the playhead is currently moving.
    static let windowBehindSeconds = 2.0
    static let windowAheadSeconds = 6.0
    /// A new window is started once the playhead gets this close to the edge
    /// of what's already decoded.
    static let refillMarginSeconds = 1.0
    /// Frames farther than this from the latest requested time are evicted.
    static let keepSeconds = 6.0
}

/// Decoded, downscaled frames for scrubbing — the Stage reads from here
/// synchronously while paused/scrubbing instead of seeking an `AVPlayer`.
/// See CLAUDE.md's "Scrubbing renders from a decoded frame cache" note.
@MainActor
@Observable
final class ScrubFrameCache {
    static let shared = ScrubFrameCache()

    /// Bumped whenever frames land, so views reading `image(...)` re-render.
    private(set) var version = 0

    @ObservationIgnored private var stores: [String: Store] = [:]

    private struct Store {
        var times: [Double] = []
        var images: [CGImage] = []
        var decodedRange: ClosedRange<Double>?
        var pendingRange: ClosedRange<Double>?
        var generation = 0
        var task: Task<Void, Never>?
        var durationSeconds: Double?
        var lastRequested: Double?
    }

    /// Nearest cached frame to `seconds` (asset-local time), or `nil` if
    /// nothing has been decoded for this asset yet.
    func image(assetId: String, atSeconds seconds: Double) -> CGImage? {
        _ = version
        guard let store = stores[assetId], !store.times.isEmpty else { return nil }
        return store.images[Self.nearestIndex(in: store.times, to: seconds)]
    }

    /// Makes sure frames around `seconds` are decoded or being decoded.
    /// Cheap to call on every playhead tick.
    func prefetch(assetId: String, url: URL, around seconds: Double) {
        var store = stores[assetId] ?? Store()
        let movingForward = seconds >= (store.lastRequested ?? seconds)
        store.lastRequested = seconds

        let upperLimit = store.durationSeconds ?? .infinity
        let needLower = max(0, seconds - ScrubFrameTuning.refillMarginSeconds)
        let needUpper = min(upperLimit, seconds + ScrubFrameTuning.refillMarginSeconds)
        let inFlightCovers = store.pendingRange?.contains(seconds) ?? false
        let decodedCovers = store.decodedRange.map { $0.lowerBound <= needLower && needUpper <= $0.upperBound } ?? false
        guard !inFlightCovers, !decodedCovers else {
            stores[assetId] = store
            return
        }

        let behind = movingForward ? ScrubFrameTuning.windowBehindSeconds : ScrubFrameTuning.windowAheadSeconds
        let ahead = movingForward ? ScrubFrameTuning.windowAheadSeconds : ScrubFrameTuning.windowBehindSeconds
        let lower = max(0, seconds - behind)
        let range = lower...max(lower, min(upperLimit, seconds + ahead))

        store.task?.cancel()
        store.generation += 1
        store.pendingRange = range
        let generation = store.generation
        store.task = Task { [weak self] in
            await self?.consume(ScrubFrameDecoder.frames(url: url, range: range), assetId: assetId, range: range, generation: generation)
        }
        stores[assetId] = store
    }

    private func consume(_ events: AsyncStream<ScrubFrameDecoder.Event>, assetId: String, range: ClosedRange<Double>, generation: Int) async {
        for await event in events {
            guard stores[assetId]?.generation == generation else { return }
            switch event {
            case .duration(let seconds):
                stores[assetId]?.durationSeconds = seconds
            case .frames(let batch):
                insert(batch, assetId: assetId, decodedFrom: range.lowerBound)
            }
        }
        if stores[assetId]?.generation == generation {
            stores[assetId]?.pendingRange = nil
        }
    }

    private func insert(_ batch: [ScrubFrameDecoder.Frame], assetId: String, decodedFrom lower: Double) {
        guard var store = stores[assetId], let last = batch.last else { return }
        let minSpacing = 0.5 / Double(ScrubFrameTuning.framesPerSecond)
        for frame in batch {
            let index = Self.insertionIndex(in: store.times, for: frame.seconds)
            if index < store.times.count, abs(store.times[index] - frame.seconds) < minSpacing {
                store.images[index] = frame.image
            } else if index > 0, abs(store.times[index - 1] - frame.seconds) < minSpacing {
                store.images[index - 1] = frame.image
            } else {
                store.times.insert(frame.seconds, at: index)
                store.images.insert(frame.image, at: index)
            }
        }

        let progress = lower...max(lower, last.seconds)
        let joinGap = 2.0 / Double(ScrubFrameTuning.framesPerSecond)
        if let decoded = store.decodedRange,
           progress.lowerBound <= decoded.upperBound + joinGap,
           decoded.lowerBound <= progress.upperBound + joinGap {
            store.decodedRange = min(decoded.lowerBound, progress.lowerBound)...max(decoded.upperBound, progress.upperBound)
        } else {
            store.decodedRange = progress
        }

        if let center = store.lastRequested {
            let keepLower = center - ScrubFrameTuning.keepSeconds
            let keepUpper = center + ScrubFrameTuning.keepSeconds
            var keptTimes: [Double] = []
            var keptImages: [CGImage] = []
            for (time, image) in zip(store.times, store.images) where time >= keepLower && time <= keepUpper {
                keptTimes.append(time)
                keptImages.append(image)
            }
            store.times = keptTimes
            store.images = keptImages
            if let decoded = store.decodedRange {
                let clampedLower = max(decoded.lowerBound, keepLower)
                let clampedUpper = min(decoded.upperBound, keepUpper)
                store.decodedRange = clampedLower <= clampedUpper ? clampedLower...clampedUpper : nil
            }
        }

        stores[assetId] = store
        version &+= 1
    }

    private static func insertionIndex(in times: [Double], for value: Double) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func nearestIndex(in times: [Double], to value: Double) -> Int {
        let index = insertionIndex(in: times, for: value)
        if index == 0 { return 0 }
        if index == times.count { return times.count - 1 }
        return (value - times[index - 1]) <= (times[index] - value) ? index - 1 : index
    }
}

private let scrubCIContext = CIContext(options: [.cacheIntermediates: false])

/// Decodes one time window of a video sequentially with `AVAssetReader`,
/// already rotated (preferred transform) and downscaled on the GPU via a
/// video composition, at `ScrubFrameTuning.framesPerSecond`. Sequential
/// decode only pays the "walk forward from the previous keyframe" cost once
/// per window, instead of once per seek.
enum ScrubFrameDecoder {
    struct Frame {
        let seconds: Double
        let image: CGImage
    }

    enum Event {
        case duration(Double)
        case frames([Frame])
    }

    static func frames(url: URL, range: ClosedRange<Double>) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                await decode(url: url, range: range, into: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private static func decode(url: URL, range: ClosedRange<Double>, into continuation: AsyncStream<Event>.Continuation) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let properties = try? await track.load(.naturalSize, .preferredTransform),
              let duration = try? await asset.load(.duration)
        else { return }

        let durationSeconds = duration.seconds
        continuation.yield(.duration(durationSeconds))
        let end = min(range.upperBound, durationSeconds)
        guard end > range.lowerBound, !Task.isCancelled else { return }

        let (naturalSize, preferredTransform) = properties
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let longEdge = max(bounds.width, bounds.height)
        guard longEdge > 0 else { return }
        let scale = min(1, ScrubFrameTuning.maxLongEdge / longEdge)
        let renderSize = CGSize(
            width: max(2, (bounds.width * scale / 2).rounded(.down) * 2),
            height: max(2, (bounds.height * scale / 2).rounded(.down) * 2)
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(
            preferredTransform
                .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: ScrubFrameTuning.framesPerSecond)
        composition.instructions = [instruction]

        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = composition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        guard reader.startReading() else { return }

        var batch: [Frame] = []
        while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            // `createCGImage` copies out of the reader's pixel-buffer pool,
            // so holding many frames never starves the reader.
            guard let image = scrubCIContext.createCGImage(ciImage, from: ciImage.extent) else { continue }
            batch.append(Frame(seconds: CMSampleBufferGetPresentationTimeStamp(sample).seconds, image: image))
            if batch.count >= 3 {
                continuation.yield(.frames(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }
        if Task.isCancelled {
            reader.cancelReading()
            return
        }
        if !batch.isEmpty { continuation.yield(.frames(batch)) }
    }
}

/// One exact, full-quality frame for when scrubbing has settled — the cache
/// above is downscaled and quantized to `ScrubFrameTuning.framesPerSecond`.
@MainActor
final class SharpFrameLoader {
    static let shared = SharpFrameLoader()

    private var generators: [String: AVAssetImageGenerator] = [:]

    func image(assetId: String, url: URL, atSeconds seconds: Double) async -> CGImage? {
        let generator: AVAssetImageGenerator
        if let existing = generators[assetId] {
            generator = existing
        } else {
            generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            generators[assetId] = generator
        }
        return try? await generator.image(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600)).image
    }
}
