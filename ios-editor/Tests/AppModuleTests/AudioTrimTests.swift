import XCTest
@testable import NeonixEditor

/// Trimming a standalone audio clip (`AudioTrim`, `TrimAudioClipCommand`) and the rule that an audio track with no clip is gone.
final class AudioTrimTests: XCTestCase {
    private func clip(_ id: String, start: Double, duration: Double, trimStart: Double = 0) -> V2AudioClip {
        V2AudioClip(id: id, assetId: "a", timing: V2AudioClipTiming(start: start, duration: duration), trim: V2AudioClipTrim(start: trimStart, end: nil), playbackRate: 1)
    }

    private func project(_ tracks: [[V2AudioClip]]) -> V2Project {
        V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [],
            audio: V2AudioDomain(sampleRate: 48000, tracks: tracks.enumerated().map { V2AudioTrack(id: "t\($0.offset)", gainDb: nil, pan: 0, muted: false, clips: $0.element) })
        )
    }

    func testLeftHandleMovesTheHeadOfTheFootageWithTheEdge() {
        let c = clip("c", start: 1000, duration: 4000, trimStart: 500)
        let r = AudioTrim.left(clip: c, deltaMs: 300, floorMs: nil)!
        XCTAssertEqual(r.start, 1300); XCTAssertEqual(r.duration, 3700); XCTAssertEqual(r.trimStart, 800)
    }

    func testLeftHandleCannotRevealBeforeTheFileStartBeforeZeroOrIntoTheNeighbour() {
        let c = clip("c", start: 1000, duration: 4000, trimStart: 200)
        XCTAssertEqual(AudioTrim.left(clip: c, deltaMs: -900, floorMs: nil)!.trimStart, 0, "the file starts there")
        let d = clip("d", start: 100, duration: 4000, trimStart: 5000)
        XCTAssertEqual(AudioTrim.left(clip: d, deltaMs: -900, floorMs: nil)!.start, 0, "not before 0")
        let e = clip("e", start: 1000, duration: 4000, trimStart: 5000)
        XCTAssertEqual(AudioTrim.left(clip: e, deltaMs: -900, floorMs: 800)!.start, 800, "stops at the previous clip's end")
    }

    func testTheClipKeepsAMinimumLength() {
        let c = clip("c", start: 0, duration: 1000)
        XCTAssertEqual(AudioTrim.left(clip: c, deltaMs: 5000, floorMs: nil)!.duration, AudioTrim.minDurationMs)
        XCTAssertEqual(AudioTrim.right(clip: c, deltaMs: -5000, ceilingMs: nil, assetDurationMs: nil)!.duration, AudioTrim.minDurationMs)
    }

    func testRightHandleStopsAtTheEndOfTheFileAndTheNextClip() {
        let c = clip("c", start: 1000, duration: 2000, trimStart: 1000)   // plays 1.0...3.0 s of a 4 s file
        XCTAssertEqual(AudioTrim.right(clip: c, deltaMs: 5000, ceilingMs: nil, assetDurationMs: 4000)!.duration, 3000, "no more file")
        XCTAssertEqual(AudioTrim.right(clip: c, deltaMs: 5000, ceilingMs: 3500, assetDurationMs: 4000)!.duration, 2500, "the next clip is in the way")
        XCTAssertEqual(AudioTrim.right(clip: c, deltaMs: -500, ceilingMs: nil, assetDurationMs: 4000)!.duration, 1500)
    }

    func testTheCommandMovesTheEdgesAndFailsClosedOnOverlapOrPastTheFile() {
        let p = project([[clip("a", start: 0, duration: 2000), clip("b", start: 3000, duration: 2000)]])
        let ok = TrimAudioClipCommand(clipId: "b", start: 2500, duration: 2500, trimStart: 0, assetDurationMs: 6000).apply(to: p)
        XCTAssertEqual(ok.audio.tracks[0].clips[1].timing.start, 2500)
        XCTAssertEqual(ok.audio.tracks[0].clips[1].timing.duration, 2500)
        let overlap = TrimAudioClipCommand(clipId: "b", start: 1500, duration: 3500, trimStart: 0).apply(to: p)
        XCTAssertEqual(overlap.audio.tracks[0].clips[1].timing.start, 3000, "overlapping the neighbour is refused")
        let pastFile = TrimAudioClipCommand(clipId: "b", start: 3000, duration: 4000, trimStart: 0, assetDurationMs: 3500).apply(to: p)
        XCTAssertEqual(pastFile.audio.tracks[0].clips[1].timing.duration, 2000, "the file ends at 3.5 s")
    }

    func testDeletingTheLastClipOfATrackRemovesTheTrack() {
        let p = project([[clip("a", start: 0, duration: 1000)], [clip("b", start: 0, duration: 1000), clip("c", start: 2000, duration: 1000)]])
        let afterA = DeleteAudioClipCommand(clipId: "a").apply(to: p)
        XCTAssertEqual(afterA.audio.tracks.map(\.id), ["t1"], "no empty lane is left")
        let afterB = DeleteAudioClipCommand(clipId: "b").apply(to: p)
        XCTAssertEqual(afterB.audio.tracks.map(\.id), ["t0", "t1"], "a track that still has a clip stays")
    }
}
