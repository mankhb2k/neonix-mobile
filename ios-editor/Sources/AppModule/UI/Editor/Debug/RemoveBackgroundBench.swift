#if DEBUG
import AVFoundation
import Darwin
import ImageIO
import UIKit
import Vision

/// What Vision's background removal costs and gives (user 2026-10-18: "find out about `VNGenerateForegroundInstanceMaskRequest` to finish Remove BG").
/// One second of footage (30 frames, 1/30 s apart) is decoded once, then run through the request at three input sizes, plus the people-only request
/// for comparison. For each: the first call (model load), the median / p95 / max per frame, what the mask looks like (size, pixel format, instances),
/// and how stable it is from one frame to the next (IoU of the foreground between neighbours - a flicker proxy).
/// Runs at launch when `REMOVEBG_BENCH=1` (`REMOVEBG_BENCH_VIDEO` names the video, default `iphone-footage.MOV`; `REMOVEBG_BENCH_START` the second to
/// start at, default 5) and writes `Documents/removebg_bench.txt`. Run it on a real iPhone: the simulator has no Neural Engine.
@MainActor
enum RemoveBackgroundBench {
    static func runIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["REMOVEBG_BENCH"] != nil else { return }
        let report = await run(video: environment["REMOVEBG_BENCH_VIDEO"] ?? "iphone-footage.MOV", start: Double(environment["REMOVEBG_BENCH_START"] ?? "") ?? 5)
        NSLog("REMOVEBGBENCH\n%@", report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("removebg_bench.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
    }

    private static func downscaled(_ image: CGImage, longSide: Int) -> CGImage {
        let k = Double(longSide) / Double(max(image.width, image.height))
        guard k < 1 else { return image }
        let width = Int(Double(image.width) * k), height = Int(Double(image.height) * k)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// The foreground as one bit per pixel (a label map: 0 = background).
    private static func bits(of buffer: CVPixelBuffer) -> [Bool] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        var out = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { out[y * width + x] = row[x] != 0 }
        }
        return out
    }

    private static func iou(_ a: [Bool], _ b: [Bool]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var both = 0, either = 0
        for i in 0..<a.count { if a[i] && b[i] { both += 1 }; if a[i] || b[i] { either += 1 } }
        return either == 0 ? nil : Double(both) / Double(either)
    }

    private static func formatName(_ buffer: CVPixelBuffer) -> String {
        let f = CVPixelBufferGetPixelFormatType(buffer)
        switch f {
        case kCVPixelFormatType_OneComponent8: return "OneComponent8"
        case kCVPixelFormatType_OneComponent32Float: return "OneComponent32Float"
        case kCVPixelFormatType_OneComponent16Half: return "OneComponent16Half"
        case kCVPixelFormatType_32BGRA: return "32BGRA"
        default: return String(format: "0x%08X", f)
        }
    }

    private static func saveCutouts(frame: CGImage, prefix: String = "removebg") -> String {
        let image = downscaled(frame, longSide: 1280)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else { return "cut-outs: no mask" }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let context = CIContext()
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let green = CIImage(color: CIColor(red: 0.1, green: 0.8, blue: 0.2)).cropped(to: extent)
        var done: [String] = []
        func save(_ output: CIImage, _ name: String) {
            guard let cg = context.createCGImage(output.cropped(to: extent), from: extent.integral, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()),
                  let data = UIImage(cgImage: cg).pngData() else { return }
            try? data.write(to: documents.appendingPathComponent(name))
            done.append(name)
        }
        save(CIImage(cgImage: image), "\(prefix)_original.png")
        if let cut = try? observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false) {
            save(CIImage(cvPixelBuffer: cut).composited(over: green), "\(prefix)_vision_cutout.png")
        }
        if let matte = try? observation.generateMask(forInstances: observation.allInstances) {
            let mask = CIImage(cvPixelBuffer: matte)
            let scaled = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
            save(CIImage(cgImage: image).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: green, kCIInputMaskImageKey: scaled]), "\(prefix)_matte_cutout.png")
        }
        // People only, the most accurate level: a bigger matte, made for portraits.
        let people = VNGeneratePersonSegmentationRequest()
        people.qualityLevel = .accurate
        let began = CACurrentMediaTime()
        if (try? handler.perform([people])) != nil, let matte = people.results?.first?.pixelBuffer {
            let mask = CIImage(cvPixelBuffer: matte)
            let scaled = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
            save(CIImage(cgImage: image).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: green, kCIInputMaskImageKey: scaled]), "\(prefix)_person_cutout.png")
            done.append(String(format: "(person accurate %d ms, matte %d x %d)", Int((CACurrentMediaTime() - began) * 1000), CVPixelBufferGetWidth(matte), CVPixelBufferGetHeight(matte)))
        }
        return "cut-outs saved: \(done.joined(separator: ", "))"
    }

    private static func run(video: String, start: Double) async -> String {
        guard let url = bundledURL(filename: video) else { return "no video named \(video)" }
        var lines = ["\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion); \(video) from \(start) s"]
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var frames: [CGImage] = []
        for i in 0..<30 {
            if let image = try? await generator.image(at: CMTime(seconds: start + Double(i) / 30, preferredTimescale: 600)).image { frames.append(image) }
        }
        guard let first = frames.first else { return lines.joined(separator: "\n") + "\nno frames decoded" }
        lines.append("decoded \(frames.count) frames, \(first.width) x \(first.height)")

        for longSide in [1920, 1280, 960] {
            let inputs = frames.map { downscaled($0, longSide: longSide) }
            var walls: [Double] = [], maskWalls: [Double] = [], counts: [Int] = [], masks: [[Bool]] = []
            var firstWall = 0.0, shape = ""
            for (i, input) in inputs.enumerated() {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let began = CACurrentMediaTime()
                do { try VNImageRequestHandler(cgImage: input).perform([request]) } catch { lines.append("foreground \(longSide): request failed: \(error)"); break }
                let wall = (CACurrentMediaTime() - began) * 1000
                if i == 0 { firstWall = wall } else { walls.append(wall) }
                guard let observation = request.results?.first else { counts.append(0); masks.append([]); continue }
                counts.append(observation.allInstances.count)
                masks.append(bits(of: observation.instanceMask))
                if i == 0 {
                    let label = observation.instanceMask
                    shape = "label map \(CVPixelBufferGetWidth(label)) x \(CVPixelBufferGetHeight(label)) \(formatName(label))"
                    // The soft matte and the cut-out picture, once each.
                    let m0 = CACurrentMediaTime()
                    if let matte = try? observation.generateMask(forInstances: observation.allInstances) {
                        shape += "; soft mask \(CVPixelBufferGetWidth(matte)) x \(CVPixelBufferGetHeight(matte)) \(formatName(matte)) in \(Int((CACurrentMediaTime() - m0) * 1000)) ms"
                    }
                    let c0 = CACurrentMediaTime()
                    if let cut = try? observation.generateMaskedImage(ofInstances: observation.allInstances, from: VNImageRequestHandler(cgImage: input), croppedToInstancesExtent: false) {
                        shape += "; cut-out \(CVPixelBufferGetWidth(cut)) x \(CVPixelBufferGetHeight(cut)) \(formatName(cut)) in \(Int((CACurrentMediaTime() - c0) * 1000)) ms"
                    }
                }
                // The soft matte per frame, as the cost of using the result.
                let m = CACurrentMediaTime()
                _ = try? observation.generateMask(forInstances: observation.allInstances)
                maskWalls.append((CACurrentMediaTime() - m) * 1000)
            }
            var ious: [Double] = []
            for (a, b) in zip(masks, masks.dropFirst()) { if let value = iou(a, b) { ious.append(value) } }
            lines.append(String(format: "foreground @%d px long side: first call %.0f ms, then median %.0f / p95 %.0f / max %.0f ms; soft mask per frame median %.0f ms; instances %d...%d; "
                                + "neighbour IoU mean %.3f min %.3f (n=%d)\n   %@",
                                longSide, firstWall, percentile(walls, 0.5), percentile(walls, 0.95), walls.max() ?? 0, percentile(maskWalls, 0.5),
                                counts.min() ?? 0, counts.max() ?? 0, ious.isEmpty ? 0 : ious.reduce(0, +) / Double(ious.count), ious.min() ?? 0, ious.count, shape))
        }

        // Pictures to look at: frame 0 at 1280, cut out two ways over green - Vision's own cut-out, and the soft 512 x 512 matte stretched over the frame.
        lines.append(saveCutouts(frame: frames[0]))
        if let portraitURL = bundledURL(filename: "pexels-followingnyc-38428141.jpg"), let source = CGImageSourceCreateWithURL(portraitURL as CFURL, nil),
           let portrait = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                                                       kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) {
            lines.append("portrait photo: " + saveCutouts(frame: portrait, prefix: "removebg_portrait"))
        }

        // People only: the request made for video.
        for (name, quality) in [("balanced", VNGeneratePersonSegmentationRequest.QualityLevel.balanced), ("fast", .fast), ("accurate", .accurate)] {
            let handler = VNSequenceRequestHandler()
            var walls: [Double] = []
            var shape = ""
            for (i, image) in frames.map({ downscaled($0, longSide: 1280) }).enumerated() {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = quality
                let began = CACurrentMediaTime()
                do { try handler.perform([request], on: image) } catch { lines.append("person \(name): failed: \(error)"); break }
                if i > 0 { walls.append((CACurrentMediaTime() - began) * 1000) }
                if i == 0, let mask = request.results?.first?.pixelBuffer {
                    shape = "mask \(CVPixelBufferGetWidth(mask)) x \(CVPixelBufferGetHeight(mask)) \(formatName(mask))"
                }
            }
            lines.append(String(format: "person segmentation (%@) @1280: median %.0f / p95 %.0f / max %.0f ms (sequence handler); %@", name, percentile(walls, 0.5), percentile(walls, 0.95), walls.max() ?? 0, shape))
        }
        return lines.joined(separator: "\n")
    }
}
#endif
