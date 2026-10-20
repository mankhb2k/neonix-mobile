import XCTest
@testable import NeonixEditor

/// `AudioMove` / `MoveAudioClipCommand`: an audio clip moves among the audio tracks only, new tracks come from gaps, empty tracks go.
final class AudioMoveTests: XCTestCase {
    private func clip(_ id: String, start: Double, duration: Double = 2000) -> V2AudioClip {
        V2AudioClip(id: id, assetId: "a", timing: V2AudioClipTiming(start: start, duration: duration), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1)
    }

    private func track(_ id: String, _ clips: [V2AudioClip]) -> V2AudioTrack {
        V2AudioTrack(id: id, gainDb: nil, pan: 0, muted: false, clips: clips)
    }

    private func project(_ tracks: [V2AudioTrack]) -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [],
                  audio: V2AudioDomain(sampleRate: 48000, tracks: tracks))
    }

    private let bands: [(trackId: String, minY: CGFloat, maxY: CGFloat)] = [("t0", 100, 130), ("t1", 136, 166)]

    func testAFreeTrackUnderTheClipWins() {
        let tracks = [track("t0", [clip("a", start: 0)]), track("t1", [clip("b", start: 5000)])]
        let moving = tracks[0].clips[0]
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 0, bands: bands, y: 150), .track("t1"), "t1 is free from 0 to 2 s")
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 0, bands: bands, y: 115), .track("t0"), "its own track")
    }

    func testOverAnOccupiedTrackOrInAGapItIsANewTrack() {
        let tracks = [track("t0", [clip("a", start: 0)]), track("t1", [clip("b", start: 1000)])]
        let moving = tracks[0].clips[0]
        // t1 holds a clip at 1 s: the moved clip (0...2 s) would overlap it. The lower half of t1: after it; the upper half: before it.
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 0, bands: bands, y: 160), .newTrack(at: 2))
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 0, bands: bands, y: 140), .newTrack(at: 1))
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 0, bands: bands, y: 133), .newTrack(at: 1), "in the gap between the tracks")
    }

    func testAboveTheFirstTrackIsTheSlotAtTheTopOfTheAudioSectionAndBelowTheLastIsTheEnd() {
        let tracks = [track("t0", [clip("a", start: 0)]), track("t1", [clip("b", start: 5000)])]
        let moving = tracks[1].clips[0]
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 5000, bands: bands, y: 40), .newTrack(at: 0), "far above: still only the top of the audio section")
        XCTAssertEqual(AudioMove.resolve(tracks: tracks, moving: moving, start: 5000, bands: bands, y: 600), .newTrack(at: 2))
    }

    func testMovingWithinAndBetweenTracks() {
        let p = project([track("t0", [clip("a", start: 0)]), track("t1", [clip("b", start: 5000)])])
        let within = MoveAudioClipCommand(clipId: "a", start: 1000, target: .track("t0")).apply(to: p)
        XCTAssertEqual(within.audio.tracks[0].clips[0].timing.start, 1000)
        let across = MoveAudioClipCommand(clipId: "a", start: 0, target: .track("t1")).apply(to: p)
        XCTAssertEqual(across.audio.tracks.map(\.id), ["t1"], "t0 was left empty and is gone")
        XCTAssertEqual(across.audio.tracks[0].clips.map(\.id), ["a", "b"], "sorted by time")
    }

    func testANewTrackIsInsertedAtTheIndexAndAnEmptiedSourceIsDropped() {
        let p = project([track("t0", [clip("a", start: 0)]), track("t1", [clip("b", start: 5000)])])
        let atTop = MoveAudioClipCommand(clipId: "b", start: 5000, target: .newTrack(at: 0)).apply(to: p)
        XCTAssertEqual(atTop.audio.tracks.count, 2, "t1 was emptied and dropped")
        XCTAssertEqual(atTop.audio.tracks[0].clips.map(\.id), ["b"])
        XCTAssertEqual(atTop.audio.tracks[1].id, "t0")
        let between = MoveAudioClipCommand(clipId: "b", start: 0, target: .newTrack(at: 1)).apply(to: project([track("t0", [clip("a", start: 0), clip("b", start: 9000)]), track("t1", [clip("c", start: 0)])]))
        XCTAssertEqual(between.audio.tracks.map { $0.clips.map(\.id) }, [["a"], ["b"], ["c"]], "a new track squeezed between two old ones")
        let end = MoveAudioClipCommand(clipId: "a", start: 0, target: .newTrack(at: 2)).apply(to: p)
        XCTAssertEqual(end.audio.tracks.map { $0.clips.map(\.id) }, [["b"], ["a"]], "t0 emptied and dropped, the new one at the end")
    }

    func testFailsClosed() {
        let p = project([track("t0", [clip("a", start: 0)]), track("t1", [clip("b", start: 1000)])])
        XCTAssertEqual(MoveAudioClipCommand(clipId: "a", start: 0, target: .track("t1")).apply(to: p).audio.tracks.count, 2, "an overlap is refused")
        XCTAssertEqual(MoveAudioClipCommand(clipId: "nope", start: 0, target: .track("t1")).apply(to: p).audio.tracks.count, 2)
        XCTAssertEqual(MoveAudioClipCommand(clipId: "a", start: 0, target: .track("nope")).apply(to: p).audio.tracks[0].clips.map(\.id), ["a"])
        XCTAssertEqual(MoveAudioClipCommand(clipId: "a", start: 0, target: .newTrack(at: 9)).apply(to: p).audio.tracks[0].clips.map(\.id), ["a"])
        XCTAssertEqual(MoveAudioClipCommand(clipId: "a", start: -500, target: .track("t0")).apply(to: p).audio.tracks[0].clips[0].timing.start, 0, "not before 0")
    }

    func testTheLanesAutoScrollTowardTheEdgeTheFingerIsNear() {
        XCTAssertEqual(LaneAutoScrollTuning.targetSpeed(fingerY: 300, top: 100, bottom: 500), 0, "away from the edges")
        XCTAssertEqual(LaneAutoScrollTuning.targetSpeed(fingerY: 470, top: 100, bottom: 500), LaneAutoScrollTuning.slowSpeed, "30 pt from the bottom: slow, down")
        XCTAssertEqual(LaneAutoScrollTuning.targetSpeed(fingerY: 490, top: 100, bottom: 500), LaneAutoScrollTuning.fastSpeed)
        XCTAssertEqual(LaneAutoScrollTuning.targetSpeed(fingerY: 130, top: 100, bottom: 500), -LaneAutoScrollTuning.slowSpeed, "30 pt from the top: slow, up")
        XCTAssertEqual(LaneAutoScrollTuning.targetSpeed(fingerY: 90, top: 100, bottom: 500), -LaneAutoScrollTuning.fastSpeed, "past the edge: fast")
    }
}
