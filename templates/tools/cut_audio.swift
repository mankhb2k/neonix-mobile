import AVFoundation
import Foundation

// usage: cut_audio <in> <startSeconds> <durationSeconds> <out.m4a>
let args = CommandLine.arguments
guard args.count == 5, let start = Double(args[2]), let duration = Double(args[3]) else { print("usage"); exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let out = URL(fileURLWithPath: args[4])
try? FileManager.default.removeItem(at: out)
guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { print("no session"); exit(1) }
session.outputURL = out
session.outputFileType = .m4a
session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
// 1 s fade-out so the cut does not click.
let semaphore = DispatchSemaphore(value: 0)
Task {
    if let track = try? await asset.loadTracks(withMediaType: .audio).first {
        let params = AVMutableAudioMixInputParameters(track: track)
        let fadeStart = CMTime(seconds: start + duration - 1, preferredTimescale: 600)
        params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: fadeStart, duration: CMTime(seconds: 1, preferredTimescale: 600)))
        let mix = AVMutableAudioMix(); mix.inputParameters = [params]
        session.audioMix = mix
    }
    session.exportAsynchronously { semaphore.signal() }
}
semaphore.wait()
print(session.status == .completed ? "ok \((try? FileManager.default.attributesOfItem(atPath: out.path)[.size]) ?? 0) bytes" : "failed: \(String(describing: session.error))")
