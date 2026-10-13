#if DEBUG
import AVFoundation
import CoreGraphics
import UIKit

/// Does the way the app builds its seek time land on the intended frame? (PLAYBACK_PIPELINE.md §9, "Mô hình thời gian".)
/// `PlayerSeekCoordinator` builds `CMTime(seconds:, preferredTimescale: 600)` and seeks with zero tolerance at rest; on the
/// Mac that construction truncated onto the wrong frame. This repeats the test with the real `AVPlayer` seek on the device:
/// synthetic clips (frame index drawn into each frame, exact PTS) and the real `iphone-footage.MOV` (the frame shown is
/// judged by its own PTS). Runs at launch when `SEEK_BENCH=1` is set; writes `Documents/seek_bench.txt`.
@MainActor
enum SeekTimeBench {
    struct Rate { let name: String; let num: Int32; let den: Int64
        var frame: Double { Double(den) / Double(num) }
        func pts(_ k: Int) -> CMTime { CMTime(value: Int64(k) * den, timescale: num) }
    }

    static func runIfRequested() async {
        guard ProcessInfo.processInfo.environment["SEEK_BENCH"] != nil else { return }
        let report = await run()
        NSLog("SEEKBENCH\n%@", report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("seek_bench.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Synthetic clips

    private static let bits = 10, cell = 12, side = 120

    private static func draw(_ index: Int, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(gray: 1, alpha: 1)
        for b in 0..<bits where index >> b & 1 == 1 { ctx.fill(CGRect(x: b * cell, y: 0, width: cell, height: side)) }
    }

    private static func index(of buffer: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return -1 }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        var v = 0
        for b in 0..<bits {
            let x = Int((Double(b) + 0.5) * Double(w) / Double(bits))
            let p = base.advanced(by: (h / 2) * stride + x * 4).assumingMemoryBound(to: UInt8.self)
            if p[0] > 127 { v |= 1 << b }
        }
        return v
    }

    private static func writeClip(_ rate: Rate, frames: Int, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(url: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoMaxKeyFrameIntervalKey: 15, AVVideoAllowFrameReorderingKey: false]])
        input.mediaTimeScale = rate.num
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for k in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            draw(k, into: pb!)
            adaptor.append(pb!, withPresentationTime: rate.pts(k))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    // MARK: Seeking like the app

    /// One zero-tolerance `AVPlayer` seek, then the frame the video output shows: (its PTS, its pixels).
    private static func shownFrame(player: AVPlayer, output: AVPlayerItemVideoOutput, at time: CMTime) async -> (pts: Double, buffer: CVPixelBuffer)? {
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        for _ in 0..<60 {
            var shown = CMTime.zero
            if let buffer = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: &shown) { return (shown.seconds, buffer) }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return nil
    }

    private static func makePlayer(_ url: URL) -> (AVPlayer, AVPlayerItemVideoOutput) {
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        return (AVPlayer(playerItem: item), output)
    }

    private static let methodNames = ["(a) CMTime(seconds:,600) now", "(b) rounded to 600", "(c) exact rational", "(e) mid-frame via seconds,600"]

    private static func targets(pts: CMTime, frame: Double) -> [CMTime] {
        let s = pts.seconds
        return [CMTime(seconds: s, preferredTimescale: 600),
                CMTime(value: Int64((s * 600).rounded()), timescale: 600),
                pts,
                CMTime(seconds: s + frame / 2, preferredTimescale: 600)]
    }

    // MARK: Runs

    private static func syntheticReport(frames: Int) async -> String {
        var out = "SYNTHETIC clips, \(frames) frames each, AVPlayer.seek zero tolerance, frame read through AVPlayerItemVideoOutput.\nwrong frames per method:\n"
        out += "rate    | " + methodNames.joined(separator: " | ") + "\n"
        let rates = [Rate(name: "24", num: 24, den: 1), Rate(name: "30", num: 30, den: 1), Rate(name: "29.97", num: 30000, den: 1001),
                     Rate(name: "59.94", num: 60000, den: 1001), Rate(name: "60", num: 60, den: 1)]
        for rate in rates {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("seekbench-\(rate.name).mov")
            do { try await writeClip(rate, frames: frames, to: url) } catch { out += "\(rate.name) write failed: \(error)\n"; continue }
            let (player, output) = makePlayer(url)
            var wrong = [Int](repeating: 0, count: methodNames.count), firstBad = [String](repeating: "", count: methodNames.count)
            for k in 0..<frames {
                for (m, time) in targets(pts: rate.pts(k), frame: rate.frame).enumerated() {
                    let got = (await shownFrame(player: player, output: output, at: time)).map { index(of: $0.buffer) } ?? -1
                    if got != k { wrong[m] += 1; if firstBad[m].isEmpty { firstBad[m] = " (k=\(k) got \(got))" } }
                }
            }
            out += rate.name.padding(toLength: 7, withPad: " ", startingAt: 0) + " | "
                + (0..<wrong.count).map { "\(wrong[$0])/\(frames)\(firstBad[$0])" }.joined(separator: " | ") + "\n"
        }
        return out
    }

    private static func realReport(sample: Int) async -> String {
        let candidates = [MediaImportService.importedMediaDirectory.appendingPathComponent("iphone-footage.MOV")]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return "REAL footage: iphone-footage.MOV not found in Documents/ImportedMedia\n" }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return "REAL footage: unreadable\n" }
        let nominal = (try? await track.load(.nominalFrameRate)) ?? 0
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(readerOutput); reader.startReading()
        var all: [CMTime] = []
        while all.count < 3000, let s = readerOutput.copyNextSampleBuffer() { all.append(CMSampleBufferGetPresentationTimeStamp(s)) }
        all.sort { $0 < $1 }
        let frame = 1 / Double(nominal > 0 ? nominal : 60)
        let picks = stride(from: 100, to: all.count - 1, by: max((all.count - 101) / sample, 1)).prefix(sample).map { all[$0] }
        let (player, output) = makePlayer(url)
        var wrong = [Int](repeating: 0, count: methodNames.count), early = [Int](repeating: 0, count: methodNames.count), late = [Int](repeating: 0, count: methodNames.count)
        var deltas = [[Double]](repeating: [], count: methodNames.count)
        for pts in picks {
            for (m, time) in targets(pts: pts, frame: frame).enumerated() {
                guard let shown = await shownFrame(player: player, output: output, at: time) else { wrong[m] += 1; continue }
                let delta = shown.pts - pts.seconds
                deltas[m].append(delta * 1000)
                if abs(delta) > 0.0005 { wrong[m] += 1; if delta < 0 { early[m] += 1 } else { late[m] += 1 } }
            }
        }
        var out = "REAL iphone-footage.MOV (nominal \(nominal) fps, PTS in the file's own timescale): \(picks.count) frames, each asked at its exact PTS.\n"
        out += "wrong frame (shown PTS differs by > 0.5 ms; earlier/later):\n"
        for m in 0..<methodNames.count { out += "  \(methodNames[m]): \(wrong[m])/\(picks.count)  (earlier \(early[m]), later \(late[m]))  delta ms min/median/max \(String(format: "%.2f / %.2f / %.2f", deltas[m].min() ?? 0, deltas[m].sorted()[deltas[m].count / 2], deltas[m].max() ?? 0))\n" }
        // Where does the player's frame boundary sit relative to the file's PTS? Ask at PTS + d (exact CMTime in microseconds)
        // and see which frame (by nearest file PTS) is shown.
        let times = all.map(\.seconds)
        func nearest(_ t: Double) -> Int { times.indices.min { abs(times[$0] - t) < abs(times[$1] - t) } ?? -1 }
        out += "boundary scan: request = PTS + d, share of frames showing the intended frame / the previous one / the next one\n"
        for d in stride(from: -8.0, through: 2.0, by: 1.0) {
            var same = 0, prev = 0, next = 0, n = 0
            for pts in picks.prefix(60) {
                let k = nearest(pts.seconds)
                let time = CMTime(value: Int64((pts.seconds + d / 1000) * 1_000_000), timescale: 1_000_000)
                guard let shown = await shownFrame(player: player, output: output, at: time) else { continue }
                let got = nearest(shown.pts); n += 1
                if got == k { same += 1 } else if got < k { prev += 1 } else { next += 1 }
            }
            out += String(format: "  d = %+.0f ms: intended %d%%  previous %d%%  next %d%%  (n=%d)\n", d, 100 * same / max(n, 1), 100 * prev / max(n, 1), 100 * next / max(n, 1), n)
        }
        let first = Array(picks.prefix(3)).map { "\($0.value)/\($0.timescale)" }
        out += "first target PTS: \(first); file start offset: \(all.first.map { "\($0.value)/\($0.timescale)" } ?? "?")\n"
        return out
    }

    private static func run() async -> String {
        let device = UIDevice.current
        var report = "SEEK TIME BENCH — \(device.model) \(device.systemName) \(device.systemVersion)\n\n"
        if ProcessInfo.processInfo.environment["SEEK_BENCH"] != "real" { report += await syntheticReport(frames: 120) + "\n" }
        report += await realReport(sample: 120)
        return report
    }
}
#endif
