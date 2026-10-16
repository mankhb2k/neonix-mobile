import XCTest
@testable import NeonixEditor

final class StorageUsageTests: XCTestCase {
    private var root: URL!
    private var locations: StorageLocations!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("Library", isDirectory: true)
        locations = StorageLocations(
            documents: root.appendingPathComponent("Documents", isDirectory: true),
            library: library,
            tmp: root.appendingPathComponent("tmp", isDirectory: true),
            media: root.appendingPathComponent("Documents/ImportedMedia", isDirectory: true),
            templates: library.appendingPathComponent("Application Support/Templates", isDirectory: true),
            caches: library.appendingPathComponent("Caches", isDirectory: true)
        )
        for dir in [locations.media, locations.templates, locations.caches, locations.tmp] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ kilobytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: kilobytes * 1024).write(to: url)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testASizeCountsEveryFileInsideNestedFolders() throws {
        try write(100, to: locations.caches.appendingPathComponent("a.bin"))
        try write(200, to: locations.caches.appendingPathComponent("Stickers/b.bin"))

        let size = StorageUsage.size(of: locations.caches)

        XCTAssertGreaterThanOrEqual(size, 300 * 1024)
        XCTAssertLessThan(size, 300 * 1024 + 64 * 1024, "only block rounding on top")
        XCTAssertEqual(StorageUsage.size(of: root.appendingPathComponent("missing")), 0)
    }

    func testTheSnapshotSplitsMediaTemplatesAndCache() throws {
        try write(500, to: locations.media.appendingPathComponent("clip.mov"))
        try write(300, to: locations.templates.appendingPathComponent("t1/v1/document.json"))
        try write(100, to: locations.caches.appendingPathComponent("x.bin"))
        try write(50, to: locations.tmp.appendingPathComponent("rec.m4a"))

        let snapshot = StorageUsage.measure(locations)

        XCTAssertGreaterThanOrEqual(snapshot.media, 500 * 1024)
        XCTAssertGreaterThanOrEqual(snapshot.templates, 300 * 1024)
        XCTAssertGreaterThanOrEqual(snapshot.cache, 150 * 1024, "Caches + tmp")
        XCTAssertGreaterThanOrEqual(snapshot.total, snapshot.media + snapshot.templates + snapshot.cache - 64 * 1024)
    }

    func testClearingTheCacheEmptiesCachesAndTmpButKeepsFolderAndEverythingElse() throws {
        try write(100, to: locations.caches.appendingPathComponent("loose.bin"))
        try write(100, to: locations.caches.appendingPathComponent("Stickers/s.png"))
        try write(100, to: locations.tmp.appendingPathComponent("rec.m4a"))
        let media = locations.media.appendingPathComponent("clip.mov")
        let template = locations.templates.appendingPathComponent("t1/v1/document.json")
        try write(100, to: media)
        try write(100, to: template)

        StorageUsage.clearCache(locations)

        XCTAssertFalse(exists(locations.caches.appendingPathComponent("loose.bin")))
        XCTAssertFalse(exists(locations.caches.appendingPathComponent("Stickers/s.png")))
        XCTAssertTrue(exists(locations.caches.appendingPathComponent("Stickers")), "a store that made its folder at launch can keep writing")
        XCTAssertFalse(exists(locations.tmp.appendingPathComponent("rec.m4a")))
        XCTAssertTrue(exists(media), "the user's media is never touched")
        XCTAssertTrue(exists(template))
    }

    func testRemovingTemplatesLeavesMediaAndCache() throws {
        let media = locations.media.appendingPathComponent("clip.mov")
        let cached = locations.caches.appendingPathComponent("x.bin")
        try write(100, to: media)
        try write(100, to: cached)
        try write(100, to: locations.templates.appendingPathComponent("t1/v1/document.json"))

        StorageUsage.removeDownloadedTemplates(locations)

        XCTAssertEqual(StorageUsage.size(of: locations.templates), 0)
        XCTAssertTrue(exists(locations.templates), "the folder stays")
        XCTAssertTrue(exists(media))
        XCTAssertTrue(exists(cached))
    }
}
