import XCTest
import AVFoundation
@testable import NeonixEditor

/// Covers `MediaImportService.extractAudio` (Trích xuất) — the export
/// machinery doesn't care whether its source is a video-with-audio file or
/// a plain audio file, so a synthesized WAV stands in for "a video asset"
/// here; this app's own bundled sample videos have no audio track at all
/// (see CLAUDE.md), so there's no real video-with-audio fixture to extract
/// from in this repo yet.
@MainActor
final class MediaImportServiceTests: XCTestCase {
    private var sourceURL: URL!
    private let sourceDurationSeconds = 1.0

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("extract-source-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(44100 * sourceDurationSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // A pure silent buffer exports fine, but a non-zero signal is a
        // closer stand-in for a real video's audio track and rules out any
        // "export quietly no-ops on silence" false positive.
        for i in 0..<Int(frameCount) {
            buffer.floatChannelData?[0][i] = sinf(Float(i) * 0.05)
        }
        try file.write(from: buffer)
        sourceURL = url
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceURL)
        let extractedURL = MediaImportService.importedMediaDirectory
            .appendingPathComponent("extracted-\(sourceURL.deletingPathExtension().lastPathComponent).m4a")
        try? FileManager.default.removeItem(at: extractedURL)
    }

    func testExtractAudioProducesARealFileWithTheSourceDuration() async throws {
        let asset = try await MediaImportService.extractAudio(from: sourceURL)

        XCTAssertEqual(asset.duration, sourceDurationSeconds * 1000, accuracy: 50)
        XCTAssertTrue(asset.uri.hasPrefix("extracted-"))

        let resolved = bundledURL(filename: asset.uri)
        XCTAssertNotNil(resolved)
        if let resolved {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
        }
    }

    func testExtractAudioReusesTheCachedFileOnASecondCall() async throws {
        let first = try await MediaImportService.extractAudio(from: sourceURL)
        let second = try await MediaImportService.extractAudio(from: sourceURL)

        // Same stable id/uri — `AddAudioClipCommand`'s dedupe relies on this
        // to avoid appending a duplicate `project.assets` entry when the
        // user extracts from the same source video twice.
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.uri, second.uri)
    }
}
