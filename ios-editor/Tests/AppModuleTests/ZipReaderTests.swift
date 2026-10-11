import XCTest
@testable import NeonixEditor

enum ZipFixtures {
    /// manifest.json (deflate), assets/note.txt (stored), empty.txt — built with Python's zipfile.
    static let good = "UEsDBBQAAAAIAAAAIQAC2UgbHwAAAEYBAAANAAAAbWFuaWZlc3QuanNvbqtWykjNyclXslIqzy/KSVHSUSpITAHyKkYB0UCpFgBQSwMEFAAAAAAAAAAhALUBrw8LAAAACwAAAA8AAABhc3NldHMvbm90ZS50eHRzdG9yZWQgdGV4dFBLAwQUAAAAAAAAACEAAAAAAAAAAAAAAAAACQAAAGVtcHR5LnR4dFBLAQIUAxQAAAAIAAAAIQAC2UgbHwAAAEYBAAANAAAAAAAAAAAAAACAAQAAAABtYW5pZmVzdC5qc29uUEsBAhQDFAAAAAAAAAAhALUBrw8LAAAACwAAAA8AAAAAAAAAAAAAAIABSgAAAGFzc2V0cy9ub3RlLnR4dFBLAQIUAxQAAAAAAAAAIQAAAAAAAAAAAAAAAAAJAAAAAAAAAAAAAACAAYIAAABlbXB0eS50eHRQSwUGAAAAAAMAAwCvAAAAqQAAAAAA"
    /// One entry named "../evil.txt".
    static let traversal = "UEsDBBQAAAAAAAAAIQAtU7Q7BQAAAAUAAAALAAAALi4vZXZpbC50eHRvd25lZFBLAQIUAxQAAAAAAAAAIQAtU7Q7BQAAAAUAAAALAAAAAAAAAAAAAACAAQAAAAAuLi9ldmlsLnR4dFBLBQYAAAAAAQABADkAAAAuAAAAAAA="
    /// One entry named "/abs.txt".
    static let absolute = "UEsDBBQAAAAAAAAAIQAtU7Q7BQAAAAUAAAAIAAAAL2Ficy50eHRvd25lZFBLAQIUAxQAAAAAAAAAIQAtU7Q7BQAAAAUAAAAIAAAAAAAAAAAAAACAAQAAAAAvYWJzLnR4dFBLBQYAAAAAAQABADYAAAArAAAAAAA="
}

final class ZipReaderTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testExtractsDeflatedAndStoredEntries() throws {
        let zip = try ZipReader(data: Data(base64Encoded: ZipFixtures.good)!)
        XCTAssertEqual(zip.entries.map(\.name).sorted(), ["assets/note.txt", "empty.txt", "manifest.json"])

        let directory = try temporaryDirectory()
        try zip.extract(to: directory)
        let manifest = try String(contentsOf: directory.appendingPathComponent("manifest.json"))
        XCTAssertTrue(manifest.hasPrefix(#"{"hello":"world""#))
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("assets/note.txt")), "stored text")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("empty.txt")).count, 0)
    }

    func testRejectsPathsThatEscapeTheTargetFolder() throws {
        let directory = try temporaryDirectory()
        for fixture in [ZipFixtures.traversal, ZipFixtures.absolute] {
            let zip = try ZipReader(data: Data(base64Encoded: fixture)!)
            XCTAssertThrowsError(try zip.extract(to: directory)) { error in
                guard case ZipError.unsafePath = error else { return XCTFail("expected unsafePath, got \(error)") }
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("evil.txt").path))
    }

    func testRejectsNonZipAndTruncatedData() {
        XCTAssertThrowsError(try ZipReader(data: Data("not a zip at all, just some text".utf8)))
        let good = Data(base64Encoded: ZipFixtures.good)!
        XCTAssertThrowsError(try ZipReader(data: good.prefix(good.count / 2)))
    }
}
