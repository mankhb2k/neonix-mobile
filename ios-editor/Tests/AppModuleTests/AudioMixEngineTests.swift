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
