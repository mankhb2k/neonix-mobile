import AVFoundation
import XCTest
@testable import NeonixEditor

/// Volume of a video clip's own sound: the command, the overlay copy staying silent, and which video layers `AudioMixEngine` plays.
@MainActor
final class VideoVolumeTests: XCTestCase {
    private var filename = ""

    override func setUpWithError() throws {
        // The engine resolves a video's file through `bundledURL`; any file under that name will do for building the source list.
        filename = "videovolume-\(UUID().uuidString).mov"
        try Data([0]).write(to: MediaImportService.importedMediaDirectory.appendingPathComponent(filename))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MediaImportService.importedMediaDirectory.appendingPathComponent(filename))
    }

    private func project(audio: V2EmbeddedVideoAudio? = nil, rate: Double? = nil, curve: [V2SpeedPoint]? = nil, trimStart: Double? = 250) -> V2Project {
        let asset = V2VideoAsset(id: "v1", uri: filename, width: 1080, height: 1920, duration: 5000)
        var payload = V2VideoPayload(assetId: "v1", trimStart: trimStart)
        payload.playbackRate = rate
        payload.speedCurve = curve
        payload.audio = audio
        let layer = V2Layer(id: "clip", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                            timing: V2Timing(start: 1000, duration: 4000), payload: .video(payload))
        return V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [.video(asset)], layers: [layer])
    }

    private func gain(_ project: V2Project) -> Double? {
        guard case .video(let payload)? = project.layers.first?.payload else { return nil }
        return payload.audio?.gainDb
    }

    // MARK: Command

    func testTheCommandWritesTheGainAndKeepsTheSoundOn() {
        let p = SetVideoClipVolumeCommand(layerId: "clip", gainDb: -6).apply(to: project())
        XCTAssertEqual(gain(p), -6)
        guard case .video(let payload)? = p.layers.first?.payload else { return XCTFail() }
        XCTAssertEqual(payload.audio?.enabled, true)
    }

    func testBackToNoChangeClearsTheGainButNotTheSwitch() {
        var p = SetVideoClipVolumeCommand(layerId: "clip", gainDb: 6).apply(to: project())
        p = SetVideoClipVolumeCommand(layerId: "clip", gainDb: 0).apply(to: p)
        XCTAssertNil(gain(p))
        guard case .video(let payload)? = p.layers.first?.payload else { return XCTFail() }
        XCTAssertEqual(payload.audio?.enabled, true)
    }

    func testAnUnknownOrNonVideoLayerIsLeftAlone() {
        let p = project()
        XCTAssertNil(gain(SetVideoClipVolumeCommand(layerId: "nope", gainDb: -6).apply(to: p)))
        let text = AddTextLayerCommand(layerId: "t", text: "Hi", atMs: 0).apply(to: p)
        let after = SetVideoClipVolumeCommand(layerId: "t", gainDb: -6).apply(to: text)
        XCTAssertEqual(after.layers.count, text.layers.count)
        XCTAssertNil(gain(after))
    }

    func testAnOverlayCopyIsSilentSoTheSoundIsNotDoubled() {
        let loud = SetVideoClipVolumeCommand(layerId: "clip", gainDb: 6).apply(to: project())
        let copied = CopyToOverlayCommand(layerId: "clip", newLayerId: "overlay-1").apply(to: loud)
        guard let copy = copied.layers.first(where: { $0.id == "overlay-1" }), case .video(let payload) = copy.payload else { return XCTFail() }
        XCTAssertEqual(payload.audio?.enabled, false)
        let engine = AudioMixEngine()
        engine.update(project: copied)
        XCTAssertEqual(engine.sources.map(\.id), ["clip"], "only the original's sound plays")
    }

    // MARK: Engine

    func testAVideoPlaysItsOwnSoundAtItsGainFromItsTrimStart() {
        let engine = AudioMixEngine()
        engine.update(project: SetVideoClipVolumeCommand(layerId: "clip", gainDb: -12).apply(to: project()))
        XCTAssertEqual(engine.sources.count, 1)
        let source = engine.sources[0]
        XCTAssertEqual(source.id, "clip")
        XCTAssertEqual(source.startMs, 1000)
        XCTAssertEqual(source.durationMs, 4000)
        XCTAssertEqual(source.trimStartMs, 250)
        XCTAssertEqual(source.gainDb, -12)
    }

    func testTheSoundIsOnByDefaultAtNoChange() {
        let engine = AudioMixEngine()
        engine.update(project: project())
        XCTAssertEqual(engine.sources.first?.gainDb, 0)
    }

    func testSwitchedOffSpeedChangedAndCurvedClipsStaySilent() {
        let engine = AudioMixEngine()
        engine.update(project: project(audio: V2EmbeddedVideoAudio(enabled: false, gainDb: nil, pan: nil, fadeIn: nil, fadeOut: nil)))
        XCTAssertTrue(engine.sources.isEmpty)
        engine.update(project: project(rate: 2))
        XCTAssertTrue(engine.sources.isEmpty, "this engine does not retime: a sped-up clip is silent")
        engine.update(project: project(curve: [V2SpeedPoint(sourceMs: 0, rate: 1, slope: nil), V2SpeedPoint(sourceMs: 4000, rate: 2, slope: nil)]))
        XCTAssertTrue(engine.sources.isEmpty)
    }

    func testAVideoVolumeOfMuteIsSilenceAndTenTimesIsLoud() {
        let engine = AudioMixEngine()
        let mute = SetVideoClipVolumeCommand(layerId: "clip", gainDb: VolumeScale.gainDb(forMultiplier: 0)).apply(to: project())
        engine.update(project: mute)
        XCTAssertEqual(engine.volume(for: engine.sources[0], atMs: 2000), 0, accuracy: 0.0001)
        let ten = SetVideoClipVolumeCommand(layerId: "clip", gainDb: VolumeScale.gainDb(forMultiplier: 10)).apply(to: project())
        engine.update(project: ten)
        XCTAssertEqual(engine.volume(for: engine.sources[0], atMs: 2000), 10, accuracy: 0.01)
    }

    // MARK: Main lane speaker button

    private func twoLanes() -> V2Project {
        var p = project()
        guard case .video(let payload)? = p.layers.first?.payload else { return p }
        // Another video on a lane above (not the main one), and an overlay copy.
        var other = V2Layer(id: "upper", order: 1, frame: V2Frame(width: 360, height: 640), transform: .identity,
                            timing: V2Timing(start: 0, duration: 1000), payload: .video(payload))
        other.order = 1
        p = p.withLayers(p.layers + [other])
        return CopyToOverlayCommand(layerId: "clip", newLayerId: "overlay-1").apply(to: p)
    }

    private func enabled(_ project: V2Project, _ id: String) -> Bool? {
        guard let layer = project.layers.first(where: { $0.id == id }), case .video(let payload) = layer.payload else { return nil }
        return payload.audio?.enabled
    }

    func testTheSpeakerMutesTheMainLaneVideosOnlyAndKeepsTheirVolume() {
        let loud = SetVideoClipVolumeCommand(layerId: "clip", gainDb: -6).apply(to: twoLanes())
        XCTAssertFalse(SetMainLaneSoundCommand.isMuted(loud.layers))
        let muted = SetMainLaneSoundCommand(muted: true).apply(to: loud)
        XCTAssertEqual(enabled(muted, "clip"), false)
        XCTAssertNotEqual(enabled(muted, "upper"), false, "another lane is not touched")
        XCTAssertEqual(gain(muted), -6, "the volume is kept")
        XCTAssertTrue(SetMainLaneSoundCommand.isMuted(muted.layers))
        let engine = AudioMixEngine()
        engine.update(project: muted)
        XCTAssertFalse(engine.sources.contains { $0.id == "clip" }, "a muted main lane plays nothing")
    }

    func testTheSpeakerBringsTheSoundBackAndAFreshClipUnmutesTheState() {
        var p = SetMainLaneSoundCommand(muted: true).apply(to: twoLanes())
        p = SetMainLaneSoundCommand(muted: false).apply(to: p)
        XCTAssertEqual(enabled(p, "clip"), true)
        XCTAssertFalse(SetMainLaneSoundCommand.isMuted(p.layers))
        // Muted, then a clip with sound lands on the main lane: the lane is no longer all muted.
        var muted = SetMainLaneSoundCommand(muted: true).apply(to: twoLanes())
        guard case .video(let payload)? = muted.layers.first?.payload else { return XCTFail() }
        var fresh = payload
        fresh.audio = nil
        muted = muted.withLayers(muted.layers + [V2Layer(id: "new", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                                                         timing: V2Timing(start: 5000, duration: 1000), payload: .video(fresh))])
        XCTAssertFalse(SetMainLaneSoundCommand.isMuted(muted.layers))
    }

    func testTheSpeakerDoesNothingWithoutAMainLane() {
        let empty = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        XCTAssertEqual(SetMainLaneSoundCommand(muted: true).apply(to: empty).layers.count, 0)
        XCTAssertFalse(SetMainLaneSoundCommand.isMuted([]))
    }
}
