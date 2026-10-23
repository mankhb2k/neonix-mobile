import XCTest
import AVFoundation
import QuartzCore
import Darwin
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

    func testTouchDownBrakesACoastSoItStopsQuicklyAndFarShortOfTheFreeGlide() async throws {
        let free = makeEngine(durationMs: 600_000)
        free.beginScrub()
        free.endScrub(velocityMsPerSecond: 20_000)
        let braked = makeEngine(durationMs: 600_000)
        braked.beginScrub()
        braked.endScrub(velocityMsPerSecond: 20_000)
        try await Task.sleep(nanoseconds: 100_000_000)
        braked.brake()
        braked.brake() // idempotent
        XCTAssertEqual(braked.mode, .coasting, "braking is a short glide, not an instant stop")
        let brakedAt = braked.currentTimeMs
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(braked.mode, .idle, "a braked coast must have come to rest")
        XCTAssertLessThan(braked.currentTimeMs - brakedAt, 4000, "braking travels only a short way")
        XCTAssertGreaterThan(free.currentTimeMs, braked.currentTimeMs + 10_000, "the free glide is still running far ahead")
    }

    func testBrakeDoesNothingWhenNotCoasting() {
        let engine = makeEngine()
        engine.brake()
        XCTAssertEqual(engine.mode, .idle)
        engine.beginScrub()
        engine.brake()
        XCTAssertEqual(engine.mode, .scrubbing)
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

    #if DEBUG
    func testFourClipPlaybackWithoutTransitionsReachesTheEndWithoutRewinding() async throws {
        try await assertFourClipPlaybackIsContinuous(withTransitions: false)
    }

    func testFourClipPlaybackWithThreeTransitionsReachesTheEndWithoutRewinding() async throws {
        try await assertFourClipPlaybackIsContinuous(withTransitions: true)
    }

    func testSelfieProjectPlaybackWithThreeTransitionsUsesReadyPlayersAndReachesEveryCut() async throws {
        try await assertPeopleProjectPlayback(uri: "demo-nguoi1.MOV", projectId: "people-selfie", withTransitions: true)
    }

    func testCrowdProjectPlaybackWithThreeTransitionsUsesReadyPlayersAndReachesEveryCut() async throws {
        try await assertPeopleProjectPlayback(uri: "demo-nguoi2.MOV", projectId: "people-crowd", withTransitions: true)
    }

    func testSelfieProjectPlaybackWithoutTransitionsIsPlayerBaseline() async throws {
        try await assertPeopleProjectPlayback(uri: "demo-nguoi1.MOV", projectId: "people-selfie-baseline", withTransitions: false)
    }

    func testCrowdProjectPlaybackWithoutTransitionsIsPlayerBaseline() async throws {
        try await assertPeopleProjectPlayback(uri: "demo-nguoi2.MOV", projectId: "people-crowd-baseline", withTransitions: false)
    }

    func testSplitPlaybackSeamOnImportedFootageLogsPreviewPlayerState() async throws {
        setenv("PLAYBACK_SPLIT_DIAGNOSTICS", "1", 1)
        defer { unsetenv("PLAYBACK_SPLIT_DIAGNOSTICS") }
        // The selfie in the reported screenshot is demo-nguoi1.MOV. Compare it
        // with a second HEVC phone recording, an imported portrait phone clip,
        // and the bundled H.264 sample at the same source cut.
        let cases = [
            ("demo-nguoi1.MOV", 5_000.0),
            ("demo-nguoi2.MOV", 5_000.0),
            ("iphone-footage.MOV", 5_000.0),
            ("13792197_1080_1920_30fps.mp4", 5_000.0),
        ]

        for (uri, cutMs) in cases {
            let media = try XCTUnwrap(VideoFileInfo.read(uri: uri), "missing real footage \(uri)")
            let assetId = "split-probe-\(uri)"
            let layer = V2Layer(
                id: "split-probe-source-\(uri)", order: 0,
                frame: V2Frame(width: 360, height: 640), transform: .identity,
                timing: V2Timing(start: 0, duration: media.durationMs),
                payload: .video(V2VideoPayload(assetId: assetId, fit: "cover", trimStart: 0,
                                               trimEnd: media.durationMs, playbackRate: 1))
            )
            let asset = V2Asset.video(V2VideoAsset(id: assetId, uri: uri, width: media.width,
                                                   height: media.height, duration: media.durationMs))
            let unsplit = V2Project(id: "split-preview-\(uri)",
                                    composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
                                    assets: [asset], layers: [layer])
            let split = SplitClipCommand(layerId: layer.id, atMs: cutMs,
                                         secondLayerId: "split-probe-second-\(uri)").apply(to: unsplit)
            XCTAssertEqual(split.layers.count, 2, "\(uri) must really pass through SplitClipCommand")
            let firstMap = try XCTUnwrap(VideoTimeMapping(layer: split.layers[0]))
            let secondMap = try XCTUnwrap(VideoTimeMapping(layer: split.layers[1]))
            XCTAssertTrue(firstMap.isContinuous(with: secondMap), "split V2 time mapping must be source-contiguous for \(uri)")

            let engine = EditorPlaybackEngine(project: split)
            engine.prepare()
            defer { engine.pause() }

            let first = try XCTUnwrap(engine.player(for: split.layers[0].id))
            let second = try XCTUnwrap(engine.player(for: split.layers[1].id))
            let readyDeadline = Date().addingTimeInterval(10)
            while Date() < readyDeadline && (first.currentItem?.status != .readyToPlay || second.currentItem?.status != .readyToPlay) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(first.currentItem?.status, .readyToPlay, "first half AVPlayerItem not ready for \(uri)")
            XCTAssertEqual(second.currentItem?.status, .readyToPlay, "second half AVPlayerItem not ready for \(uri)")

            NSLog("[SplitPreviewTest] begin uri=%@ cutMs=%.1f codecMetadata=see split-gop report firstStatus=%ld secondStatus=%ld mappingContinuous=%@",
                  uri, cutMs, first.currentItem?.status.rawValue ?? -1,
                  second.currentItem?.status.rawValue ?? -1, firstMap.isContinuous(with: secondMap) ? "yes" : "no")

            engine.beginScrub()
            engine.scrub(toMs: cutMs - 500)
            engine.endScrub(velocityMsPerSecond: 0)
            try await Task.sleep(nanoseconds: 400_000_000)
            engine.play()

            var previousTimeline = engine.currentTimeMs
            var previousWall = CACurrentMediaTime()
            var longestNoAdvanceMs = 0.0
            let deadline = CACurrentMediaTime() + 2.0
            while CACurrentMediaTime() < deadline && engine.currentTimeMs < cutMs + 700 {
                try await Task.sleep(nanoseconds: 20_000_000)
                let now = CACurrentMediaTime()
                let timeline = engine.currentTimeMs
                let timelineDelta = timeline - previousTimeline
                let wallDeltaMs = (now - previousWall) * 1000
                if wallDeltaMs >= 80 && timelineDelta < 5 {
                    longestNoAdvanceMs = max(longestNoAdvanceMs, wallDeltaMs)
                    NSLog("[SplitPreviewTest] no_advance uri=%@ wallMs=%.1f timelineDeltaMs=%.1f t=%.1f first={rate=%.2f,src=%.3f,control=%ld} second={rate=%.2f,src=%.3f,control=%ld} buffered={firstEmpty=%@,secondEmpty=%@}",
                          uri, wallDeltaMs, timelineDelta, timeline,
                          first.rate, first.currentTime().seconds, first.timeControlStatus.rawValue,
                          second.rate, second.currentTime().seconds, second.timeControlStatus.rawValue,
                          first.currentItem?.isPlaybackBufferEmpty == true ? "yes" : "no",
                          second.currentItem?.isPlaybackBufferEmpty == true ? "yes" : "no")
                }
                if timeline >= cutMs - 350 && timeline <= cutMs + 350 {
                    NSLog("[SplitPreviewTest] sample uri=%@ t=%.1f delta=%.1f first={rate=%.2f,src=%.3f,control=%ld} second={rate=%.2f,src=%.3f,control=%ld}",
                          uri, timeline, timelineDelta,
                          first.rate, first.currentTime().seconds, first.timeControlStatus.rawValue,
                          second.rate, second.currentTime().seconds, second.timeControlStatus.rawValue)
                }
                previousTimeline = timeline
                previousWall = now
            }
            engine.pause()
            NSLog("[SplitPreviewTest] end uri=%@ reached=%.1f cutMs=%.1f longestNoAdvanceMs=%.1f firstError=%@ secondError=%@",
                  uri, engine.currentTimeMs, cutMs, longestNoAdvanceMs,
                  first.currentItem?.error?.localizedDescription ?? "none",
                  second.currentItem?.error?.localizedDescription ?? "none")
            XCTAssertGreaterThan(engine.currentTimeMs, cutMs + 300, "\(uri) preview must cross its split point")
        }
    }

    func testThreeVideoPreviewFrameCadenceAcrossUnsplitSplitAndTransitions() async throws {
        setenv("PLAYBACK_SPLIT_DIAGNOSTICS", "1", 1)
        defer { unsetenv("PLAYBACK_SPLIT_DIAGNOSTICS") }
        let videos = ["demo-nguoi1.MOV", "demo-nguoi2.MOV", "iphone-footage.MOV"]
        let cuts = [5_000.0, 10_000.0, 15_000.0]
        for uri in videos {
            let base = try await makeFrameCadenceProject(uri: uri)
            let split = try makeSegmentedProject(base, cuts: cuts, addTransitions: false)
            let transitioned = try makeSegmentedProject(base, cuts: cuts, addTransitions: true)
            XCTAssertEqual(split.layers.filter { $0.type == "video" }.count, cuts.count + 1)
            XCTAssertEqual(TransitionFramePlan(project: transitioned).windows.count, cuts.count)

            for (variant, project) in [("unsplit", base), ("split", split), ("transition", transitioned)] {
                let ids = project.layers.filter { $0.type == "video" }.map(\.id)
                let engine = EditorPlaybackEngine(project: project)
                engine.prepare()
                let outputs = try await attachFrameOutputs(to: engine, layerIds: ids)
                for (index, cut) in cuts.enumerated() {
                    let sample = try await measureDecodedFrameCadence(
                        variant: variant, uri: uri, cutMs: cut, project: project,
                        engine: engine, outputs: outputs
                    )
                    let effect = variant == "transition" ? [TransitionKind.mix, .fadeBlack, .push][index].rawValue : "none"
                    NSLog("[FrameCadenceCompare] uri=%@ variant=%@ cutMs=%.0f effect=%@ uniqueFrames=%d ptsFPS=%.1f maxPTSGapMs=%.1f maxLayerHostGapMs=%.1f duplicatePTS=%d",
                          uri, variant, cut, effect, sample.frames, sample.fps, sample.maxPTSGapMs,
                          sample.maxHostGapMs, sample.duplicatePTS)
                    NSLog("[FrameSeam] uri=%@ variant=%@ cutMs=%.0f hostGapMs=%.1f",
                          uri, variant, cut, sample.seamHostGapMs)
                    XCTAssertGreaterThan(sample.frames, 5, "\(uri) \(variant) must produce frames around \(cut)")
                    if variant != "unsplit" {
                        XCTAssertLessThanOrEqual(sample.maxPTSGapMs, 75,
                                                 "\(uri) \(variant) drops source frames at \(cut)")
                        XCTAssertLessThanOrEqual(sample.seamHostGapMs, 90,
                                                 "\(uri) \(variant) stalls at \(cut)")
                    }
                }
                engine.pause()
            }
        }
    }

    func testDifferentFilesHandoffAcrossCutAndTransition() async throws {
        let first = try await makeFrameCadenceProject(uri: "demo-nguoi1.MOV")
        let second = try await makeFrameCadenceProject(uri: "demo-nguoi2.MOV")
        let outgoing = V2Layer(
            id: "mixed-outgoing", order: 0,
            frame: V2Frame(width: 360, height: 640), transform: .identity,
            timing: V2Timing(start: 0, duration: 5_000),
            payload: .video(V2VideoPayload(assetId: first.assets[0].id, fit: "cover",
                                           trimStart: 0, trimEnd: 5_000, playbackRate: 1))
        )
        let incoming = V2Layer(
            id: "mixed-incoming", order: 0,
            frame: V2Frame(width: 360, height: 640), transform: .identity,
            timing: V2Timing(start: 5_000, duration: 5_000),
            payload: .video(V2VideoPayload(assetId: second.assets[0].id, fit: "cover",
                                           trimStart: 0, trimEnd: 5_000, playbackRate: 1))
        )
        let cut = V2Project(id: "mixed-files-cut", composition: first.composition,
                            assets: [first.assets[0], second.assets[0]], layers: [outgoing, incoming])
        let transitioned = SetTransitionCommand(outgoingId: outgoing.id, incomingId: incoming.id,
                                                kind: .mix, durationMs: 1_000).apply(to: cut)
        for (variant, project) in [("split", cut), ("transition", transitioned)] {
            let engine = EditorPlaybackEngine(project: project)
            engine.prepare()
            let outputs = try await attachFrameOutputs(to: engine, layerIds: [outgoing.id, incoming.id])
            let sample = try await measureDecodedFrameCadence(
                variant: variant, uri: "mixed-files", cutMs: 5_000,
                project: project, engine: engine, outputs: outputs
            )
            NSLog("[DifferentFiles] variant=%@ maxPTSGapMs=%.1f seamHostGapMs=%.1f",
                  variant, sample.maxPTSGapMs, sample.seamHostGapMs)
            XCTAssertLessThanOrEqual(sample.maxPTSGapMs, 75)
            XCTAssertLessThanOrEqual(sample.seamHostGapMs, 90)
            engine.pause()
        }
    }

    private func makeFrameCadenceProject(uri: String) async throws -> V2Project {
        let mediaURL = try XCTUnwrap(bundledURL(filename: uri), "missing real footage \(uri)")
        let sourceAsset = AVURLAsset(url: mediaURL)
        let duration = try await sourceAsset.load(.duration)
        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first, "video track missing for \(uri)")
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let uprightSize = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).size
        let durationMs = duration.seconds * 1000
        let assetId = "frame-cadence-\(uri)"
        let source = V2Layer(
            id: "frame-cadence-source-\(uri)", order: 0,
            frame: V2Frame(width: 360, height: 640), transform: .identity,
            timing: V2Timing(start: 0, duration: durationMs),
            payload: .video(V2VideoPayload(assetId: assetId, fit: "cover", trimStart: 0,
                                           trimEnd: durationMs, playbackRate: 1))
        )
        let asset = V2Asset.video(V2VideoAsset(id: assetId, uri: uri, width: abs(uprightSize.width),
                                               height: abs(uprightSize.height), duration: durationMs))
        return V2Project(id: "frame-cadence-\(uri)",
                         composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
                         assets: [asset], layers: [source])
    }

    private func makeSegmentedProject(_ base: V2Project, cuts: [Double], addTransitions: Bool) throws -> V2Project {
        var result = base
        for (index, cut) in cuts.enumerated() {
            let layer = try XCTUnwrap(result.layers.first {
                $0.type == "video" && cut > $0.timing.start && cut < $0.timing.start + $0.timing.duration
            })
            result = SplitClipCommand(layerId: layer.id, atMs: cut,
                                      secondLayerId: "frame-cadence-split-\(index)-\(base.id)").apply(to: result)
        }
        guard addTransitions else { return result }
        let clips = result.layers.filter { $0.type == "video" }.sorted { $0.timing.start < $1.timing.start }
        for (index, kind) in [TransitionKind.mix, .fadeBlack, .push].enumerated() {
            result = SetTransitionCommand(outgoingId: clips[index].id, incomingId: clips[index + 1].id,
                                          kind: kind, durationMs: 1_000).apply(to: result)
        }
        return result
    }

    private struct FrameCadenceMeasurement {
        let frames: Int
        let fps: Double
        let maxPTSGapMs: Double
        let maxHostGapMs: Double
        let seamHostGapMs: Double
        let duplicatePTS: Int
    }

    private func attachFrameOutputs(to engine: EditorPlaybackEngine, layerIds: [String]) async throws -> [String: AVPlayerItemVideoOutput] {
        var outputs: [String: AVPlayerItemVideoOutput] = [:]
        for id in layerIds {
            let player = try XCTUnwrap(engine.player(for: id), "missing AVPlayer for \(id)")
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline && player.currentItem?.status != .readyToPlay {
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            let item = try XCTUnwrap(player.currentItem)
            XCTAssertEqual(item.status, .readyToPlay, "AVPlayerItem for \(id) must be ready before frame sampling")
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            item.add(output)
            outputs[id] = output
        }
        return outputs
    }

    private func measureDecodedFrameCadence(
        variant: String,
        uri: String,
        cutMs: Double,
        project: V2Project,
        engine: EditorPlaybackEngine,
        outputs: [String: AVPlayerItemVideoOutput]
    ) async throws -> FrameCadenceMeasurement {
        engine.pause()
        engine.beginScrub()
        engine.scrub(toMs: cutMs - 400)
        engine.endScrub(velocityMsPerSecond: 0)
        try await Task.sleep(nanoseconds: 250_000_000)
        engine.play()

        var presentation: [(layerId: String, host: CFTimeInterval, timelineMs: Double)] = []
        var duplicatePTS = 0
        let deadline = CACurrentMediaTime() + 2
        while CACurrentMediaTime() < deadline && engine.currentTimeMs < cutMs + 400 {
            let hostTime = CACurrentMediaTime()
            let timeline = engine.currentTimeMs
            let activeLayers = project.layers.filter { layer in
                layer.type == "video" && (
                    (timeline >= layer.timing.start && timeline < layer.timing.start + layer.timing.duration)
                        || engine.transitionFramePlan.isVisible(layer.id, at: timeline)
                )
            }
            for layer in activeLayers {
                guard let output = outputs[layer.id] else { continue }
                let itemTime = output.itemTime(forHostTime: hostTime)
                if itemTime.isValid && output.hasNewPixelBuffer(forItemTime: itemTime) {
                    var displayTime = CMTime.invalid
                    if output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) != nil,
                       displayTime.isValid, displayTime.seconds.isFinite,
                       let mapping = VideoTimeMapping(layer: layer) {
                        let timelinePTS = mapping.timelineMs(atSourceMs: displayTime.seconds * 1000)
                        let layerStart = layer.timing.start
                        let layerEnd = layer.timing.start + layer.timing.duration
                        // Transition participants intentionally hold their edge frame outside
                        // authored clip timing. Do not count that designed hold as a decoder stall.
                        if timeline >= layerStart && timeline < layerEnd,
                           timelinePTS >= cutMs - 300 && timelinePTS <= cutMs + 300 {
                            if presentation.contains(where: { $0.layerId == layer.id && abs($0.timelineMs - timelinePTS) < 0.1 }) {
                                duplicatePTS += 1
                            } else {
                                // Keep each source's host presentation samples. During transitions both
                                // players are visible, so de-duplicating across layers hides handoff stalls.
                                presentation.append((layer.id, hostTime, timelinePTS))
                            }
                        }
                    }
                }
            }
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        engine.pause()

        let pts = Array(Set(presentation.map(\.timelineMs).map { Int(($0 * 10).rounded()) })).map { Double($0) / 10 }.sorted()
        let ptsGaps = zip(pts, pts.dropFirst()).map { abs($1 - $0) }
        let hostGaps = Dictionary(grouping: presentation, by: \.layerId).values.flatMap { events in
            let host = events.map(\.host).sorted()
            return zip(host, host.dropFirst()).map { ($1 - $0) * 1000 }
        }
        let beforeCut = presentation.filter { $0.timelineMs < cutMs }.max { $0.timelineMs < $1.timelineMs }
        let afterCut = presentation.filter { $0.timelineMs >= cutMs }.min { $0.timelineMs < $1.timelineMs }
        let seamHostGapMs = beforeCut.flatMap { before in
            afterCut.map { max(0, ($0.host - before.host) * 1000) }
        } ?? .nan
        let elapsed = (pts.last ?? 0) - (pts.first ?? 0)
        let measurement = FrameCadenceMeasurement(
            frames: pts.count,
            fps: elapsed > 0 ? Double(max(0, presentation.count - 1)) * 1000 / elapsed : 0,
            maxPTSGapMs: ptsGaps.max() ?? 0,
            maxHostGapMs: hostGaps.max() ?? 0,
            seamHostGapMs: seamHostGapMs,
            duplicatePTS: duplicatePTS
        )
        let formattedPTS = pts.map { String(format: "%.1f", $0) }.joined(separator: ",")
        NSLog("[FrameCadence] variant=%@ uri=%@ cutMs=%.0f window=[%.0f,%.0f] uniqueFrames=%d fps=%.1f maxPTSGapMs=%.1f maxHostGapMs=%.1f duplicatePTS=%d timelinePTS=[%@]",
              variant, uri, cutMs, cutMs - 300, cutMs + 300,
              measurement.frames, measurement.fps, measurement.maxPTSGapMs, measurement.maxHostGapMs,
              measurement.duplicatePTS, formattedPTS)
        return measurement
    }

    private func assertFourClipPlaybackIsContinuous(withTransitions: Bool) async throws {
        let project = ProjectsView.makeTransitionDebugProject(withTransitions: withTransitions)
        let engine = EditorPlaybackEngine(project: project)
        engine.prepare()
        engine.play()
        defer { engine.pause() }

        let deadline = Date().addingTimeInterval(22)
        var previous = 0.0
        var highest = 0.0
        while engine.isPlaying && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
            guard engine.isPlaying else { break } // Reaching the end resets the playhead to zero.
            let time = engine.currentTimeMs
            if time + 1 < previous {
                XCTFail("playhead rewound from \(previous) to \(time) ms")
                return
            }
            highest = max(highest, time)
            previous = time
        }
        XCTAssertEqual(engine.mode, .idle, "playback must finish instead of stalling at a cut")
        XCTAssertGreaterThan(highest, 11_000, "playback must cross all three cuts")
    }

    private func assertPeopleProjectPlayback(uri: String, projectId: String, withTransitions: Bool) async throws {
        let sourceProject = try makePeopleProject(uri: uri, projectId: projectId, withTransitions: withTransitions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(sourceProject)
        let project = try JSONDecoder().decode(V2Project.self, from: encoded)
        XCTAssertEqual(try encoder.encode(project), encoded, "\(projectId) V2 JSON must round-trip stably")
        XCTAssertEqual(TransitionWrappers.applied(in: project.layers).count, withTransitions ? 3 : 0,
                       "\(projectId) V2 decode must preserve each transition intent")
        let plan = TransitionFramePlan(project: project)
        XCTAssertEqual(plan.windows.count, withTransitions ? 3 : 0, "fixture must have exactly three transition cuts or none")
        let renderProject = TransitionRenderPlan.compile(project)
        XCTAssertEqual(TransitionFramePlan(project: renderProject).windows.count, withTransitions ? 3 : 0,
                       "renderer compilation must preserve all three transition windows")
        let clipIds = (0..<4).map { "\(projectId)-clip-\($0)" }
        let primaryClips = clipIds.compactMap { id in project.layers.first { $0.id == id } }
        XCTAssertEqual(primaryClips.count, 4, "fixture must keep four primary clips on the main lane")
        XCTAssertTrue(primaryClips.allSatisfy { $0.type == "video" && $0.order == 0 })

        let engine = EditorPlaybackEngine(project: project)
        engine.prepare()
        defer { engine.pause() }

        for id in clipIds {
            XCTAssertNotNil(engine.player(for: id), "missing AVPlayer for \(id); the real project media did not load")
        }

        let readyDeadline = Date().addingTimeInterval(10)
        while Date() < readyDeadline {
            let statuses = clipIds.compactMap { engine.player(for: $0)?.currentItem?.status }
            if statuses.count == clipIds.count, statuses.allSatisfy({ $0 != .unknown }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        for id in clipIds {
            let item = try XCTUnwrap(engine.player(for: id)?.currentItem, "missing AVPlayerItem for \(id)")
            NSLog("[TransitionPlayerTest] project=%@ clip=%@ status=%ld duration=%.3f",
                  projectId, id, item.status.rawValue, item.duration.seconds)
            XCTAssertEqual(item.status, .readyToPlay, "AVPlayerItem for \(id) must be ready before playback")
        }

        engine.play()
        let deadline = Date().addingTimeInterval(22)
        var previous = engine.currentTimeMs
        var highest = previous
        var reachedWindows = Set<Int>()
        var highWaterByWindow = [Int: Double]()
        var playbackPlayerSamples = 0
        var playerClockAdvances = 0
        var previousSourceSeconds: [String: Double] = [:]
        var loggedTransitionCheckpoints = Set<String>()

        while engine.isPlaying && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
            guard engine.isPlaying else { break } // Reaching the end resets the playhead to zero.
            let time = engine.currentTimeMs
            if time + 1 < previous {
                NSLog("[TransitionPlayerTest] project=%@ PLAYHEAD_REGRESSION from=%.1f to=%.1f", projectId, previous, time)
                XCTFail("\(projectId) playhead rewound from \(previous) to \(time) ms")
                return
            }
            highest = max(highest, time)
            previous = time

            if let source = clipIds.first(where: { (engine.player(for: $0)?.rate ?? 0) > 0 }) {
                playbackPlayerSamples += 1
                if let player = engine.player(for: source) {
                    let sourceSeconds = player.currentTime().seconds
                    if let previousSource = previousSourceSeconds[source], sourceSeconds > previousSource + 0.001 {
                        playerClockAdvances += 1
                    }
                    previousSourceSeconds[source] = sourceSeconds
                }
                if playbackPlayerSamples.isMultiple(of: 100) {
                    let player = try XCTUnwrap(engine.player(for: source))
                    NSLog("[TransitionPlayerTest] project=%@ t=%.1f playing=%@ rate=%.2f source=%.3f status=%ld",
                          projectId, time, source, player.rate, player.currentTime().seconds,
                          player.currentItem?.status.rawValue ?? -1)
                }
            }

            if let window = plan.activeWindow(at: time),
               let index = plan.windows.firstIndex(of: window) {
                reachedWindows.insert(index)
                let progress = window.progress(at: time)
                highWaterByWindow[index] = max(highWaterByWindow[index] ?? 0, progress)
                let checkpoint: String? = progress < 0.1 ? "start" : (progress >= 0.5 && progress < 0.52 ? "middle" : (progress >= 0.9 ? "end" : nil))
                if let checkpoint, loggedTransitionCheckpoints.insert("\(index)-\(checkpoint)").inserted {
                    let players = [window.outgoingId, window.incomingId].map { id -> String in
                        guard let player = engine.player(for: id) else { return "\(id):missing" }
                        return "\(id):rate=\(String(format: "%.1f", player.rate)),src=\(String(format: "%.3f", player.currentTime().seconds)),status=\(player.currentItem?.status.rawValue ?? -1)"
                    }.joined(separator: ";")
                    NSLog("[TransitionPlayerTest] project=%@ transition=%d kind=%@ checkpoint=%@ progress=%.3f t=%.1f players={%@}",
                          projectId, index + 1, window.kind.rawValue, checkpoint, progress, time, players)
                }
            }
        }

        XCTAssertEqual(engine.mode, .idle, "\(projectId) must reach the end, not stall at a transition")
        XCTAssertGreaterThan(highest, 11_000, "\(projectId) must play through the complete four clip track")
        XCTAssertGreaterThan(playbackPlayerSamples, 0, "\(projectId) must advance a real AVPlayer clock")
        XCTAssertGreaterThan(playerClockAdvances, 0, "\(projectId) AVPlayer source time must advance while rate is nonzero")
        if withTransitions {
            XCTAssertEqual(reachedWindows, Set(0..<3), "\(projectId) must pass through all three transition windows")
            for index in 0..<3 {
                XCTAssertGreaterThanOrEqual(highWaterByWindow[index] ?? 0, 0.9,
                                            "\(projectId) did not reach the end of transition \(index + 1)")
            }
        }
    }

    private func makePeopleProject(uri: String, projectId: String, withTransitions: Bool) throws -> V2Project {
        let media = try XCTUnwrap(VideoFileInfo.read(uri: uri), "real project media \(uri) is missing from app bundle/ImportedMedia")
        let segmentMs = 3_000.0
        XCTAssertGreaterThanOrEqual(media.durationMs, segmentMs * 4, "\(uri) needs at least 12 seconds for the four segment fixture")
        let assetId = "\(projectId)-asset"
        let clips = (0..<4).map { index -> V2Layer in
            let sourceStart = Double(index) * segmentMs
            return V2Layer(
                id: "\(projectId)-clip-\(index)", order: 0,
                frame: V2Frame(width: 360, height: 202.5), transform: .identity,
                timing: V2Timing(start: Double(index) * segmentMs, duration: segmentMs),
                payload: .video(V2VideoPayload(assetId: assetId, fit: "cover", trimStart: sourceStart,
                                               trimEnd: sourceStart + segmentMs, playbackRate: 1))
            )
        }
        let asset = V2Asset.video(V2VideoAsset(id: assetId, uri: uri, width: media.width,
                                               height: media.height, duration: media.durationMs))
        var project = V2Project(id: projectId,
                                composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
                                assets: [asset], layers: clips)
        if withTransitions {
            for (index, kind) in [TransitionKind.mix, .fadeBlack, .push].enumerated() {
                project = SetTransitionCommand(outgoingId: clips[index].id, incomingId: clips[index + 1].id,
                                               kind: kind, durationMs: 1_000).apply(to: project)
            }
        }
        return project
    }
    #endif

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

    // MARK: time floor + glide (trim: the playhead follows the edge, even before t0, and lands on it)

    func testThePlayheadCannotGoBelowZeroUnlessTheFloorIsLowered() {
        let engine = makeEngine()
        engine.beginScrub()
        engine.scrub(toMs: -500)
        XCTAssertEqual(engine.currentTimeMs, 0, "default floor is 0")

        engine.setTimeFloor(-1_000_000)
        engine.scrub(toMs: -500)
        XCTAssertEqual(engine.currentTimeMs, -500, "a main-lane trim lowers the floor")

        engine.setTimeFloor(0)
        engine.scrub(toMs: -200)
        XCTAssertEqual(engine.currentTimeMs, 0)
        engine.endScrub(velocityMsPerSecond: 0)
    }

    func testGlideLandsOnTheTargetThenRunsItsCompletionAndLeavesScrubbing() {
        let engine = makeEngine()
        engine.beginScrub()
        engine.setTimeFloor(-1000)
        engine.scrub(toMs: -400)
        engine.endScrub(velocityMsPerSecond: 0)

        let done = expectation(description: "glide finished")
        engine.glide(toMs: 3000, duration: 0.1) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(engine.currentTimeMs, 3000, accuracy: 0.5)
        XCTAssertEqual(engine.mode, .idle)
    }

    func testGlideToWhereTheyAlreadyAreCompletesAtOnce() {
        let engine = makeEngine()
        var finished = false
        engine.glide(toMs: 0) { finished = true }
        XCTAssertTrue(finished)
    }

    func testATouchDuringAGlideCancelsItButStillRunsTheCompletion() {
        let engine = makeEngine()
        var finished = false
        engine.glide(toMs: 5000, duration: 5) { finished = true }
        engine.beginScrub()
        XCTAssertTrue(finished, "the completion (which restores the time floor) must not be lost")
        engine.endScrub(velocityMsPerSecond: 0)
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
