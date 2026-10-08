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

    func testReachingTheEndResetsToZeroAndStops() async throws {
        let engine = makeEngine(durationMs: 100)
        engine.play()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.currentTimeMs, 0)
    }
}
