#if DEBUG
import AVFoundation
import Darwin
import UIKit

/// Why the Crop popup's play button looks choppy (user 2026-10-18, "measure first"). The popup plays by asking `VideoFrameCache.frame` for a still every
/// 150 ms (`CropSheet.togglePlay`); the candidate fix is an `AVPlayer` with `AVPlayerItemVideoOutput` running the clip for real. This times both on the same
/// stretch of the same footage:
///  A. 40 stills, one every 150 ms of footage, each awaited (what the popup does): wall time per still, and how many took longer than the 150 ms step;
///  B. the player running for 6 s: how many new frames it delivers per second and the longest gap between two.
/// Runs at launch when `CROP_BENCH=1` (`CROP_BENCH_VIDEO` names the video, default `iphone-footage.MOV`; `CROP_BENCH_START` the second to start at,
/// default 5) and writes `Documents/crop_bench.txt`. CPU time is the whole process's user + system time. Run it on a real iPhone.
@MainActor
enum CropFrameBench {
    static func runIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CROP_BENCH"] != nil else { return }
        let report = await run(video: environment["CROP_BENCH_VIDEO"] ?? "iphone-footage.MOV", start: Double(environment["CROP_BENCH_START"] ?? "") ?? 5)
        NSLog("CROPBENCH\n%@", report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("crop_bench.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func cpuMs() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
        return ms(usage.ru_utime) + ms(usage.ru_stime)
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
    }

    private static func run(video: String, start: Double) async -> String {
        guard let url = bundledURL(filename: video) else { return "no video named \(video) in ImportedMedia or the bundle" }
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let size = (try? await track?.load(.naturalSize)) ?? .zero
        let fps = (try? await track?.load(.nominalFrameRate)) ?? 0
        var lines = [String(format: "%@  %.1f s, %.0f x %.0f, %.0f fps, starting at %.1f s", video, duration, size.width, size.height, fps, start)]

        // A. stills, as the popup asks for them.
        var times: [Double] = []
        for i in 0..<40 { times.append(start + Double(i) * 0.15) }
        var walls: [Double] = []
        let cpuA = cpuMs()
        let beganA = CACurrentMediaTime()
        for (i, t) in times.enumerated() {
            let began = CACurrentMediaTime()
            _ = await VideoFrameCache.shared.frame(assetId: "cropbench-\(i)", url: url, atSeconds: t)
            walls.append((CACurrentMediaTime() - began) * 1000)
        }
        let totalA = CACurrentMediaTime() - beganA
        let late = walls.filter { $0 > 150 }.count
        lines.append(String(format: "A  stills every 150 ms: wall median %.0f ms, p95 %.0f ms, max %.0f ms; %d of %d took longer than the 150 ms step; "
                            + "40 stills = %.1f s for %.1f s of footage (%.1f stills/s); CPU %.0f ms/s",
                            percentile(walls, 0.5), percentile(walls, 0.95), walls.max() ?? 0, late, walls.count, totalA, 6.0, 40 / totalA,
                            (cpuMs() - cpuA) / totalA))

        // B. the player running for real.
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let cpuB = cpuMs()
        let beganB = CACurrentMediaTime()
        player.play()
        var stamps: [Double] = []
        while CACurrentMediaTime() - beganB < 6 {
            let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: itemTime), output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) != nil {
                stamps.append(CACurrentMediaTime())
            }
            try? await Task.sleep(for: .milliseconds(4))
        }
        player.pause()
        let elapsedB = CACurrentMediaTime() - beganB
        let gaps = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
        lines.append(String(format: "B  AVPlayer + video output: %d new frames in %.1f s = %.1f frames/s; gap between frames median %.0f ms, p95 %.0f ms, max %.0f ms; CPU %.0f ms/s",
                            stamps.count, elapsedB, Double(stamps.count) / elapsedB, percentile(gaps, 0.5), percentile(gaps, 0.95), gaps.max() ?? 0,
                            (cpuMs() - cpuB) / elapsedB))
        return lines.joined(separator: "\n")
    }
}
#endif
