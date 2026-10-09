import AVFoundation

/// Copies a user-picked (or, later, recorded/extracted) media file into the
/// app's own sandbox and mints the `V2Asset` that refers to it — the first
/// media import path this app has ever needed; every asset before this was a
/// bundled sample file resolved via `Bundle.main` (see `bundledURL(filename:)`
/// in `PreviewCanvas.swift`, which this service's directory is now also a
/// fallback for).
///
/// Filenames are `"<uuid>.<ext>"` — exactly one dot, matching
/// `bundledURL(filename:)`'s own `split(separator: ".", maxSplits: 1)`
/// assumption.
enum MediaImportService {
    /// `Documents/ImportedMedia` — not `Caches`, since an imported audio
    /// clip is real user content the system shouldn't feel free to purge.
    static var importedMediaDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("ImportedMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    enum ImportError: Error {
        case unreadableDuration
        case exportFailed
    }

    /// Copies `sourceURL` in, reads its real duration, and returns a
    /// `V2AudioAsset` ready to be appended to `project.assets`. The caller
    /// (an `EditorCommand`) decides where the resulting clip goes on the
    /// timeline — this only handles "get the file into the sandbox and
    /// describe it."
    static func importAudio(from sourceURL: URL) async throws -> V2AudioAsset {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = importedMediaDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let asset = AVURLAsset(url: destination)
        guard let duration = try? await asset.load(.duration), duration.isValid, !duration.isIndefinite else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.unreadableDuration
        }

        return V2AudioAsset(
            id: UUID().uuidString,
            uri: filename,
            mimeType: mimeType(forExtension: ext),
            duration: CMTimeGetSeconds(duration) * 1000
        )
    }

    /// Trích xuất — pulls a video asset's own audio track out as a
    /// standalone file. Exports the **whole** asset's audio once per source
    /// file, cached by filename under `importedMediaDirectory` (keyed, not
    /// a UUID per call) so extracting from a second clip that shares the
    /// same underlying video asset — or re-extracting after the user
    /// deleted the clip once — reuses the same export instead of doing the
    /// work again. The caller (`EditorShellView.extractAudio`) is
    /// responsible for trimming the *clip* it places down to the video
    /// layer's own `trimStart`/duration via `AddAudioClipCommand`'s
    /// `trimStartMs`/`trimEndMs` — this only produces the full-length file
    /// + its real duration.
    ///
    /// Uses the older completion-handler `exportAsynchronously` API (wrapped
    /// in a continuation) rather than the newer `async throws export()` —
    /// that one needs a newer deployment target than this project's 17.0
    /// floor.
    static func extractAudio(from videoURL: URL) async throws -> V2AudioAsset {
        let cacheKey = videoURL.deletingPathExtension().lastPathComponent
        let filename = "extracted-\(cacheKey).m4a"
        let destination = importedMediaDirectory.appendingPathComponent(filename)

        if !FileManager.default.fileExists(atPath: destination.path) {
            try await exportAudioOnly(from: videoURL, to: destination)
        }

        let asset = AVURLAsset(url: destination)
        guard let duration = try? await asset.load(.duration), duration.isValid, !duration.isIndefinite, duration.seconds > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.unreadableDuration
        }

        return V2AudioAsset(
            id: "extracted-\(cacheKey)",
            uri: filename,
            mimeType: "audio/mp4",
            duration: CMTimeGetSeconds(duration) * 1000
        )
    }

    private static func exportAudioOnly(from sourceURL: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.exportFailed
        }
        session.outputURL = destination
        session.outputFileType = .m4a

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: session.error ?? ImportError.exportFailed)
                }
            }
        }
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        default: return "audio/mp4"
        }
    }
}
