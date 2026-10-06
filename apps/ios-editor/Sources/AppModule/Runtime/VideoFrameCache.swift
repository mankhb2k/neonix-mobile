import AVFoundation
import UIKit

/// Extracts a still frame from a video asset at an arbitrary time, driven by
/// the app's own custom clock (not a separate `AVPlayer` timeline) — see the
/// "Video preview" decision in the editor-document plan: this keeps every
/// layer, shape or video, sampled by the same clock, at the cost of being
/// less smooth than real decoded playback.
final class VideoFrameCache {
    static let shared = VideoFrameCache()

    private var generators: [String: AVAssetImageGenerator] = [:]

    func frame(assetId: String, url: URL, atSeconds seconds: Double) -> UIImage? {
        let generator: AVAssetImageGenerator
        if let cached = generators[assetId] {
            generator = cached
        } else {
            let asset = AVURLAsset(url: url)
            let created = AVAssetImageGenerator(asset: asset)
            created.appliesPreferredTrackTransform = true
            created.requestedTimeToleranceBefore = .zero
            created.requestedTimeToleranceAfter = .zero
            generators[assetId] = created
            generator = created
        }
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
