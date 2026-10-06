import Foundation

// Port of packages/motion-protocol/src/v2/audio.ts. `audio-fixtures.ts` is
// TS-test-only data and is not ported.

enum V2AudioFadeCurve: String, Codable {
    case linear
    case equalPower = "equal-power"
}

struct V2AudioFade: Codable {
    var duration: Double
    var curve: V2AudioFadeCurve
}

/// `gainDb`/`pan` mirror Zod `.default(0)` fields — optional here, caller
/// applies the fallback.
struct V2EmbeddedVideoAudio: Codable {
    var enabled: Bool
    var gainDb: Double?
    var pan: Double?
    var fadeIn: V2AudioFade?
    var fadeOut: V2AudioFade?
}

struct V2AudioClipTiming: Codable {
    var start: Double
    var duration: Double
}

struct V2AudioClipTrim: Codable {
    var start: Double
    var end: Double?
}

/// `enabled`/`gainDb`/`pan` mirror Zod `.default(...)` fields — optional
/// here, caller applies the fallback (`true`/`0`/`0`).
struct V2AudioClip: Codable {
    var id: String
    var assetId: String
    var timing: V2AudioClipTiming
    var trim: V2AudioClipTrim
    var playbackRate: Double
    var enabled: Bool?
    var gainDb: Double?
    var pan: Double?
    var fadeIn: V2AudioFade?
    var fadeOut: V2AudioFade?
}

/// `gainDb` mirrors a Zod `.default(0)` field — optional here, caller
/// applies the fallback.
struct V2AudioTrack: Codable {
    var id: String
    var gainDb: Double?
    var pan: Double
    var muted: Bool
    var clips: [V2AudioClip]
}

struct V2AudioDomain: Codable {
    var sampleRate: Double
    var tracks: [V2AudioTrack]
}
