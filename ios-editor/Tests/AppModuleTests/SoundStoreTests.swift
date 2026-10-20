import AVFoundation
import XCTest
@testable import NeonixEditor

/// `SoundStore`: the catalogue JSON, downloading a sound once into the cache, refusing a file that is not audio, and the project copy.
@MainActor
final class SoundStoreTests: XCTestCase {
    private var directory: URL!
    private var source: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sound-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: source, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for i in 0..<4410 { buffer.floatChannelData?[0][i] = sinf(Float(i) * 0.05) }
        try file.write(from: buffer)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sound(id: String = "sfx-test", url: URL? = nil) -> APISoundCatalogue.Sound {
        .init(id: id, name: "Test", category: "ui", url: url ?? source, durationMs: 100, mimeType: "audio/mp4", peaks: [1, 0.5])
    }

    private func store() -> SoundStore { SoundStore(cacheDirectory: directory.appendingPathComponent("cache", isDirectory: true)) }

    func testCatalogueDecodesAndRoundTripsThroughJSON() throws {
        let json = """
        {"categories":[{"id":"ui","title":"UI"}],
         "sounds":[{"id":"sfx-pop","name":"Pop","category":"ui","url":"https://cdn.test/pop.m4a","durationMs":180,"mimeType":"audio/mp4","peaks":[1,0.5,0.25]}]}
        """
        let catalogue = try NeonixAPIClient.decoder.decode(APISoundCatalogue.self, from: Data(json.utf8))
        XCTAssertEqual(catalogue.sounds[0].peaks, [1, 0.5, 0.25])
        XCTAssertEqual(catalogue.sounds[0].url.absoluteString, "https://cdn.test/pop.m4a")
        XCTAssertEqual(try JSONDecoder().decode(APISoundCatalogue.self, from: JSONEncoder().encode(catalogue)), catalogue)
    }

    func testLocalURLDownloadsOnceAndMarksTheSoundDownloaded() async {
        let store = store()
        let s = sound()
        XCTAssertFalse(store.isDownloaded(s))
        let first = await store.localURL(for: s)
        XCTAssertNotNil(first)
        XCTAssertTrue(store.isDownloaded(s))
        try? FileManager.default.removeItem(at: source)   // a second call must come from the cache, not the source
        let second = await store.localURL(for: s)
        XCTAssertEqual(first, second)
    }

    func testAFileThatIsNotAudioIsRefusedAndLeavesNothingBehind() async throws {
        let junk = directory.appendingPathComponent("junk.m4a")
        try Data("not audio".utf8).write(to: junk)
        let store = store()
        let s = sound(id: "sfx-junk", url: junk)
        let url = await store.localURL(for: s)
        XCTAssertNil(url)
        XCTAssertFalse(store.isDownloaded(s))
    }

    func testImportAssetCopiesTheFileIntoImportedMediaUnderALibraryId() async throws {
        let store = store()
        let s = sound(id: "sfx-import-\(UUID().uuidString.prefix(6).lowercased())")
        let asset = try await store.importAsset(for: s)
        XCTAssertEqual(asset.id, "library-\(s.id)")
        XCTAssertEqual(asset.uri, "library-\(s.id).m4a")
        XCTAssertEqual(asset.duration, 100)
        let copy = MediaImportService.importedMediaDirectory.appendingPathComponent(asset.uri)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        try? FileManager.default.removeItem(at: copy)
    }

    func testAnImportedSoundLandsOnTheAudioLaneAtThePlayheadAndItsAssetIsKeptOnce() async throws {
        let store = store()
        let s = sound(id: "sfx-lane-\(UUID().uuidString.prefix(6).lowercased())")
        let asset = try await store.importAsset(for: s)
        defer { try? FileManager.default.removeItem(at: MediaImportService.importedMediaDirectory.appendingPathComponent(asset.uri)) }
        var project = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        project = AddAudioClipCommand(asset: asset, durationMs: asset.duration, atMs: 1500).apply(to: project)
        project = AddAudioClipCommand(asset: asset, durationMs: asset.duration, atMs: 1550).apply(to: project)   // overlaps: a second track
        XCTAssertEqual(project.audio.tracks.count, 2)
        XCTAssertEqual(project.assets.count, 1, "the same sound shares one asset")
        XCTAssertEqual(project.audio.tracks[0].clips[0].timing.start, 1500)
    }
}
