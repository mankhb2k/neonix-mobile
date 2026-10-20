import XCTest
import AVFoundation
@testable import NeonixEditor

/// `PeakWaveformCache`: a fine envelope of an audio file, ~200 values per second, as fractions of full scale.
@MainActor
final class PeakWaveformCacheTests: XCTestCase {
    private var created: [URL] = []

    override func tearDown() async throws {
        for url in created { try? FileManager.default.removeItem(at: url) }
    }

    /// A mono file of `seconds`: `signal(i)` per sample, at 44.1 kHz.
    private func makeFile(seconds: Double, signal: (Int) -> Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("peaks-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = signal(i) }
        try file.write(from: buffer)
        created.append(url)
        return url
    }

    func testAboutTwoHundredValuesPerSecondAsFractionsOfFullScale() async throws {
        // Half a second of a quiet tone, then half a second of a tone four times louder.
        let url = try makeFile(seconds: 1) { i in (i < 22050 ? 0.1 : 0.4) * sinf(Float(i) * 0.3) }
        let envelopeMaybe = await PeakWaveformCache.shared.envelope(url: url)
        let envelope = try XCTUnwrap(envelopeMaybe)
        XCTAssertEqual(Double(envelope.values.count), 1000 / PeakEnvelope.bucketMs, accuracy: 3)
        XCTAssertEqual(envelope.values.max() ?? 0, 0.4, accuracy: 0.02, "the loud half's amplitude, not scaled")
        XCTAssertEqual(envelope.peak, envelope.values.max() ?? -1, "the peak is the loudest value")
        let quiet = envelope.values[20 ..< 80].max() ?? 1, loud = envelope.values[120 ..< 180].max() ?? 0
        XCTAssertEqual(Double(quiet / loud), 0.25, accuracy: 0.05, "the quiet half stays a quarter as tall")
    }

    func testSilenceStaysFlatWithoutBlowingUp() async throws {
        let url = try makeFile(seconds: 0.5) { _ in 0 }
        let envelopeMaybe = await PeakWaveformCache.shared.envelope(url: url)
        let envelope = try XCTUnwrap(envelopeMaybe)
        XCTAssertFalse(envelope.values.isEmpty)
        XCTAssertTrue(envelope.values.allSatisfy { $0 == 0 })
    }

    func testASecondAskIsServedFromTheCache() async throws {
        let url = try makeFile(seconds: 0.5) { i in 0.5 * sinf(Float(i) * 0.2) }
        let firstMaybe = await PeakWaveformCache.shared.envelope(url: url)
        let first = try XCTUnwrap(firstMaybe)
        try FileManager.default.removeItem(at: url)   // the file is gone; the cached envelope is not
        let secondMaybe = await PeakWaveformCache.shared.envelope(url: url)
        let second = try XCTUnwrap(secondMaybe)
        XCTAssertEqual(first.values, second.values)
    }
}
