import Foundation

/// The arithmetic of trimming one audio clip's edge, shared by the timeline's handles (live, every drag tick) and tested on its own.
/// Audio plays at its normal speed (`AudioMixEngine` ignores `playbackRate`), so the file moves 1 ms per timeline ms.
enum AudioTrim {
    static let minDurationMs = 200.0

    /// Left edge moved by `deltaMs`: the head of the clip's footage moves with it. Limited by the start of the file (`trim.start`),
    /// by 0, by the previous clip on the track (`floorMs` = its end) and by the minimum length.
    static func left(clip: V2AudioClip, deltaMs: Double, floorMs: Double?) -> (start: Double, duration: Double, trimStart: Double, appliedMs: Double)? {
        var delta = max(deltaMs, -clip.trim.start, -clip.timing.start)
        if let floorMs { delta = max(delta, floorMs - clip.timing.start) }
        delta = min(delta, clip.timing.duration - minDurationMs)
        guard clip.timing.duration - delta >= minDurationMs - 0.001 else { return nil }
        return (clip.timing.start + delta, clip.timing.duration - delta, clip.trim.start + delta, delta)
    }

    /// Right edge moved by `deltaMs`: more footage is revealed (up to the end of the file, `assetDurationMs`) or less. Limited by the
    /// next clip on the track (`ceilingMs` = its start) and the minimum length.
    static func right(clip: V2AudioClip, deltaMs: Double, ceilingMs: Double?, assetDurationMs: Double?) -> (duration: Double, appliedMs: Double)? {
        var duration = max(clip.timing.duration + deltaMs, minDurationMs)
        if let ceilingMs { duration = min(duration, ceilingMs - clip.timing.start) }
        if let assetDurationMs { duration = min(duration, assetDurationMs - clip.trim.start) }
        guard duration >= minDurationMs - 0.001 else { return nil }
        return (duration, duration - clip.timing.duration)
    }
}

/// Moves a standalone audio clip's edges: its place on the timeline (`start`, `duration`) and the footage it plays (`trimStart`).
/// Valid by construction: a clip that would overlap another on its track, start before 0, run past the end of its file
/// (`assetDurationMs`), or be shorter than `AudioTrim.minDurationMs` leaves the project unchanged.
struct TrimAudioClipCommand: EditorCommand {
    let clipId: String
    let start: Double
    let duration: Double
    let trimStart: Double
    /// The file's own length when known.
    var assetDurationMs: Double?

    func apply(to project: V2Project) -> V2Project {
        var tracks = project.audio.tracks
        guard let t = tracks.firstIndex(where: { $0.clips.contains { $0.id == clipId } }),
              let c = tracks[t].clips.firstIndex(where: { $0.id == clipId })
        else { return project }
        let clip = tracks[t].clips[c]
        guard start >= 0, trimStart >= 0, duration >= AudioTrim.minDurationMs - 0.001 else { return project }
        if let assetDurationMs, trimStart + duration > assetDurationMs + 1 { return project }
        let overlaps = tracks[t].clips.contains { other in
            other.id != clipId && start < other.timing.start + other.timing.duration - 0.001 && other.timing.start < start + duration - 0.001
        }
        guard !overlaps else { return project }
        tracks[t].clips[c].timing = V2AudioClipTiming(start: start, duration: duration)
        tracks[t].clips[c].trim = V2AudioClipTrim(start: trimStart, end: clip.trim.end.map { _ in trimStart + duration })
        return project.withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}
