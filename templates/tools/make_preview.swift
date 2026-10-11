import AVFoundation
import Foundation
// usage: make_preview <video> <startSeconds> <durationSeconds> <out.mp4> <poster.jpg>
let a = CommandLine.arguments
guard a.count == 6, let start = Double(a[2]), let duration = Double(a[3]) else { print("usage"); exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let out = URL(fileURLWithPath: a[4]); try? FileManager.default.removeItem(at: out)
guard let s = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else { print("no session"); exit(1) }
s.outputURL = out; s.outputFileType = .mp4; s.shouldOptimizeForNetworkUse = true
s.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
let sem = DispatchSemaphore(value: 0)
s.exportAsynchronously { sem.signal() }; sem.wait()
print("video:", s.status == .completed ? "ok \((try? FileManager.default.attributesOfItem(atPath: out.path)[.size]) ?? 0) bytes" : "failed \(String(describing: s.error))")
// poster: a frame 1 s in, as JPEG
let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 1080, height: 1920)
if let cg = try? gen.copyCGImage(at: CMTime(seconds: start + 1, preferredTimescale: 600), actualTime: nil) {
    let rep = NSMutableData()
    if let dest = CGImageDestinationCreateWithData(rep, "public.jpeg" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        CGImageDestinationFinalize(dest)
        try? (rep as Data).write(to: URL(fileURLWithPath: a[5]))
        print("poster ok \(rep.length) bytes \(cg.width)x\(cg.height)")
    }
}
