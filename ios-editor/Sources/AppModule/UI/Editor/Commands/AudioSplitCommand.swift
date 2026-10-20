import Foundation

/// Splits a standalone audio clip in two at `atMs` (timeline time), like `SplitClipCommand` does for a picture clip: the first half keeps the head
/// of the footage, the second half plays on from where the first stops (`trim.start` moves on by the first half's length - audio plays at normal
/// speed), and the second half goes in the same track right after the first. Both keep the clip's gain and pan. The fades follow the same rule as
/// the animations of a picture clip: **Fade in stays on the first half and Fade out goes to the second**, each kept inside `AudioFadeLimit` for its
/// new, shorter clip. No-op (fail closed) unless the cut is strictly inside the clip.
struct SplitAudioClipCommand: EditorCommand {
    let clipId: String
    let atMs: Double
    /// The id of the second half; nil = a fresh `<id>-split-<uuid>`.
    var newClipId: String?

    func apply(to project: V2Project) -> V2Project {
        var tracks = project.audio.tracks
        guard let t = tracks.firstIndex(where: { $0.clips.contains { $0.id == clipId } }),
              let c = tracks[t].clips.firstIndex(where: { $0.id == clipId })
        else { return project }
        let original = tracks[t].clips[c]
        let end = original.timing.start + original.timing.duration
        guard atMs > original.timing.start, atMs < end else { return project }

        let firstDuration = atMs - original.timing.start
        let secondDuration = end - atMs

        func clamped(_ fade: V2AudioFade?, forDuration duration: Double) -> V2AudioFade? {
            guard var fade else { return nil }
            fade.duration = min(fade.duration, AudioFadeLimit.maxMs(forClipDurationMs: duration))
            return fade.duration >= 1 ? fade : nil
        }

        var first = original
        first.timing = V2AudioClipTiming(start: original.timing.start, duration: firstDuration)
        first.trim = V2AudioClipTrim(start: original.trim.start, end: original.trim.end.map { _ in original.trim.start + firstDuration })
        first.fadeIn = clamped(original.fadeIn, forDuration: firstDuration)
        first.fadeOut = nil

        var second = original
        second.id = newClipId ?? "\(original.id)-split-\(UUID().uuidString.prefix(8))"
        second.timing = V2AudioClipTiming(start: atMs, duration: secondDuration)
        second.trim = V2AudioClipTrim(start: original.trim.start + firstDuration, end: original.trim.end)
        second.fadeIn = nil
        second.fadeOut = clamped(original.fadeOut, forDuration: secondDuration)

        tracks[t].clips[c] = first
        tracks[t].clips.insert(second, at: c + 1)
        return project.withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}
