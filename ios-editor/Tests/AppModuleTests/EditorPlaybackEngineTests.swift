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


final class ScrubTolerancePolicyTests: XCTestCase {
    func testDefaultIsFixedTwoHundredMilliseconds() {
        XCTAssertEqual(ScrubTolerancePolicy().seconds(forSpeedMsPerSecond: 5000), 0.2)
        XCTAssertEqual(ScrubTolerancePolicy().seconds(forSpeedMsPerSecond: 0), 0.2)
    }

    func testParsingFixedAndProportionalAndRejectingGarbage() {
        XCTAssertEqual(ScrubTolerancePolicy(parsing: "0")?.seconds(forSpeedMsPerSecond: 900), 0)
        XCTAssertEqual(ScrubTolerancePolicy(parsing: "0.05")?.seconds(forSpeedMsPerSecond: 900), 0.05)
        XCTAssertEqual(ScrubTolerancePolicy(parsing: "prop:1.5")?.kind, .proportional(frames: 1.5, capSeconds: 0.2))
        XCTAssertNil(ScrubTolerancePolicy(parsing: "fast"))
        XCTAssertNil(ScrubTolerancePolicy(parsing: "prop:x"))
    }

    func testProportionalSlackIsFramesOfMotionAndCapped() throws {
        let policy = try XCTUnwrap(ScrubTolerancePolicy(parsing: "prop:1.5"))
        // 600 ms/s = 10 ms per 60 Hz frame; 1.5 frames = 15 ms.
        XCTAssertEqual(policy.seconds(forSpeedMsPerSecond: 600), 0.015, accuracy: 1e-9)
        XCTAssertEqual(policy.seconds(forSpeedMsPerSecond: -600), 0.015, accuracy: 1e-9)
        XCTAssertEqual(policy.seconds(forSpeedMsPerSecond: 0), 0)
        XCTAssertEqual(policy.seconds(forSpeedMsPerSecond: 100_000), 0.2)
    }
}
