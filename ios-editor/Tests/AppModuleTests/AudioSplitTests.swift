import XCTest
@testable import NeonixEditor

/// `SplitAudioClipCommand`: one audio clip becomes two at the playhead.
final class AudioSplitTests: XCTestCase {
    private func clip(start: Double = 1000, duration: Double = 10_000, trimStart: Double = 500) -> V2AudioClip {
        V2AudioClip(
            id: "c", assetId: "a", timing: V2AudioClipTiming(start: start, duration: duration), trim: V2AudioClipTrim(start: trimStart, end: nil),
            playbackRate: 1, enabled: nil, gainDb: -6, pan: 0.25,
            fadeIn: V2AudioFade(duration: 3000, curve: .equalPower), fadeOut: V2AudioFade(duration: 4000, curve: .equalPower)
        )
    }

    private func project(_ clips: [V2AudioClip]) -> V2Project {
        V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [],
            audio: V2AudioDomain(sampleRate: 48000, tracks: [V2AudioTrack(id: "t", gainDb: nil, pan: 0, muted: false, clips: clips)])
        )
    }

    func testTheSecondHalfPlaysOnFromWhereTheFirstStops() {
        let result = SplitAudioClipCommand(clipId: "c", atMs: 5000, newClipId: "d").apply(to: project([clip()]))
        let clips = result.audio.tracks[0].clips
        XCTAssertEqual(clips.map(\.id), ["c", "d"], "the second half follows the first in the same track")
        XCTAssertEqual(clips[0].timing.start, 1000); XCTAssertEqual(clips[0].timing.duration, 4000)
        XCTAssertEqual(clips[1].timing.start, 5000); XCTAssertEqual(clips[1].timing.duration, 6000)
        XCTAssertEqual(clips[0].trim.start, 500)
        XCTAssertEqual(clips[1].trim.start, 4500, "500 + the first half's 4000 ms of footage")
        XCTAssertEqual(clips[1].timing.start + clips[1].timing.duration, 11_000, "the end of the clip (1000 + 10000) did not move")
        XCTAssertEqual(clips[0].gainDb, -6); XCTAssertEqual(clips[1].gainDb, -6, "both keep the gain")
        XCTAssertEqual(clips[1].pan, 0.25)
    }

    func testFadeInStaysOnTheFirstHalfAndFadeOutGoesToTheSecond() {
        let result = SplitAudioClipCommand(clipId: "c", atMs: 5000, newClipId: "d").apply(to: project([clip()]))
        let clips = result.audio.tracks[0].clips
        XCTAssertEqual(clips[0].fadeIn?.duration, 3000)
        XCTAssertNil(clips[0].fadeOut)
        XCTAssertNil(clips[1].fadeIn)
        XCTAssertEqual(clips[1].fadeOut?.duration, 4000)
    }

    func testAFadeLongerThanItsNewHalfIsShortenedToIt() {
        let result = SplitAudioClipCommand(clipId: "c", atMs: 2000, newClipId: "d").apply(to: project([clip()]))   // first half 1 s, fade in was 3 s
        XCTAssertEqual(result.audio.tracks[0].clips[0].fadeIn?.duration, 1000, "never longer than the clip it is on")
    }

    func testTheCutMustBeStrictlyInsideTheClip() {
        let p = project([clip()])
        for cut in [1000.0, 11_000, 500, 20_000] {
            XCTAssertEqual(SplitAudioClipCommand(clipId: "c", atMs: cut).apply(to: p).audio.tracks[0].clips.count, 1, "cut at \(cut) leaves it alone")
        }
        XCTAssertEqual(SplitAudioClipCommand(clipId: "nope", atMs: 5000).apply(to: p).audio.tracks[0].clips.count, 1)
    }

    func testOtherClipsOfTheTrackStayWhereTheyAre() {
        var other = clip(start: 20_000, duration: 3000); other.id = "z"
        let result = SplitAudioClipCommand(clipId: "c", atMs: 5000, newClipId: "d").apply(to: project([clip(), other]))
        XCTAssertEqual(result.audio.tracks[0].clips.map(\.id), ["c", "d", "z"])
        XCTAssertEqual(result.audio.tracks[0].clips[2].timing.start, 20_000)
    }
}
