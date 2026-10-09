import XCTest
@testable import NeonixEditor

@MainActor
final class EditorPlaybackEngineTests: XCTestCase {
    /// A project with only a group layer: no video, so playback uses the
    /// software clock and nothing touches `AVPlayer`.
    private func makeEngine(durationMs: Double = 10_000) -> EditorPlaybackEngine {
        let layer = V2Layer(
            id: "g",
            order: 0,
            frame: V2Frame(width: 100, height: 100),
            transform: .identity,
            timing: V2Timing(start: 0, duration: durationMs),
            payload: .group(render3d: nil)
        )
        let project = V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
            assets: [],
            layers: [layer]
        )
        return EditorPlaybackEngine(project: project)
    }

    func testStartsIdleAtZeroWithProjectDuration() {
        let engine = makeEngine(durationMs: 8000)
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.currentTimeMs, 0)
        XCTAssertEqual(engine.maxDurationMs, 8000)
    }

    func testScrubMovesRelativeToWhereTheGestureStartedAndClamps() {
        let engine = makeEngine(durationMs: 10_000)
        engine.beginScrub()
        engine.scrub(deltaMs: 4000)
        XCTAssertEqual(engine.currentTimeMs, 4000)
        engine.scrub(deltaMs: -99_000)
        XCTAssertEqual(engine.currentTimeMs, 0)
        engine.scrub(deltaMs: 99_000)
        XCTAssertEqual(engine.currentTimeMs, 10_000)
    }

    func testScrubIsIgnoredOutsideAScrubGesture() {
        let engine = makeEngine()
        engine.scrub(deltaMs: 5000)
        engine.scrub(toMs: 5000)
        XCTAssertEqual(engine.currentTimeMs, 0)
    }

    func testBeginScrubIsIdempotentWithinAGesture() {
        let engine = makeEngine()
        engine.beginScrub()
        engine.scrub(deltaMs: 3000)
        // Every drag tick calls beginScrub again; it must not re-anchor.
        engine.beginScrub()
        engine.scrub(deltaMs: 3000)
        XCTAssertEqual(engine.currentTimeMs, 3000)
    }

    func testSlowReleaseStopsAndFastReleaseCoasts() {
        let slow = makeEngine()
        slow.beginScrub()
        slow.endScrub(velocityMsPerSecond: 10)
        XCTAssertEqual(slow.mode, .idle)

        let fast = makeEngine()
        fast.beginScrub()
        fast.endScrub(velocityMsPerSecond: 2000)
        XCTAssertEqual(fast.mode, .coasting)
    }

    func testNewTouchDuringACoastTakesOverFromTheLiveTime() async throws {
        let engine = makeEngine(durationMs: 60_000)
        engine.beginScrub()
        engine.endScrub(velocityMsPerSecond: 20_000)
        try await Task.sleep(nanoseconds: 120_000_000)
        let coastedTo = engine.currentTimeMs
        XCTAssertGreaterThan(coastedTo, 0)

        engine.beginScrub()
        XCTAssertEqual(engine.mode, .scrubbing)
        engine.scrub(deltaMs: 0)
        XCTAssertEqual(engine.currentTimeMs, coastedTo, accuracy: 1)
    }

    func testCoastEndsAtTheTimelineEdgeAndGoesIdle() async throws {
        let engine = makeEngine(durationMs: 500)
        engine.beginScrub()
        engine.endScrub(velocityMsPerSecond: 50_000)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(engine.currentTimeMs, 500)
        XCTAssertEqual(engine.mode, .idle)
    }

    func testPlayAdvancesTheSoftwareClockAndPauseStopsIt() async throws {
        let engine = makeEngine(durationMs: 60_000)
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(engine.currentTimeMs, 50)

        engine.pause()
        XCTAssertEqual(engine.mode, .idle)
        let pausedAt = engine.currentTimeMs
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(engine.currentTimeMs, pausedAt)
    }

    func testBeginScrubPausesPlayback() {
        let engine = makeEngine()
        engine.play()
        engine.beginScrub()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.mode, .scrubbing)
    }

    func testReleasingAScrubLeavesPlaybackPausedUntilPlayIsTapped() async throws {
        let engine = makeEngine(durationMs: 60_000)
        engine.play()
        engine.beginScrub()
        engine.scrub(toMs: 12_000)
        engine.endScrub(velocityMsPerSecond: 0)

        XCTAssertEqual(engine.mode, .idle)
        XCTAssertFalse(engine.isPlaying)
        let releasedAt = engine.currentTimeMs
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(engine.currentTimeMs, releasedAt, accuracy: 1)

        engine.play()
        XCTAssertTrue(engine.isPlaying)
        engine.pause()
    }

    func testReachingTheEndResetsToZeroAndStops() async throws {
        let engine = makeEngine(durationMs: 100)
        engine.play()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.currentTimeMs, 0)
    }

    /// `EditorShellView.init` builds an engine every time the view struct is
    /// re-created and SwiftUI keeps only the first — so constructing one must
    /// not create an `AVPlayer`; `prepare()` does.
    func testInitCreatesNoPlayersUntilPrepare() {
        let project = videoProject()
        let before = PlaybackMetrics.shared.liveCount(.stageSession)
        let engine = EditorPlaybackEngine(project: project)
        XCTAssertNil(engine.player(for: "clip"))
        XCTAssertEqual(PlaybackMetrics.shared.liveCount(.stageSession), before, "init must not create a StagePlayerSession")

        engine.prepare()
        XCTAssertNotNil(engine.player(for: "clip"))
        XCTAssertEqual(PlaybackMetrics.shared.liveCount(.stageSession), before + 1)

        // An edit after prepare keeps the same session (same asset + url).
        let session = engine.player(for: "clip")
        engine.update(project: project)
        XCTAssertTrue(engine.player(for: "clip") === session)
    }

    private func videoProject() -> V2Project {
        let layer = V2Layer(
            id: "clip", order: 0,
            frame: V2Frame(width: 100, height: 100), transform: .identity,
            timing: V2Timing(start: 0, duration: 4000),
            payload: .video(V2VideoPayload(assetId: "v", fit: nil, trimStart: nil, trimEnd: nil, playbackRate: nil, audio: nil))
        )
        return V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
            assets: [.video(V2VideoAsset(id: "v", uri: "13792197_1080_1920_30fps.mp4", width: 1080, height: 1920, duration: 31200))],
            layers: [layer]
        )
    }
}
