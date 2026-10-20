import CoreGraphics
import Foundation

/// Where a moved audio clip lands: an existing audio track, or a new track inserted at an index of the (non-empty) track list.
enum AudioMoveTarget: Equatable {
    case track(String)
    case newTrack(at: Int)
}

/// Rules for moving one standalone audio clip by long-press-and-drag (user 2026-10-17). Audio has its own list of tracks that the timeline draws *below*
/// every picture lane and never mixed with them, so a clip only ever moves between audio tracks: a track it fits in, or a **new track** in the gap between
/// two audio tracks, above the first one (right under the last picture lane - the line the clip cannot cross) or below the last.
enum AudioMove {
    /// True when `moving` can sit in track `trackId` from `start`: no other clip of the track overlaps it.
    static func fits(_ tracks: [V2AudioTrack], moving: V2AudioClip, trackId: String, start: Double) -> Bool {
        guard let track = tracks.first(where: { $0.id == trackId }) else { return false }
        let end = start + moving.timing.duration
        return !track.clips.contains { other in
            other.id != moving.id && start < other.timing.start + other.timing.duration - 0.001 && other.timing.start < end - 0.001
        }
    }

    /// The target for the clip's centre at `y` (the bands' space). A track under it that fits wins; over a track that does not fit, or in a gap, or
    /// above the first track, or below the last, it is a new track inserted before the first track whose middle is below `y` (at the end when none is).
    /// Anything above the first track is the slot at the top of the audio section: the clip never goes into a picture lane.
    static func resolve(tracks: [V2AudioTrack], moving: V2AudioClip, start: Double, bands: [(trackId: String, minY: CGFloat, maxY: CGFloat)], y: CGFloat) -> AudioMoveTarget {
        let sorted = bands.sorted { $0.minY < $1.minY }
        if let hit = sorted.first(where: { y >= $0.minY && y <= $0.maxY }), fits(tracks, moving: moving, trackId: hit.trackId, start: start) {
            return .track(hit.trackId)
        }
        if let below = sorted.first(where: { y < ($0.minY + $0.maxY) / 2 }), let index = tracks.firstIndex(where: { $0.id == below.trackId }) {
            return .newTrack(at: index)
        }
        return .newTrack(at: tracks.count)
    }
}

/// Moves one audio clip to `start` (ms, not below 0) in `target`. Valid by construction: an unknown clip or track, an overlap, or an index out of range
/// leaves the project unchanged. Tracks left with no clip are dropped (no empty lanes), so a new track's index counts the non-empty tracks - the source
/// track included - as they were before the move.
struct MoveAudioClipCommand: EditorCommand {
    let clipId: String
    let start: Double
    let target: AudioMoveTarget

    func apply(to project: V2Project) -> V2Project {
        var tracks = project.audio.tracks.filter { !$0.clips.isEmpty }
        guard let t = tracks.firstIndex(where: { $0.clips.contains { $0.id == clipId } }),
              let c = tracks[t].clips.firstIndex(where: { $0.id == clipId })
        else { return project }
        var clip = tracks[t].clips.remove(at: c)
        clip.timing = V2AudioClipTiming(start: max(start, 0), duration: clip.timing.duration)

        switch target {
        case .track(let id):
            guard let i = tracks.firstIndex(where: { $0.id == id }) else { return project }
            let end = clip.timing.start + clip.timing.duration
            let overlaps = tracks[i].clips.contains { $0.timing.start < end - 0.001 && clip.timing.start < $0.timing.start + $0.timing.duration - 0.001 }
            guard !overlaps else { return project }
            tracks[i].clips.append(clip)
            tracks[i].clips.sort { $0.timing.start < $1.timing.start }
        case .newTrack(let index):
            guard index >= 0, index <= tracks.count else { return project }
            tracks.insert(V2AudioTrack(id: "track-\(UUID().uuidString.prefix(8))", gainDb: nil, pan: 0, muted: false, clips: [clip]), at: index)
        }
        tracks.removeAll { $0.clips.isEmpty }
        return project.withAudio(V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: tracks))
    }
}
