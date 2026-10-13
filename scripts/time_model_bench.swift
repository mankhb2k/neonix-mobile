import AVFoundation
import CoreGraphics
import Foundation

// MARK: shared
struct Rate { let name: String; let num: Int32; let den: Int64
    var fps: Double { Double(num) / Double(den) }
    func pts(_ k: Int) -> CMTime { CMTime(value: Int64(k) * den, timescale: num) }
}
let rates = [Rate(name: "24", num: 24, den: 1), Rate(name: "25", num: 25, den: 1), Rate(name: "30", num: 30, den: 1),
             Rate(name: "23.976", num: 24000, den: 1001), Rate(name: "29.97", num: 30000, den: 1001),
             Rate(name: "59.94", num: 60000, den: 1001), Rate(name: "60", num: 60, den: 1)]

// MARK: 1. real footage
func inspectReal(_ path: String) async {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else { print("no track"); return }
    let nominal = try? await track.load(.nominalFrameRate)
    let minDur = try? await track.load(.minFrameDuration)
    let ts = try? await track.load(.naturalTimeScale)
    print("REAL \(URL(fileURLWithPath: path).lastPathComponent): nominalFrameRate=\(nominal ?? 0) minFrameDuration=\(minDur.map { "\($0.value)/\($0.timescale)" } ?? "?") naturalTimeScale=\(ts ?? 0)")
    guard let reader = try? AVAssetReader(asset: asset) else { return }
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(out); reader.startReading()
    var pts: [CMTime] = []
    while pts.count < 3000, let s = out.copyNextSampleBuffer() { pts.append(CMSampleBufferGetPresentationTimeStamp(s)) }
    let sorted = pts.sorted { $0 < $1 }
    var deltas: [String: Int] = [:]
    for (a, b) in zip(sorted, sorted.dropFirst()) { let d = CMTimeSubtract(b, a); deltas["\(d.value)/\(d.timescale)", default: 0] += 1 }
    print("  first \(sorted.count) samples, PTS deltas (value/timescale: count): \(deltas.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key): \($0.value)" })")
}

// MARK: 2. arithmetic: how the time model maps onto exact frame PTS
func arithmetic() {
    print("\nARITH (1 hour of frames; exact PTS = k*den/num s)")
    print("rate     | ts600 round: maxErr ms, frames asked EARLIER than PTS | int-ms round: maxErr ms, EARLIER | exact CMTime")
    for r in rates {
        let n = Int(3600 * r.fps)
        var maxA = 0.0, earlyA = 0, maxB = 0.0, earlyB = 0
        for k in 0..<n {
            let exact = Double(k) * Double(r.den) / Double(r.num)            // seconds
            let t600 = (exact * 600).rounded() / 600                          // CMTime(seconds:, 600)
            let ms = (exact * 1000).rounded() / 1000                          // integer-ms Double
            if t600 < exact - 1e-12 { earlyA += 1 }; maxA = max(maxA, abs(t600 - exact) * 1000)
            if ms < exact - 1e-12 { earlyB += 1 }; maxB = max(maxB, abs(ms - exact) * 1000)
        }
        print(String(format: "%-8@ | %.3f ms, %5.1f%% | %.3f ms, %5.1f%% | 0", r.name as NSString, maxA, 100 * Double(earlyA) / Double(n), maxB, 100 * Double(earlyB) / Double(n)))
    }
    // accumulation: summing a per-frame duration repeatedly
    print("\nACCUM: after 1 hour of frames, the time reached by adding one frame at a time")
    for r in rates {
        let n = Int(3600 * r.fps)
        let exact = Double(n) * Double(r.den) / Double(r.num) * 1000
        let perFrameRoundedMs = (Double(r.den) / Double(r.num) * 1000).rounded()   // frame length stored as integer ms
        let acc = Double(n) * perFrameRoundedMs
        var sum = 0.0; let step = Double(r.den) / Double(r.num) * 1000; for _ in 0..<n { sum += step }
        print(String(format: "%-8@ | integer-ms frame: off by %8.1f ms (%.1f frames) | Double ms sum: off by %.9f ms", r.name as NSString, acc - exact, (acc - exact) / step, sum - exact))
    }
}

// MARK: 3. end to end: write a synthetic clip where each frame encodes its index, then ask AVAssetImageGenerator
let bits = 10, cell = 12, side = bits * cell
func makeFrame(_ index: Int, _ buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    for b in 0..<bits where index >> b & 1 == 1 { ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: b * cell, y: 0, width: cell, height: side)) }
}
func decode(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var v = 0
    for b in 0..<bits { let x = Int((Double(b) + 0.5) * Double(w) / Double(bits)); let i = ((h / 2) * w + x) * 4; if px[i] > 127 { v |= 1 << b } }
    return v
}
func writeClip(rate: Rate, frames: Int, to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(url: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoMaxKeyFrameIntervalKey: 15, AVVideoAllowFrameReorderingKey: false]])
    input.mediaTimeScale = rate.num   // keep the PTS exact: the writer would otherwise round them onto its own grid
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    for k in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        makeFrame(k, pb!); adaptor.append(pb!, withPresentationTime: rate.pts(k))
    }
    input.markAsFinished(); await writer.finishWriting()
}
func endToEnd() async {
    print("\nEND-TO-END: 240-frame clip per rate (frame index drawn into each frame), AVAssetImageGenerator with zero tolerance.")
    print("rate     | wrong frames of 240 when asked with: (a) CMTime(seconds:,600) now | (b) 600 rounded | (c) integer ms rounded | (d) exact rational | (e) mid-frame via seconds,600")
    for k in [41, 11] { let t = CMTime(seconds: Double(k) / 25, preferredTimescale: 600); print("  CMTime(seconds: \(k)/25, 600) = \(t.value)/\(t.timescale)  (exact is \(k * 24)/600)") }
    for r in rates {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tb-\(r.name).mov")
        do { try await writeClip(rate: r, frames: 240, to: url) } catch { print(r.name, "write failed", error); continue }
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero; gen.appliesPreferredTrackTransform = true
        func wrong(_ make: (Int) -> CMTime) async -> String {
            var bad = 0, first = ""
            for k in 0..<240 {
                do {
                    let (img, _) = try await gen.image(at: make(k))
                    let got = decode(img); if got != k { bad += 1; if first.isEmpty { first = "k=\(k) got \(got)" } }
                } catch { bad += 1; if first.isEmpty { first = "k=\(k) error" } }
            }
            return "\(bad)/240" + (first.isEmpty ? "" : " (\(first))")
        }
        func sec(_ k: Int) -> Double { Double(k) * Double(r.den) / Double(r.num) }
        let a = await wrong { CMTime(seconds: sec($0), preferredTimescale: 600) }
        let b = await wrong { CMTime(value: Int64((sec($0) * 600).rounded()), timescale: 600) }
        let c = await wrong { CMTime(value: Int64((sec($0) * 1000).rounded()), timescale: 1000) }
        let d = await wrong { r.pts($0) }
        let e = await wrong { CMTime(seconds: sec($0) + 0.5 * Double(r.den) / Double(r.num), preferredTimescale: 600) }
        print("\(r.name.padding(toLength: 8, withPad: " ", startingAt: 0)) | \(a) | \(b) | \(c) | \(d) | \(e)")
    }
}

@main struct Main {
    static func main() async {
        let args = CommandLine.arguments
        await inspectReal(args.count > 1 ? args[1] : "")
        arithmetic()
        await endToEnd()
    }
}
