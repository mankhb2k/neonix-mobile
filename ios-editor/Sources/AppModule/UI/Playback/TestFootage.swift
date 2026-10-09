import Foundation

/// The one clip every playback test screen uses (Playback Sandbox, Video Raw
/// and the editor's sample project): real footage recorded on an iPhone —
/// HEVC, 1080×1920, 60 fps, a keyframe every 0.5 s.
///
/// Stock clips downloaded from the web are not representative: the one this
/// project started with has a keyframe every 6–8 s, so even the iOS Photos app
/// stutters scrubbing it, and for a while that was mistaken for a bug in our
/// pipeline (`PLAYBACK_PIPELINE.md` § 9, § 12). The file lives in
/// `public/preview/video/` and is pushed to a device's
/// `Documents/ImportedMedia/` with `devicectl device copy to` (§ 12) — it is
/// 190 MB, so it is deliberately not bundled in the app.
enum TestFootage {
    static let filename = "iphone-footage.MOV"

    static var url: URL? {
        bundledURL(filename: filename)
    }

    static let missingMessage = "iphone-footage.MOV is not on this device. Push it with devicectl (PLAYBACK_PIPELINE.md § 12) or copy it into Documents/ImportedMedia."
}
