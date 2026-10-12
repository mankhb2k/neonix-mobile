#if DEBUG
import AVFoundation
import Darwin
import UIKit

/// What the Filter grid costs the CPU (user 2026-10-12, "measure first"): the way it was first built - decode a fresh frame
/// at 300 px, render 16 thumbnails at 300 px, no cache - against the current way - the filmstrip's own thumbnail, 160 px,
/// cached. Runs at launch when `FILTER_BENCH=1` is set (`FILTER_BENCH_VIDEO` names the video, default
/// `iphone-footage.MOV`, falling back to a bundled sample) and writes `Documents/filter_bench.txt`.
///
/// CPU time is the whole process's user + system time over the stage (`getrusage`), so it counts every thread but **not**
/// the GPU. Wall time is real elapsed time. Run it on a real iPhone; the simulator's numbers are only a sanity check.
@MainActor
enum FilterThumbnailBench {
    struct Sample { var wallMs: Double; var cpuMs: Double }

    static func runIfRequested() async {
        guard ProcessInfo.processInfo.environment["FILTER_BENCH"] != nil else { return }
        let report = await run()
        NSLog("FILTERBENCH\n%@", report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("filter_bench.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Measuring

    private static func cpuMs() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
        return ms(usage.ru_utime) + ms(usage.ru_stime)
    }

    private static func measure<T>(_ body: () async -> T) async -> (T, Sample) {
        let wall = CACurrentMediaTime(), cpu = cpuMs()
        let value = await body()
        return (value, Sample(wallMs: (CACurrentMediaTime() - wall) * 1000, cpuMs: cpuMs() - cpu))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    private static func line(_ name: String, _ samples: [Sample]) -> String {
        let wall = samples.map(\.wallMs), cpu = samples.map(\.cpuMs)
        return String(format: "%-34@ wall median %7.1f ms  CPU median %7.1f ms   (first %7.1f / %7.1f, n=%d)",
                      name as NSString, median(wall), median(cpu), wall.first ?? 0, cpu.first ?? 0, samples.count)
    }

    // MARK: The two pipelines

    /// The original source: a fresh frame decoded at up to 300 px.
    private static func legacySource(url: URL, seconds: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// 16 presets rendered one after the other, off the main actor, no cache.
    private static func renderAll(_ source: CGImage) async -> Int {
        await Task.detached(priority: .userInitiated) {
            var done = 0
            for preset in FilterCatalog.presets {
                let filter = compileFilter(id: "bench-\(preset.id)", presets: adjustPresets(for: preset.values))
                if FilterRenderer.apply(filter, to: source) != nil { done += 1 }
            }
            return done
        }.value
    }

    // MARK: The run

    private static func run() async -> String {
        var out: [String] = []
        let names = [ProcessInfo.processInfo.environment["FILTER_BENCH_VIDEO"], "iphone-footage.MOV", "13792197_1080_1920_30fps.mp4"].compactMap { $0 }
        guard let name = names.first(where: { bundledURL(filename: $0) != nil }), let url = bundledURL(filename: name),
              let durationMs = await AssetDurationCache.shared.durationMs(url: url)
        else { return "FILTER BENCH: no video found (tried \(names))" }

        let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        let size = try? await track?.load(.naturalSize)
        out.append("Filter thumbnail bench - video \(name), \(Int(durationMs / 1000)) s, \(Int(size?.width ?? 0))x\(Int(size?.height ?? 0)), \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
        out.append("CPU = process user+system time over the stage (all threads, no GPU). 16 presets per grid.")

        // The very first grid in a process also pays Core Image / Metal first-use setup. Decode a frame first (not timed) so
        // only the rendering is charged, then charge it once, with a small image, before either pipeline is timed.
        let warmSource = FilterThumbnails.downscaled((await legacySource(url: url, seconds: 1)) ?? UIImage().cgImage!, maxPixels: 64)
        let (firstRender, firstSample) = await measure { await renderAll(warmSource) }
        out.append(String(format: "first-ever grid render in this process (64 px, cold Core Image, no decode): wall %.1f ms, CPU %.1f ms (%d rendered)", firstSample.wallMs, firstSample.cpuMs, firstRender))
        let (_, secondSample) = await measure { await renderAll(warmSource) }
        out.append(String(format: "second grid render, same image (warm): wall %.1f ms, CPU %.1f ms", secondSample.wallMs, secondSample.cpuMs))

        let trials = (1...12).map { Double($0) * durationMs / 13 / 1000 }   // seconds; distinct frames so nothing is reused by luck

        // The filmstrip the timeline already builds (not part of the Filter cost; built first because "current" reads it).
        let assetId = "bench"
        let step = FilmstripGrid.baseStepMs(durationMs: durationMs)
        let expected = Int(durationMs / step) + 1
        let (_, filmstripBuild) = await measure { () async -> Void in
            VideoFrameCache.shared.ensureBaseThumbnails(assetId: assetId, url: url, durationMs: durationMs, priorityMs: durationMs / 2)
            let deadline = CACurrentMediaTime() + 90
            while (VideoFrameCache.shared.baseThumbs[assetId]?.count ?? 0) < expected, CACurrentMediaTime() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        out.append(String(format: "filmstrip build (done by the timeline anyway, %d thumbnails): wall %.0f ms, CPU %.0f ms", VideoFrameCache.shared.baseThumbs[assetId]?.count ?? 0, filmstripBuild.wallMs, filmstripBuild.cpuMs))

        var legacySourceSamples: [Sample] = [], legacyRenderSamples: [Sample] = [], legacyTotal: [Sample] = []
        var rawThumb: [Sample] = [], preparedThumb: [Sample] = [], bareRender: [Sample] = []
        var newSource: [Sample] = [], newRender: [Sample] = [], newTotal: [Sample] = [], cachedTotal: [Sample] = []

        func original(_ t: Double) async {
            let (image, s1) = await measure { await legacySource(url: url, seconds: t) }
            guard let image else { return }
            let (_, s2) = await measure { await renderAll(image) }
            legacySourceSamples.append(s1); legacyRenderSamples.append(s2)
            legacyTotal.append(Sample(wallMs: s1.wallMs + s2.wallMs, cpuMs: s1.cpuMs + s2.cpuMs))
        }
        func current(_ t: Double) async {
            FilterThumbnails.clearCache()
            let (source, s1) = await measure { await FilterThumbnails.videoSource(assetId: assetId, url: url, sourceMs: t * 1000) }
            guard let source else { return }
            let (_, s2) = await measure { await FilterThumbnails.render(source: source, presets: FilterCatalog.presets) { _, _ in } }
            newSource.append(s1); newRender.append(s2)
            newTotal.append(Sample(wallMs: s1.wallMs + s2.wallMs, cpuMs: s1.cpuMs + s2.cpuMs))
            let (_, s3) = await measure { await FilterThumbnails.render(source: source, presets: FilterCatalog.presets) { _, _ in } }
            cachedTotal.append(s3)
            let (_, s4) = await measure { await renderAll(source.image) }   // same pixels, no main-actor hops, no cache
            bareRender.append(s4)
            if let thumbs = VideoFrameCache.shared.baseThumbs[assetId],
               let index = thumbs.keys.min(by: { abs(Double($0) * step - t * 1000) < abs(Double($1) * step - t * 1000) }),
               let thumb = thumbs[index], let raw = thumb.cgImage {
                let (_, sRaw) = await measure { await renderAll(raw) }
                rawThumb.append(sRaw)
                let k = FilterThumbnails.thumbnailPixels / CGFloat(max(raw.width, raw.height))
                if let prepared = await thumb.byPreparingThumbnail(ofSize: CGSize(width: CGFloat(raw.width) * k, height: CGFloat(raw.height) * k))?.cgImage {
                    let (_, sPrep) = await measure { await renderAll(prepared) }
                    preparedThumb.append(sPrep)
                }
            }
        }
        // Interleaved, and the order swaps every trial, so drift (heat, background load) hits both pipelines alike.
        for (i, t) in trials.enumerated() {
            if i % 2 == 0 { await original(t); await current(t) } else { await current(t); await original(t) }
        }

        out.append("")
        out.append("Summary (median of \(trials.count) frames):")
        out.append(line("original: decode source", legacySourceSamples))
        out.append(line("original: render 16 @ 300 px", legacyRenderSamples))
        out.append(line("original: TOTAL", legacyTotal))
        out.append(line("current: filmstrip source", newSource))
        out.append(line("current: render 16 @ 160 px", newRender))
        out.append(line("   same, bare (no hops/cache)", bareRender))
        out.append(line("   filmstrip thumb as is (288 px)", rawThumb))
        out.append(line("   preparingThumbnail 160 px", preparedThumb))
        out.append(line("current: TOTAL (cold cache)", newTotal))
        out.append(line("current: reopen (all cached)", cachedTotal))
        let before = median(legacyTotal.map(\.cpuMs)), after = median(newTotal.map(\.cpuMs))
        if before > 0 { out.append(String(format: "CPU: %.1f ms -> %.1f ms (%.0f%% of the original); wall: %.1f -> %.1f ms", before, after, after / before * 100, median(legacyTotal.map(\.wallMs)), median(newTotal.map(\.wallMs)))) }
        return out.joined(separator: "\n")
    }
}
#endif
