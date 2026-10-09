import AVFoundation
import Foundation

/// Debug-only way to run the sample project on a different video — footage
/// recorded on a real iPhone, say — without touching the code: launch with
/// `PLAYBACK_SAMPLE_CLIP=<filename>` (or just leave `iphone-footage.MOV` in
/// `Documents/ImportedMedia`), where the file is bundled or sits in
/// `Documents/ImportedMedia` (push it with `devicectl device copy to`, see
/// `PLAYBACK_PIPELINE.md` § 12). The asset's size and the project's length come
/// from the file itself, not from the 31.2 s numbers hard-coded for the stock
/// sample. In Release builds this is always `nil`.
enum SampleClipOverride {
    struct Metadata {
        let uri: String
        let width: Double
        let height: Double
        let durationMs: Double
    }

    #if DEBUG
    static let current: Metadata? = {
        // Explicit choice wins; otherwise real iPhone footage that has been
        // pushed into `Documents/ImportedMedia` replaces the stock sample.
        let name = ProcessInfo.processInfo.environment["PLAYBACK_SAMPLE_CLIP"]
            ?? (bundledURL(filename: "iphone-footage.MOV") != nil ? "iphone-footage.MOV" : nil)
        guard let name, let url = bundledURL(filename: name) else { return nil }
        // `static let` initialisers run once, on whichever thread asks first
        // (SwiftUI `body`, main thread) — the file is probed on a detached task
        // and waited for, never on the main actor itself.
        final class Box: @unchecked Sendable { var value: Metadata? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let asset = AVURLAsset(url: url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform),
               let duration = try? await asset.load(.duration) {
                let upright = CGRect(origin: .zero, size: size).applying(transform)
                box.value = Metadata(uri: name, width: abs(upright.width), height: abs(upright.height), durationMs: duration.seconds * 1000)
            }
            done.signal()
        }
        done.wait()
        return box.value
    }()
    #else
    static let current: Metadata? = nil
    #endif
}
