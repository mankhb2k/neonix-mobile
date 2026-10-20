#if DEBUG
import AVFoundation

/// Debug: the picture size and length of a video file in the bundle or `Documents/ImportedMedia`, read before the UI exists (the same probe as `SampleClipOverride`).
enum VideoFileInfo {
    struct Info { let uri: String; let width: Double; let height: Double; let durationMs: Double }

    static func read(uri: String) -> Info? {
        guard let url = bundledURL(filename: uri) else { return nil }
        final class Box: @unchecked Sendable { var value: Info? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let asset = AVURLAsset(url: url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first, let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform), let duration = try? await asset.load(.duration) {
                let upright = CGRect(origin: .zero, size: size).applying(transform)
                box.value = Info(uri: uri, width: abs(upright.width), height: abs(upright.height), durationMs: duration.seconds * 1000)
            }
            done.signal()
        }
        done.wait()
        return box.value
    }
}
#endif
