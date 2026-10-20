import Foundation

/// How long a standalone audio clip's fade in / fade out may be (user 2026-10-17): up to 10 s, and never longer than the clip itself - a 9 s
/// clip fades for at most 9 s, an 11 s clip for at most 10 s.
enum AudioFadeLimit {
    static let maximumMs = 10_000.0

    static func maxMs(forClipDurationMs duration: Double) -> Double { min(maximumMs, max(duration, 0)) }
}

/// Sets a standalone audio clip's fade in and fade out (ms, 0 = none). Each is kept inside `AudioFadeLimit`; the curve is equal-power (a fade that
/// sounds even), which `AudioMixEngine.volume(for:atMs:)` plays. No-op (fail closed) for an unknown clip.
struct SetAudioClipFadeCommand: EditorCommand {
    let clipId: String
    let fadeInMs: Double
    let fadeOutMs: Double

    func apply(to project: V2Project) -> V2Project {
        var found = false
        let tracks = project.audio.tracks.map { track -> V2AudioTrack in
            var track = track
            guard let index = track.clips.firstIndex(where: { $0.id == clipId }) else { return track }
            found = true
            let limit = AudioFadeLimit.maxMs(forClipDurationMs: track.clips[index].timing.duration)
            func fade(_ ms: Double) -> V2AudioFade? {
                let duration = min(max(ms, 0), limit)
                return duration >= 1 ? V2AudioFade(duration: duration, curve: .equalPower) : nil
            }
            track.clips[index].fadeIn = fade(fadeInMs)
            track.clips[index].fadeOut = fade(fadeOutMs)
            return track
        }
        guard found else { return project }
        return project.withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}

/// The gain (0...1) a clip's fades give at `elapsedMs` into a clip of `durationMs`: the engine multiplies its volume by it
/// (`AudioMixEngine.volume(for:atMs:)`) and the timeline draws it (the clip's two-tone body and its scaled waveform), so what is seen is what is heard.
enum AudioFadeEnvelope {
    static func gain(elapsedMs: Double, durationMs: Double, fadeIn: V2AudioFade?, fadeOut: V2AudioFade?) -> Double {
        var gain = 1.0
        if let fadeIn, fadeIn.duration > 0, elapsedMs < fadeIn.duration {
            gain *= curve(fraction: elapsedMs / fadeIn.duration, fadeIn.curve)
        }
        let remainingMs = durationMs - elapsedMs
        if let fadeOut, fadeOut.duration > 0, remainingMs < fadeOut.duration {
            gain *= curve(fraction: remainingMs / fadeOut.duration, fadeOut.curve)
        }
        return gain
    }

    /// Linear blends value, equal-power blends power (sin of a quarter turn): the standard constant-loudness curve.
    static func curve(fraction: Double, _ curve: V2AudioFadeCurve) -> Double {
        let t = min(max(fraction, 0), 1)
        switch curve {
        case .linear: return t
        case .equalPower: return sin(t * .pi / 2)
        }
    }
}
