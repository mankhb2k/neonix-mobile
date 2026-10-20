import AVFoundation
import CoreImage
import Darwin
import Observation
import Vision

/// Remove BG on video, step 2 (CLAUDE.md "Remove BG"): fills a `MatteSet` for a stretch of a video's source time. The video is read once, forward, with `AVAssetReader` (no seeking), twice
/// at most - from the playhead to the end, then from the start up to the playhead, so the picture next to where the person looks is cut first - and every frame on the 30 fps grid that has
/// no matte yet goes through `VNGenerateForegroundInstanceMaskRequest` (all foreground instances, no tracking). Progress and cancellation are the caller's: `isCancelled` is polled per frame.
enum VideoMatteJob {
    struct Result {
        var frames = 0
        var visionMs: [Double] = []
        var seconds = 0.0
        var cancelled = false
        /// The app's memory footprint (MB) at the start and the highest seen while the job ran (sampled every 10 frames).
        var startFootprintMB = 0.0
        var peakFootprintMB = 0.0
    }

    private enum Step { case next, end, cancelled }

    /// `phys_footprint`, the number the system's memory limit counts.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// `range` is source seconds; `focus` the second to start from. `progress(done, total)` is called from the worker (throttled by the caller).
    static func run(asset url: URL, set: MatteSet, range: ClosedRange<Double>, focus: Double, isCancelled: @Sendable () -> Bool, progress: @Sendable (Int, Int) -> Void) async -> Result {
        let began = CACurrentMediaTime()
        var result = Result()
        result.startFootprintMB = footprintMB()
        result.peakFootprintMB = result.startFootprintMB
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform), let size = try? await track.load(.naturalSize) else { return result }
        let nominalFps = Double((try? await track.load(.nominalFrameRate)) ?? 30)
        // A frame feeds the grid index its time is closest to: only samples within half a source frame (in grid steps) of a grid time are used. The old rule took the first
        // sample of each index, i.e. on a 60 fps clip the frame 1/60 s BEFORE the grid time every time.
        let tolerance = 0.5 * max(MatteSet.fps / max(nominalFps, 1), 0.25) + 1e-3
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let longSide = max(abs(bounds.width), abs(bounds.height))
        let shrink = min(960 / longSide, 1)

        let wanted = MatteSet.index(forSourceSeconds: range.lowerBound)...MatteSet.index(forSourceSeconds: range.upperBound)
        var todo = Set(set.missing(in: wanted))
        let total = todo.count
        guard total > 0 else { return result }
        let focusSeconds = min(max(focus, range.lowerBound), range.upperBound)
        let context = CIContext(options: [.workingColorSpace: NSNull()])

        for pass in [focusSeconds...range.upperBound, range.lowerBound...focusSeconds] {
            if todo.isEmpty || isCancelled() { break }
            guard let reader = try? AVAssetReader(asset: asset) else { break }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData = false
            reader.timeRange = CMTimeRange(start: CMTime(seconds: pass.lowerBound, preferredTimescale: 600), end: CMTime(seconds: pass.upperBound + 0.05, preferredTimescale: 600))
            guard reader.canAdd(output) else { break }
            reader.add(output)
            guard reader.startReading() else { break }
            // Each frame runs in its own autorelease pool: the sample buffer, the CIImage / CGImage and Vision's objects are autoreleased, and this loop never returns to a run loop, so
            // without it they pile up (measured on an iPhone 13: +8 MB per frame, 2 GB and the app was killed at frame ~250).
            frames: while true {
                let step: Step = autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { return .end }
                    if isCancelled() { reader.cancelReading(); return .cancelled }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let index = MatteSet.index(forSourceSeconds: pts)
                    guard todo.contains(index), abs(pts * MatteSet.fps - Double(index)) <= tolerance, let buffer = CMSampleBufferGetImageBuffer(sample) else { return .next }
                    let frame = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]).oriented(VideoOrientation.orientation(for: transform)).transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
                    let started = CACurrentMediaTime()
                    let data = matte(of: frame, context: context)
                    result.visionMs.append((CACurrentMediaTime() - started) * 1000)
                    set.store(index: index, compressed: data)
                    todo.remove(index)
                    result.frames += 1
                    if result.frames % 10 == 0 { result.peakFootprintMB = max(result.peakFootprintMB, footprintMB()) }
                    #if DEBUG
                    if result.frames % 50 == 0 { NSLog("REMOVEBGVIDEO frame %d footprint %.0f MB", result.frames, footprintMB()) }
                    #endif
                    progress(total - todo.count, total)
                    return .next
                }
                switch step {
                case .next: continue frames
                case .end: break frames
                case .cancelled: result.cancelled = true; break frames
                }
            }
            if reader.status == .reading { reader.cancelReading() }
        }
        result.cancelled = result.cancelled || isCancelled()
        if !result.cancelled, !todo.isEmpty {
            // Indexes no frame was close enough to (24 fps clips, the clip's last step): the neighbour's matte stands in, so the stretch counts as done.
            for index in todo { if let neighbour = set.compressed(index - 1) ?? set.compressed(index + 1) { set.store(index: index, compressed: neighbour) } }
            progress(total, total)
        }
        result.seconds = CACurrentMediaTime() - began
        return result
    }

    private static func matte(of frame: CIImage, context: CIContext) -> Data {
        guard let cg = context.createCGImage(frame, from: frame.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else { return MatteSet.wholeFrameMatte() ?? Data() }
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? VNImageRequestHandler(cgImage: cg).perform([request])) != nil, let observation = request.results?.first, !observation.allInstances.isEmpty,
              let mask = try? observation.generateMask(forInstances: observation.allInstances), let data = MatteSet.encode(mask) else { return MatteSet.wholeFrameMatte() ?? Data() }
        return data
    }
}

/// The running jobs, for the stage's progress card and the Remove BG tile. One job per layer; a layer's job needs its matte set filled over the clip's source stretch.
@MainActor
@Observable
final class SegmentationJobs {
    static let shared = SegmentationJobs()

    struct Progress: Equatable { var done = 0; var total = 1; var fraction: Double { total > 0 ? Double(done) / Double(total) : 1 } }

    /// layer id -> progress, while its job runs.
    private(set) var running: [String: Progress] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var requests: [String: String] = [:]
    @ObservationIgnored private var generations: [String: Int] = [:]

    /// Starts (or keeps) the job that fills the matte set of `layerId`'s file over `range` (source seconds). The same request again does nothing; a changed range restarts it
    /// (only the missing frames cost anything).
    func ensure(layerId: String, assetURI: String, range: ClosedRange<Double>, focus: Double) {
        guard let url = bundledURL(filename: assetURI) else { return }
        let request = "\(assetURI)|\(range.lowerBound)|\(range.upperBound)"
        if requests[layerId] == request { return }
        cancel(layerId, forget: false)
        requests[layerId] = request
        let set = VideoMatteStore.shared.set(forAssetURI: assetURI)
        let generation = (generations[layerId] ?? 0) + 1
        generations[layerId] = generation
        running[layerId] = Progress()
        tasks[layerId] = Task { [weak self] in
            let flag = CancelFlag()
            await withTaskCancellationHandler {
                let outcome = await Task.detached(priority: .userInitiated) { () -> VideoMatteJob.Result in
                    set.loadFromDisk()
                    var lastReport = 0.0
                    return await VideoMatteJob.run(asset: url, set: set, range: range, focus: focus, isCancelled: { flag.value }, progress: { done, total in
                        let now = CACurrentMediaTime()
                        guard now - lastReport > 0.1 || done == total else { return }
                        lastReport = now
                        Task { @MainActor in self?.report(layerId, done: done, total: total) }
                    })
                }.value
                self?.finish(layerId, generation: generation, outcome: outcome, assetURI: assetURI)
            } onCancel: { flag.value = true }
        }
    }

    func cancel(_ layerId: String, forget: Bool = true) {
        tasks[layerId]?.cancel()
        tasks[layerId] = nil
        running[layerId] = nil
        generations[layerId, default: 0] += 1
        if forget { requests[layerId] = nil }
    }

    /// Layers that no longer need a job (their Remove BG was taken off or the clip is gone).
    func keepOnly(_ layerIds: Set<String>) {
        for id in Set(requests.keys).subtracting(layerIds) { cancel(id) }
    }

    private func report(_ layerId: String, done: Int, total: Int) {
        guard running[layerId] != nil else { return }
        running[layerId] = Progress(done: done, total: total)
    }

    private func finish(_ layerId: String, generation: Int, outcome: VideoMatteJob.Result, assetURI: String) {
        if generations[layerId] == generation { running[layerId] = nil; tasks[layerId] = nil }
        // A cancelled request stays remembered, so the same request is not restarted at once; taking Remove BG off forgets it.
        #if DEBUG
        if outcome.frames > 0 {
            let sorted = outcome.visionMs.sorted()
            let line = String(format: "%@ frames %d in %.1f s (%.1f frames/s) per frame median %.0f p95 %.0f max %.0f ms%@\n", assetURI, outcome.frames, outcome.seconds,
                              Double(outcome.frames) / max(outcome.seconds, 0.001), sorted[sorted.count / 2], sorted[min(Int(Double(sorted.count - 1) * 0.95), sorted.count - 1)],
                              sorted.last ?? 0, outcome.cancelled ? " (cancelled)" : "")
            NSLog("REMOVEBGVIDEO %@", line)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("removebg_video.txt")
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
        #endif
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}
