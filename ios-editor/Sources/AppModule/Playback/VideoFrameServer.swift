import AVFoundation
import CoreImage
import Observation
import UIKit

/// Tunables for `VideoFrameServer`. Memory ≈ frames held × one
/// `maxLongEdge`-sized BGRA image (540×960×4 B ≈ 2 MB). At these values a
/// forward-moving playhead holds ~1.7 s of frames (~50 frames ≈ 100 MB per
/// asset) and a backward scrub ~2.3 s (~70 frames ≈ 140 MB).
enum VideoFrameTuning {
    /// Long edge of decoded preview frames. The Stage shows a 9:16 video
    /// ~1120 px tall on a 6.1" iPhone, so 960 is close to native.
    static let maxLongEdge: CGFloat = 960

    // Playhead moving forward or playing: decode just ahead of it and keep
    // a short tail for small back-and-forth movements.
    static let forwardStartBehindSeconds = 0.3
    static let forwardDecodeAheadSeconds = 1.0
    static let forwardKeepBehindSeconds = 0.5

    // Playhead moving backward: start the reader well behind it, since every
    // restart pays a walk from the previous keyframe.
    static let backwardStartBehindSeconds = 1.5
    static let backwardDecodeAheadSeconds = 0.3
    static let backwardKeepBehindSeconds = 1.8

    /// While moving forward, keep the running reader if the playhead is at
    /// most this far past what it has produced — it will catch up faster
    /// than a restart (which re-walks from the previous keyframe) would.
    static let readerCatchUpSeconds = 1.0

    /// A direction flip only takes effect once movement opposite to the
    /// current direction accumulates past this much source time. Without
    /// it, the small back-and-forth jitter inside an otherwise one-way drag
    /// flips `movingBackward` on every single tick that disagrees, and each
    /// flip changes `isServed`'s own criteria enough to force a reader
    /// restart — turning a steady forward drag into a stream of restarts.
    static let directionHysteresisSeconds = 0.12
}

/// The one source of video pixels for the Stage — the same path for
/// scrubbing, momentum and Play. `EditorPlaybackEngine` calls
/// `prefetch(...)` every time `currentTimeMs` changes; views read
/// `image(...)` synchronously in `body`.
///
/// Each asset has at most one `AVAssetReader` running forward
/// sequentially from where it was started, with backpressure: it decodes
/// until it is `decodeAhead` seconds past the playhead and then waits. So
/// playback is one continuous sequential decode — no seek per frame, no
/// re-seek on Play, no keyframe walk except when the playhead jumps (a
/// scrub jump or moving backward), which starts a new reader. That walk
/// is the real cost of long-GOP footage (the sample videos have a keyframe
/// every 250 frames); the long-term fix is an all-intra proxy at import.
@MainActor
@Observable
final class VideoFrameServer {
    static let shared = VideoFrameServer()

    /// Bumped whenever a frame lands, so views reading `image(...)` re-render.
    private(set) var version = 0

    @ObservationIgnored private var stores: [String: Store] = [:]
    @ObservationIgnored private var nextGeneration = 0

    private struct Store {
        var times: [Double] = []
        var images: [CGImage] = []
        var reader: Reader?
        var lastRequested: Double?
        var movingBackward = false
        /// Source-time distance moved opposite to `movingBackward` since it
        /// last flipped — see `VideoFrameTuning.directionHysteresisSeconds`.
        var reverseAccumulator: Double = 0
    }

    private struct Reader {
        let generation: Int
        let startSeconds: Double
        /// The playhead time this reader was started for — it counts as
        /// "serving" that time until it gets there.
        let targetSeconds: Double
        let gate: DecodeGate
        let task: Task<Void, Never>
    }

    // MARK: Reading

    /// Nearest decoded frame to `seconds` (asset-local time), or `nil` if
    /// nothing has been decoded for this asset yet.
    func image(assetId: String, atSeconds seconds: Double) -> CGImage? {
        _ = version
        guard let store = stores[assetId], !store.times.isEmpty else { return nil }
        return store.images[Self.nearestIndex(in: store.times, to: seconds)]
    }

    func hasFrame(assetId: String, near seconds: Double, tolerance: Double) -> Bool {
        guard let store = stores[assetId], !store.times.isEmpty else { return false }
        let index = Self.nearestIndex(in: store.times, to: seconds)
        return abs(store.times[index] - seconds) <= tolerance
    }

    // MARK: Prefetch

    /// Positions decoding around `seconds`. Cheap; call on every playhead
    /// change.
    func prefetch(assetId: String, url: URL, atSeconds seconds: Double) {
        var store = stores[assetId] ?? Store()
        if let last = store.lastRequested {
            let delta = seconds - last
            if delta != 0 {
                let movingBackwardNow = delta < 0
                if movingBackwardNow == store.movingBackward {
                    store.reverseAccumulator = 0
                } else {
                    store.reverseAccumulator += abs(delta)
                    if store.reverseAccumulator >= VideoFrameTuning.directionHysteresisSeconds {
                        store.movingBackward = movingBackwardNow
                        store.reverseAccumulator = 0
                    }
                }
            }
        }
        store.lastRequested = seconds

        let backward = store.movingBackward
        let decodeAhead = backward ? VideoFrameTuning.backwardDecodeAheadSeconds : VideoFrameTuning.forwardDecodeAheadSeconds
        store.reader?.gate.limitSeconds = seconds + decodeAhead
        Self.evict(&store, around: seconds)

        if !Self.isServed(store, seconds: seconds, backward: backward) {
            let behind = backward ? VideoFrameTuning.backwardStartBehindSeconds : VideoFrameTuning.forwardStartBehindSeconds
            startReader(in: &store, assetId: assetId, url: url, startSeconds: max(0, seconds - behind), targetSeconds: seconds, limitSeconds: seconds + decodeAhead)
        }
        stores[assetId] = store
    }

    private static func isServed(_ store: Store, seconds: Double, backward: Bool) -> Bool {
        let frameTolerance = 0.1
        let hasNearbyFrame = !store.times.isEmpty
            && abs(store.times[nearestIndex(in: store.times, to: seconds)] - seconds) <= frameTolerance
        guard let reader = store.reader else { return hasNearbyFrame }
        if backward {
            return reader.startSeconds <= seconds && hasNearbyFrame
        }
        guard reader.startSeconds <= seconds + 0.05 else { return hasNearbyFrame }
        if reader.gate.isFinished { return true }
        let reach = max(reader.gate.producedSeconds, reader.targetSeconds)
        return seconds <= reach + VideoFrameTuning.readerCatchUpSeconds
    }

    private func startReader(in store: inout Store, assetId: String, url: URL, startSeconds: Double, targetSeconds: Double, limitSeconds: Double) {
        store.reader?.task.cancel()
        nextGeneration += 1
        let generation = nextGeneration
        let gate = DecodeGate(limitSeconds: limitSeconds, producedSeconds: startSeconds)
        let task = Task { [weak self] in
            for await frame in VideoFrameDecoder.frames(url: url, from: startSeconds, gate: gate) {
                guard let self, self.stores[assetId]?.reader?.generation == generation else { return }
                self.insert(frame, assetId: assetId)
            }
        }
        store.reader = Reader(generation: generation, startSeconds: startSeconds, targetSeconds: targetSeconds, gate: gate, task: task)
    }

    private func insert(_ frame: VideoFrameDecoder.Frame, assetId: String) {
        guard var store = stores[assetId] else { return }
        let index = Self.insertionIndex(in: store.times, for: frame.seconds)
        let duplicateSpacing = 0.004
        if index < store.times.count, abs(store.times[index] - frame.seconds) < duplicateSpacing {
            store.images[index] = frame.image
        } else if index > 0, abs(store.times[index - 1] - frame.seconds) < duplicateSpacing {
            store.images[index - 1] = frame.image
        } else {
            store.times.insert(frame.seconds, at: index)
            store.images.insert(frame.image, at: index)
        }
        if let center = store.lastRequested {
            Self.evict(&store, around: center)
        }
        stores[assetId] = store
        version &+= 1
    }

    private static func evict(_ store: inout Store, around center: Double) {
        let backward = store.movingBackward
        let keepBehind = backward ? VideoFrameTuning.backwardKeepBehindSeconds : VideoFrameTuning.forwardKeepBehindSeconds
        let keepAhead = (backward ? VideoFrameTuning.backwardDecodeAheadSeconds : VideoFrameTuning.forwardDecodeAheadSeconds) + 0.2
        let lower = center - keepBehind
        let upper = center + keepAhead
        guard let first = store.times.first, let last = store.times.last, first < lower || last > upper else { return }
        var keptTimes: [Double] = []
        var keptImages: [CGImage] = []
        for (time, image) in zip(store.times, store.images) where time >= lower && time <= upper {
            keptTimes.append(time)
            keptImages.append(image)
        }
        store.times = keptTimes
        store.images = keptImages
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

/// Shared between the main actor (which moves `limitSeconds` with the
/// playhead) and the decoding thread (which reports progress and waits
/// whenever it is `limitSeconds` ahead).
final class DecodeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var limit: Double
    private var produced: Double
    private var finished = false

    init(limitSeconds: Double, producedSeconds: Double) {
        limit = limitSeconds
        produced = producedSeconds
    }

    var limitSeconds: Double {
        get { lock.withLock { limit } }
        set { lock.withLock { limit = newValue } }
    }

    var producedSeconds: Double {
        get { lock.withLock { produced } }
        set { lock.withLock { produced = newValue } }
    }

    var isFinished: Bool {
        get { lock.withLock { finished } }
        set { lock.withLock { finished = newValue } }
    }
}

private let previewCIContext = CIContext(options: [.cacheIntermediates: false])

/// Decodes one asset forward from a start time with `AVAssetReader`,
/// rotated (preferred transform), downscaled on the GPU via a video
/// composition and tagged Rec.709 so colors match the source, at the
/// asset's own frame rate. Waits whenever it is past `gate.limitSeconds`.
enum VideoFrameDecoder {
    struct Frame {
        let seconds: Double
        let image: CGImage
    }

    static func frames(url: URL, from startSeconds: Double, gate: DecodeGate) -> AsyncStream<Frame> {
        AsyncStream { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                await decode(url: url, from: startSeconds, gate: gate, into: continuation)
                gate.isFinished = true
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private static func decode(url: URL, from startSeconds: Double, gate: DecodeGate, into continuation: AsyncStream<Frame>.Continuation) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let properties = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate),
              let duration = try? await asset.load(.duration),
              startSeconds < duration.seconds,
              !Task.isCancelled
        else { return }

        let (naturalSize, preferredTransform, nominalFrameRate) = properties
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let longEdge = max(bounds.width, bounds.height)
        guard longEdge > 0 else { return }
        let scale = min(1, VideoFrameTuning.maxLongEdge / longEdge)
        let renderSize = CGSize(
            width: max(2, (bounds.width * scale / 2).rounded(.down) * 2),
            height: max(2, (bounds.height * scale / 2).rounded(.down) * 2)
        )
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30

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
        composition.frameDuration = CMTime(seconds: 1 / Double(frameRate), preferredTimescale: 6000)
        composition.instructions = [instruction]
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = composition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: startSeconds, preferredTimescale: 600), end: duration)
        guard reader.startReading() else { return }

        while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            // Copies out of the reader's pixel-buffer pool, so holding many
            // frames never starves the reader.
            guard let image = previewCIContext.createCGImage(ciImage, from: ciImage.extent) else { continue }
            continuation.yield(Frame(seconds: seconds, image: image))
            gate.producedSeconds = seconds
            while seconds > gate.limitSeconds, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
        }
        if Task.isCancelled { reader.cancelReading() }
    }
}

/// One exact, full-quality frame for when the playhead is at rest —
/// decoded preview frames are downscaled to `VideoFrameTuning.maxLongEdge`.
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
