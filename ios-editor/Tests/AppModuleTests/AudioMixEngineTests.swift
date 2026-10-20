import XCTest
import AVFoundation
@testable import NeonixEditor

/// Covers `AudioMixEngine`'s pure logic — which sources `update(project:)`
/// builds, and the fade/gain volume math — without exercising the real
/// `AVAudioEngine` render graph (not meaningfully testable outside a real
/// audio session; see the "audio playback foundation" roadmap plan's own
/// verification note).
@MainActor
final class AudioMixEngineTests: XCTestCase {
    /// `update(project:)` resolves each source's file via `bundledURL`,
    /// which checks `MediaImportService.importedMediaDirectory` — writing a
    /// tiny real (silent) `.caf` there, rather than stubbing the resolver,
    /// keeps this test exercising the actual lookup path.
    private var tempFilename = ""

    override func setUpWithError() throws {
        let filename = "audiomixtest-\(UUID().uuidString).caf"
        let url = MediaImportService.importedMediaDirectory.appendingPathComponent(filename)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 2)!
        buffer.frameLength = buffer.frameCapacity
        try file.write(from: buffer)
        tempFilename = filename
    }

    override func tearDownWithError() throws {
        let url = MediaImportService.importedMediaDirectory.appendingPathComponent(tempFilename)
        try? FileManager.default.removeItem(at: url)
    }

    private func makeProject(clip: V2AudioClip, muted: Bool = false) -> V2Project {
        let asset = V2AudioAsset(id: "a1", uri: tempFilename, mimeType: "audio/x-caf", duration: 2000)
        let track = V2AudioTrack(id: "t1", gainDb: nil, pan: 0, muted: muted, clips: [clip])
        return V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
            assets: [.audio(asset)],
            layers: [],
            audio: V2AudioDomain(sampleRate: 48000, tracks: [track])
        )
    }

    func testUpdateBuildsOneSourcePerEnabledClip() {
        let clip = V2AudioClip(
            id: "clip1", assetId: "a1",
            timing: V2AudioClipTiming(start: 500, duration: 1500),
            trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1, gainDb: -6
        )
        let engine = AudioMixEngine()
        engine.update(project: makeProject(clip: clip))

        XCTAssertEqual(engine.sources.count, 1)
        let source = engine.sources[0]
        XCTAssertEqual(source.id, "clip1")
        XCTAssertEqual(source.startMs, 500)
        XCTAssertEqual(source.durationMs, 1500)
        XCTAssertEqual(source.gainDb, -6)
    }

    func testUpdateSkipsClipsOnAMutedTrack() {
        let clip = V2AudioClip(
            id: "clip1", assetId: "a1",
            timing: V2AudioClipTiming(start: 0, duration: 1000),
            trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1
        )
        let engine = AudioMixEngine()
        engine.update(project: makeProject(clip: clip, muted: true))

        XCTAssertTrue(engine.sources.isEmpty)
    }

    func testUpdateSkipsExplicitlyDisabledClips() {
        var clip = V2AudioClip(
            id: "clip1", assetId: "a1",
            timing: V2AudioClipTiming(start: 0, duration: 1000),
            trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1
        )
        clip.enabled = false
        let engine = AudioMixEngine()
        engine.update(project: makeProject(clip: clip))

        XCTAssertTrue(engine.sources.isEmpty)
    }

    func testVolumeAppliesLinearFadeInNearClipStart() {
        let source = AudioMixEngine.AudioSource(
            id: "s", url: URL(fileURLWithPath: "/dev/null"),
            startMs: 1000, durationMs: 4000, trimStartMs: 0,
            gainDb: 0, pan: 0,
            fadeIn: V2AudioFade(duration: 1000, curve: .linear), fadeOut: nil
        )
        let engine = AudioMixEngine()

        // Halfway through the 1000ms fade-in (atMs 1500 -> elapsed 500ms).
        XCTAssertEqual(engine.volume(for: source, atMs: 1500), 0.5, accuracy: 0.001)
        // Past the fade window entirely -> full volume.
        XCTAssertEqual(engine.volume(for: source, atMs: 3000), 1.0, accuracy: 0.001)
    }

    func testVolumeAppliesGainDbAndEqualPowerFadeOut() {
        let source = AudioMixEngine.AudioSource(
            id: "s", url: URL(fileURLWithPath: "/dev/null"),
            startMs: 0, durationMs: 2000, trimStartMs: 0,
            gainDb: -20, pan: 0,
            fadeIn: nil, fadeOut: V2AudioFade(duration: 1000, curve: .equalPower)
        )
        let engine = AudioMixEngine()

        // -20dB -> linear 0.1. At atMs 1500, 500ms remain of the 1000ms
        // fade-out -> fraction 0.5 -> sin(0.5 * pi/2) for equal-power.
        let expected = Float(pow(10, -20.0 / 20) * sin(0.5 * Double.pi / 2))
        XCTAssertEqual(engine.volume(for: source, atMs: 1500), expected, accuracy: 0.0001)
    }
}

/// The Volume tool's scale (`VolumeScale`: 0, 1 and 10 times) and the engine's gain math at its ends.
@MainActor
final class VolumeScaleTests: XCTestCase {
    func testLabelsShowTheMultiplier() {
        XCTAssertEqual(VolumeScale.label(0), "Mute")
        XCTAssertEqual(VolumeScale.label(0.91), "0.91×")
        XCTAssertEqual(VolumeScale.label(0.5), "0.50×")
        XCTAssertEqual(VolumeScale.label(1), "1×")
        XCTAssertEqual(VolumeScale.label(1.2), "1.2×")
        XCTAssertEqual(VolumeScale.label(2), "2×")
        XCTAssertEqual(VolumeScale.label(10), "10×")
    }

    func testStepsAreHundredthsBelowOneAndTenthsFromOneUp() {
        XCTAssertEqual(VolumeScale.snapped(0.914), 0.91)
        XCTAssertEqual(VolumeScale.snapped(0.926), 0.93)
        XCTAssertEqual(VolumeScale.snapped(1.14), 1.1)
        XCTAssertEqual(VolumeScale.snapped(1.16), 1.2)
        XCTAssertEqual(VolumeScale.snapped(12), 10, "10 is the top")
        XCTAssertEqual(VolumeScale.snapped(-1), 0)
    }

    func testStoredDecibelsAndTheEnginesLinearGain() {
        XCTAssertEqual(VolumeScale.gainDb(forMultiplier: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(VolumeScale.gainDb(forMultiplier: 10), 20, accuracy: 1e-9, "10x is +20 dB")
        XCTAssertEqual(VolumeScale.gainDb(forMultiplier: 0.5), -6.0206, accuracy: 0.001)
        XCTAssertEqual(VolumeScale.gainDb(forMultiplier: 0), VolumeScale.muteDb, "0 is stored as the Mute dB")
        XCTAssertEqual(VolumeScale.linearGain(VolumeScale.muteDb), 0, "and plays as silence, not 0.001")
        XCTAssertEqual(VolumeScale.linearGain(0), 1, accuracy: 1e-9)
        XCTAssertEqual(VolumeScale.linearGain(20), 10, accuracy: 1e-9)
        // A stored dB reads back as the multiplier the user chose.
        for m in [0.0, 0.01, 0.5, 0.91, 0.99, 1, 1.1, 1.2, 3.5, 9.9, 10] {
            XCTAssertEqual(VolumeScale.multiplier(forGainDb: VolumeScale.gainDb(forMultiplier: m)), m, accuracy: 1e-9, "\(m)")
        }
    }

    func testOneIsTheMiddleOfTheSliderAndTheEndsAreZeroAndTen() {
        XCTAssertEqual(VolumeScale.position(forMultiplier: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(VolumeScale.position(forMultiplier: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(VolumeScale.position(forMultiplier: 10), 1, accuracy: 1e-9)
        XCTAssertEqual(VolumeScale.multiplier(forPosition: 0), 0)
        XCTAssertEqual(VolumeScale.multiplier(forPosition: 0.5), 1)
        XCTAssertEqual(VolumeScale.multiplier(forPosition: 1), 10)
        XCTAssertEqual(VolumeScale.multiplier(forPosition: 0.25), 0.5, "halfway along the lowering half")
        XCTAssertEqual(VolumeScale.multiplier(forPosition: 0.75), 5.5, "halfway along the boosting half")
        // Every notch survives the round trip through the slider.
        for hundredth in 0...100 {
            let m = Double(hundredth) / 100
            XCTAssertEqual(VolumeScale.multiplier(forPosition: VolumeScale.position(forMultiplier: m)), m, accuracy: 1e-9)
        }
        for tenth in 10...100 {
            let m = Double(tenth) / 10
            XCTAssertEqual(VolumeScale.multiplier(forPosition: VolumeScale.position(forMultiplier: m)), m, accuracy: 1e-9)
        }
    }

    /// The boost stage the engine uses: a player node's volume stops at 1, `AVAudioUnitEQ.globalGain` (no bands) adds dB above that. Rendered offline.
    func testTheBoostStageRaisesTheLevelAboveUnity() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frames: AVAudioFrameCount = 8192
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        source.frameLength = frames
        for i in 0..<Int(frames) { source.floatChannelData![0][i] = 0.2 * sinf(Float(i) * 0.05) }

        func renderedPeak(boostDb: Float) throws -> Float {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let boost = AVAudioUnitEQ(numberOfBands: 0)
            engine.attach(player); engine.attach(boost)
            engine.connect(player, to: boost, format: format)
            engine.connect(boost, to: engine.mainMixerNode, format: format)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            boost.globalGain = boostDb
            player.scheduleBuffer(source, at: nil)
            try engine.start()
            player.play()
            let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            var peak: Float = 0
            for _ in 0..<2 {
                guard try engine.renderOffline(4096, to: out) != .error else { break }
                for i in 0..<Int(out.frameLength) { peak = max(peak, abs(out.floatChannelData![0][i])) }
            }
            engine.stop()
            return peak
        }
        let plain = try renderedPeak(boostDb: 0)
        let boosted = try renderedPeak(boostDb: 12)
        XCTAssertGreaterThan(plain, 0.05, "the unboosted signal comes through (the mixer takes about 3 dB off a centred mono source)")
        XCTAssertEqual(boosted / plain, 3.98, accuracy: 0.2, "+12 dB is about 4x")
    }
}

/// Fade in / out of an audio clip: at most 10 s, never longer than the clip.
@MainActor
final class AudioFadeTests: XCTestCase {
    private func clip(duration: Double) -> V2AudioClip {
        V2AudioClip(id: "c", assetId: "a", timing: V2AudioClipTiming(start: 0, duration: duration), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1)
    }

    private func project(_ clip: V2AudioClip) -> V2Project {
        V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [],
            audio: V2AudioDomain(sampleRate: 48000, tracks: [V2AudioTrack(id: "t", gainDb: nil, pan: 0, muted: false, clips: [clip])])
        )
    }

    func testTheLimitIsTenSecondsOrTheClipWhicheverIsShorter() {
        XCTAssertEqual(AudioFadeLimit.maxMs(forClipDurationMs: 9000), 9000, "a 9 s clip fades for at most 9 s")
        XCTAssertEqual(AudioFadeLimit.maxMs(forClipDurationMs: 11_000), 10_000, "an 11 s clip for at most 10 s")
        XCTAssertEqual(AudioFadeLimit.maxMs(forClipDurationMs: 262_000), 10_000)
        XCTAssertEqual(AudioFadeLimit.maxMs(forClipDurationMs: 0), 0)
    }

    func testTheCommandSetsBothFadesAndClampsThemToTheLimit() {
        let long = SetAudioClipFadeCommand(clipId: "c", fadeInMs: 1500, fadeOutMs: 20_000).apply(to: project(clip(duration: 30_000)))
        let a = long.audio.tracks[0].clips[0]
        XCTAssertEqual(a.fadeIn?.duration, 1500)
        XCTAssertEqual(a.fadeOut?.duration, 10_000, "10 s at most")
        XCTAssertEqual(a.fadeIn?.curve, .equalPower)

        let short = SetAudioClipFadeCommand(clipId: "c", fadeInMs: 9500, fadeOutMs: 0).apply(to: project(clip(duration: 9000)))
        let b = short.audio.tracks[0].clips[0]
        XCTAssertEqual(b.fadeIn?.duration, 9000, "a 9 s clip cannot fade for longer than itself")
        XCTAssertNil(b.fadeOut, "0 = no fade")
    }

    func testAnUnknownClipLeavesTheProjectAlone() {
        let p = project(clip(duration: 5000))
        let result = SetAudioClipFadeCommand(clipId: "nope", fadeInMs: 1000, fadeOutMs: 1000).apply(to: p)
        XCTAssertNil(result.audio.tracks[0].clips[0].fadeIn)
    }

    func testAFadeOfTheCommandIsPlayedByTheEngineMath() {
        let engine = AudioMixEngine()
        let source = AudioMixEngine.AudioSource(
            id: "c", url: URL(fileURLWithPath: "/dev/null"), startMs: 0, durationMs: 10_000, trimStartMs: 0, gainDb: 0, pan: 0,
            fadeIn: V2AudioFade(duration: 2000, curve: .equalPower), fadeOut: nil
        )
        XCTAssertEqual(engine.volume(for: source, atMs: 0), 0, accuracy: 0.001)
        XCTAssertEqual(engine.volume(for: source, atMs: 1000), Float(sin(Double.pi / 4)), accuracy: 0.001)
        XCTAssertEqual(engine.volume(for: source, atMs: 5000), 1, accuracy: 0.001)
    }

    func testTheEnvelopeIsEqualPowerAndTwoOverlappingFadesMultiply() {
        let fadeIn = V2AudioFade(duration: 2000, curve: .equalPower)
        XCTAssertEqual(AudioFadeEnvelope.gain(elapsedMs: 0, durationMs: 10_000, fadeIn: fadeIn, fadeOut: nil), 0, accuracy: 1e-9)
        XCTAssertEqual(AudioFadeEnvelope.gain(elapsedMs: 1000, durationMs: 10_000, fadeIn: fadeIn, fadeOut: nil), sin(Double.pi / 4), accuracy: 1e-9)
        XCTAssertEqual(AudioFadeEnvelope.gain(elapsedMs: 4000, durationMs: 10_000, fadeIn: fadeIn, fadeOut: nil), 1)
        XCTAssertEqual(AudioFadeEnvelope.gain(elapsedMs: 4000, durationMs: 10_000, fadeIn: nil, fadeOut: nil), 1, "no fade, no change")
        let linear = V2AudioFade(duration: 2000, curve: .linear)
        XCTAssertEqual(AudioFadeEnvelope.gain(elapsedMs: 500, durationMs: 10_000, fadeIn: linear, fadeOut: nil), 0.25, accuracy: 1e-9)
        // A 4 s clip fading 3 s in and 3 s out: at 2 s both fades are at 2/3 of... in at 2/3, out at 2/3 -> multiplied.
        let a = V2AudioFade(duration: 3000, curve: .linear)
        XCTAssertEqual(AudioFadeEnvelope.gain(elapsedMs: 2000, durationMs: 4000, fadeIn: a, fadeOut: a), (2.0 / 3) * (2.0 / 3), accuracy: 1e-9)
    }

    func testTheTwoToneBodyIsTheWholeClipWithoutAFadeAndCurvesWhereItFades() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 30)
        let plain = AudioFadeBodyShape(durationMs: 10_000, fadeIn: nil, fadeOut: nil).path(in: rect)
        XCTAssertTrue(plain.contains(CGPoint(x: 2, y: 2)), "no fade: the 45 % area fills the clip, corner included")
        XCTAssertTrue(plain.contains(CGPoint(x: 398, y: 2)))

        let faded = AudioFadeBodyShape(
            durationMs: 10_000, fadeIn: V2AudioFade(duration: 5000, curve: .equalPower), fadeOut: V2AudioFade(duration: 2000, curve: .equalPower)
        ).path(in: rect)
        XCTAssertFalse(faded.contains(CGPoint(x: 2, y: 2)), "the top-left corner is cut off by the fade in")
        XCTAssertTrue(faded.contains(CGPoint(x: 20, y: 29.5)), "the foot of the fade in is inside (the curve starts at the corner)")
        XCTAssertTrue(faded.contains(CGPoint(x: 200, y: 2)), "the middle is full height")
        XCTAssertFalse(faded.contains(CGPoint(x: 398, y: 2)), "and the top-right corner is cut off by the fade out")
        XCTAssertTrue(faded.contains(CGPoint(x: 380, y: 29.5)), "and so is the foot of the fade out")
    }
}
