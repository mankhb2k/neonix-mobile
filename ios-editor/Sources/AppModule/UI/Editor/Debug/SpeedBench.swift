#if DEBUG
import AVFoundation
import UIKit

/// What does the playback pipeline do at 0.1x ... 10x? (PLAYBACK_PIPELINE.md §9, "Tốc độ".) The Speed tool's range is 0.1x-10x (user
/// 2026-10-15); before the editor plays a clip at such a rate this measures, with the real `iphone-footage.MOV`, the same way the app
/// plays video (`AVPlayer`, `automaticallyWaitsToMinimizeStalling = false`, muted, `rate` set directly):
/// - per rate and per path - the raw video layer, and the `AVPlayerItemVideoOutput` copy the filtered path uses - the rate the clock really
///   advances at, the time to start moving, display-link hitches (p50/p95/max tick), stalls, CPU, thermal state;
/// - a rate step response: 1x -> 10x -> 0.1x -> 1x -> 0.25x, how long each change takes to show in the clock (what a speed *curve* does).
/// Runs at launch when `SPEED_BENCH=1` is set (optional `SPEED_BENCH_VIDEO` = a file path); writes `Documents/speed_bench.txt`.
@MainActor
enum SpeedBench {
    enum Path: String { case layer = "AVPlayerLayer (raw video)", output = "VideoOutput copy (filtered video, no Core Image)" }

    static func runIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["SPEED_BENCH"] != nil else { return }
        let report = await run(videoOverride: env["SPEED_BENCH_VIDEO"])
        NSLog("SPEEDBENCH\n%@", report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("speed_bench.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Probe

    private struct Sample { var wall: Double; var media: Double; var fresh: Bool }

    /// Samples the player's clock on every display refresh (and, with an output, whether a new frame was waiting).
    private final class Probe: NSObject {
        var samples: [Sample] = []
        var player: AVPlayer?
        var output: AVPlayerItemVideoOutput?
        private var link: CADisplayLink?

        func start() {
            link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }

        func stop() { link?.invalidate(); link = nil }

        @objc private func tick(_ link: CADisplayLink) {
            guard let player else { return }
            var fresh = false
            if let output {
                let time = output.itemTime(forHostTime: CACurrentMediaTime())
                if output.hasNewPixelBuffer(forItemTime: time), output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) != nil { fresh = true }
            }
            samples.append(Sample(wall: CACurrentMediaTime(), media: player.currentTime().seconds, fresh: fresh))
        }
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
    }

    /// A fresh player at `startAt` seconds, ready to play, with the layer on screen or the output attached.
    private static func makePlayer(url: URL, path: Path, startAt: Double) async -> (AVPlayer, AVPlayerItemVideoOutput?, UIView?) {
        let item = AVPlayerItem(url: url)
        var output: AVPlayerItemVideoOutput?
        if path == .output {
            output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(output!)
        }
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = 0
        var view: UIView?
        if path == .layer, let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            let host = UIView(frame: CGRect(x: 0, y: 100, width: window.bounds.width, height: window.bounds.width))
            let layer = AVPlayerLayer(player: player)
            layer.frame = host.bounds
            layer.videoGravity = .resizeAspect
            host.layer.addSublayer(layer)
            window.addSubview(host)
            view = host
        }
        for _ in 0..<400 where item.status != .readyToPlay { try? await Task.sleep(nanoseconds: 10_000_000) }
        await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return (player, output, view)
    }

    // MARK: One rate

    private struct Row {
        var rate: Double, path: Path
        var achieved = 0.0, startupMs = 0.0
        var p50 = 0.0, p95 = 0.0, maxTick = 0.0
        var stalls = 0, cpuPercent = 0.0
        var framesPerSecond: Double?
    }

    private static func measure(url: URL, rate: Double, path: Path, seconds: Double, startAt: Double) async -> Row {
        let (player, output, view) = await makePlayer(url: url, path: path, startAt: startAt)
        let probe = Probe()
        probe.player = player; probe.output = output
        probe.start()
        let cpu0 = cpuSeconds(), wall0 = CACurrentMediaTime()
        let startMedia = player.currentTime().seconds
        player.rate = Float(rate)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        let cpu1 = cpuSeconds(), wall1 = CACurrentMediaTime()
        probe.stop()
        player.pause()
        view?.removeFromSuperview()

        var row = Row(rate: rate, path: path)
        let samples = probe.samples
        row.cpuPercent = (cpu1 - cpu0) / max(wall1 - wall0, 0.001) * 100
        if let first = samples.first(where: { abs($0.media - startMedia) > 0.001 }) { row.startupMs = (first.wall - wall0) * 1000 }
        let settled = samples.filter { $0.wall >= wall0 + 0.6 }
        if let a = settled.first, let b = settled.last, b.wall > a.wall { row.achieved = (b.media - a.media) / (b.wall - a.wall) }
        let intervals = zip(settled, settled.dropFirst()).map { ($1.wall - $0.wall) * 1000 }
        row.p50 = percentile(intervals, 0.5); row.p95 = percentile(intervals, 0.95); row.maxTick = intervals.max() ?? 0
        // A stall: the clock did not move for 5 or more display ticks in a row.
        var run = 0
        for (a, b) in zip(settled, settled.dropFirst()) {
            if abs(b.media - a.media) < 1e-4 { run += 1; if run == 5 { row.stalls += 1 } } else { run = 0 }
        }
        if output != nil, let a = settled.first, let b = settled.last, b.wall > a.wall {
            row.framesPerSecond = Double(settled.filter(\.fresh).count) / (b.wall - a.wall)
        }
        return row
    }

    // MARK: Step response

    /// Rate changes while playing: for each change, the time until the clock's speed (over 100 ms windows) is within 25 % of the target.
    private static func stepResponse(url: URL) async -> String {
        let steps: [(at: Double, rate: Double)] = [(0, 1), (1.5, 10), (3.0, 0.1), (4.5, 1), (6.0, 0.25)]
        let (player, _, view) = await makePlayer(url: url, path: .layer, startAt: 3)
        let probe = Probe(); probe.player = player; probe.start()
        let wall0 = CACurrentMediaTime()
        var changeWalls: [Double] = []
        for step in steps {
            let wait = wall0 + step.at - CACurrentMediaTime()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            changeWalls.append(CACurrentMediaTime())
            player.rate = Float(step.rate)
        }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        probe.stop(); player.pause(); view?.removeFromSuperview()

        let samples = probe.samples
        // The clock's speed in a sliding 100 ms window.
        func speed(at index: Int) -> Double? {
            guard let j = (0..<index).reversed().first(where: { samples[index].wall - samples[$0].wall >= 0.1 }) else { return nil }
            return (samples[index].media - samples[j].media) / (samples[index].wall - samples[j].wall)
        }
        var out = "STEP RESPONSE (raw video layer; speed over 100 ms windows; settled = within 25 % of the target)\n"
        for (k, step) in steps.enumerated() {
            let start = changeWalls[k]
            let end = k + 1 < steps.count ? changeWalls[k + 1] : Double.greatestFiniteMagnitude
            var settledAfter: Double?
            var jumped = 0.0
            var peak = 0.0
            for i in samples.indices where samples[i].wall >= start && samples[i].wall < end {
                if let v = speed(at: i) {
                    peak = max(peak, v)
                    if settledAfter == nil, abs(v - step.rate) <= 0.25 * step.rate { settledAfter = (samples[i].wall - start) * 1000 }
                }
                if i > 0, samples[i].media < samples[i - 1].media - 0.001 { jumped += 1 }
            }
            out += String(format: "  -> %5.2fx at t=%.1fs: %@, backward clock steps %.0f\n", step.rate, step.at,
                          settledAfter.map { String(format: "settled after %.0f ms", $0) } ?? "never settled", jumped)
        }
        return out
    }

    // MARK: Curve following

    /// A speed curve played the way the engine plays it (`StagePlayerSession.follow(rate:)`: the player's rate follows the curve at the current
    /// source position, touched only when it is off by more than 3 %): how far the footage is from where the curve says it should be, over time.
    /// Footage 1x -> 6x -> 0.5x -> 1x over its first 40 s, 15 s of wall clock.
    private static func curveFollow(url: URL) async -> String {
        let span = 40_000.0
        guard let curve = SpeedCurve(points: [V2SpeedPoint(sourceMs: 0, rate: 1), V2SpeedPoint(sourceMs: 12_000, rate: 6),
                                              V2SpeedPoint(sourceMs: 26_000, rate: 0.5), V2SpeedPoint(sourceMs: span, rate: 1)], span: span) else { return "" }
        let startAt = 2.0
        let (player, _, view) = await makePlayer(url: url, path: .layer, startAt: startAt)
        let probe = Probe(); probe.player = player; probe.start()
        let wall0 = CACurrentMediaTime()
        player.rate = Float(curve.rate(atSource: 0))
        var changes = 0
        var errors: [(t: Double, errMs: Double, rate: Double)] = []
        while CACurrentMediaTime() - wall0 < 15 {
            try? await Task.sleep(nanoseconds: 16_000_000)
            let source = player.currentTime().seconds * 1000 - startAt * 1000
            let desired = Float(curve.rate(atSource: source))
            if player.rate != 0, abs(player.rate - desired) / desired > 0.03 { player.rate = desired; changes += 1 }
            let t = CACurrentMediaTime() - wall0
            errors.append((t, source - curve.sourceMs(atOutput: t * 1000), Double(player.rate)))
        }
        probe.stop(); player.pause(); view?.removeFromSuperview()
        var out = "CURVE FOLLOW (footage 1x -> 6x -> 0.5x -> 1x; the player's rate follows the curve at its own source position, 3 % tolerance)\n"
        out += "  curve length \(Int(curve.outputDuration)) ms for \(Int(span)) ms of footage; rate changes in 15 s: \(changes)\n"
        for second in [1.0, 2, 3, 4, 5, 6, 8, 10, 12, 14] {
            if let sample = errors.first(where: { $0.t >= second }) {
                out += String(format: "  t=%4.1fs  footage ahead(+)/behind(-) the curve: %+6.0f ms (source ms), rate %.2f\n", sample.t, sample.errMs, sample.rate)
            }
        }
        out += String(format: "  worst error %.0f ms, at the end %+.0f ms\n", errors.map { abs($0.errMs) }.max() ?? 0, errors.last?.errMs ?? 0)
        return out
    }

    // MARK: Report

    private static func run(videoOverride: String?) async -> String {
        var system = utsname(); uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let process = ProcessInfo.processInfo
        var out = "SPEED BENCH \(model) iOS \(UIDevice.current.systemVersion) thermal \(process.thermalState.rawValue) lowPower \(process.isLowPowerModeEnabled)\n"
        let fallback = MediaImportService.importedMediaDirectory.appendingPathComponent("iphone-footage.MOV")
        let url = videoOverride.map { URL(fileURLWithPath: $0) } ?? fallback
        guard FileManager.default.fileExists(atPath: url.path) else { return out + "footage not found: \(url.path)\n" }
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let size = (try? await track.load(.naturalSize)) ?? .zero
            let fps = (try? await track.load(.nominalFrameRate)) ?? 0
            let codec = (try? await track.load(.formatDescriptions).first).map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            out += String(format: "footage %@: %.1f s, %.0fx%.0f, %.1f fps, codec %@, %.0f MB\n", url.lastPathComponent, duration, size.width, size.height, fps,
                          String(format: "%c%c%c%c", (codec >> 24) & 255, (codec >> 16) & 255, (codec >> 8) & 255, codec & 255), Double(bytes) / 1e6)
        }
        // The flags only mean something once the item is ready.
        let (probePlayer, _, probeView) = await makePlayer(url: url, path: .output, startAt: 0)
        if let item = probePlayer.currentItem {
            out += "item (ready): canPlaySlowForward \(item.canPlaySlowForward) canPlayFastForward \(item.canPlayFastForward) audioTimePitchAlgorithm \(item.audioTimePitchAlgorithm.rawValue)\n\n"
        }
        probeView?.removeFromSuperview()

        // Optional `SPEED_BENCH_RATES=8,9,10` narrows the run (and skips the step response) to look closer at some rates.
        let env = ProcessInfo.processInfo.environment
        let custom = env["SPEED_BENCH_RATES"].map { $0.split(separator: ",").compactMap { Double($0) } }
        if env["SPEED_BENCH_CURVE"] != nil { return out + "\n" + (await curveFollow(url: url)) + "\nthermal at end \(process.thermalState.rawValue)\n" }
        let rates: [Double] = custom ?? [0.1, 0.25, 0.5, 1, 2, 4, 6, 8, 10]
        for path in [Path.layer, .output] where custom == nil || path == .output {
            out += "PATH \(path.rawValue)\n rate | achieved | start ms | tick p50 / p95 / max ms | stalls | CPU %  | frames/s\n"
            for rate in rates {
                // Long enough to settle, short enough to stay inside the footage at 10x (5 s of wall = 50 s of footage).
                let wanted = rate >= 8 ? 4.5 : (rate <= 0.25 ? 6 : 5)
                let startAt = 2.0
                let seconds = min(wanted, max((duration - startAt - 1) / rate, 1))   // never run past the end of the footage
                let row = await measure(url: url, rate: rate, path: path, seconds: seconds, startAt: startAt)
                out += String(format: " %4.2fx | %6.2fx  | %7.0f  | %5.1f / %5.1f / %5.1f | %5d  | %5.0f  | %@\n", rate, row.achieved, row.startupMs, row.p50, row.p95, row.maxTick,
                              row.stalls, row.cpuPercent, row.framesPerSecond.map { String(format: "%.0f", $0) } ?? "-")
                try? await Task.sleep(nanoseconds: 700_000_000)   // let the decoder and the phone settle between runs
            }
            out += "\n"
        }
        if custom == nil { out += await stepResponse(url: url) }
        out += "\nthermal at end \(process.thermalState.rawValue)\n"
        return out
    }
}
#endif
