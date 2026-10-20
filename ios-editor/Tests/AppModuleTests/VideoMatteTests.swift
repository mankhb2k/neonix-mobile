import AVFoundation
import CoreImage
import XCTest
@testable import NeonixEditor

/// Remove BG on video: the matte store (frame grid, codec, files, neighbours) and the job that fills it. The job needs Vision, so it only runs on the iPhone.
final class VideoMatteTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("matte-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A 512 x 512 Vision-style soft mask: 1.0 inside a centred box, 0 outside.
    private func floatMask(boxFraction: Float = 0.5) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 512, 512, kCVPixelFormatType_OneComponent32Float, nil, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!, stride = CVPixelBufferGetBytesPerRow(pixels)
        let low = Int(256 * (1 - boxFraction)), high = Int(256 * (1 + boxFraction))
        for y in 0..<512 {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
            for x in 0..<512 { row[x] = (low..<high).contains(x) && (low..<high).contains(y) ? 1 : 0 }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    private func value(of image: CIImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return pixel[0]
    }

    func testPreferredTransformsMapToExifOrientations() {
        XCTAssertEqual(VideoOrientation.orientation(for: .identity), .up)
        XCTAssertEqual(VideoOrientation.orientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)), .right, "the usual portrait iPhone clip")
        XCTAssertEqual(VideoOrientation.orientation(for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), .left)
        XCTAssertEqual(VideoOrientation.orientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)), .down)
    }

    func testAPortraitClipIsTurnedUprightNotUpsideDown() {
        // A stored frame 2 wide, 1 tall: red on the left, blue on the right. Turned upright for a 90-degree clip (.right) it is 1 wide, 2 tall with red ON TOP.
        let stored = CIImage(bitmapData: Data([255, 0, 0, 255, 0, 0, 255, 255]), bytesPerRow: 8, size: CGSize(width: 2, height: 1), format: .RGBA8, colorSpace: nil)
        let upright = VideoOrientation.upright(stored, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0))
        XCTAssertEqual(upright.extent, CGRect(x: 0, y: 0, width: 1, height: 2))
        func pixel(y: Int) -> [UInt8] {
            var p = [UInt8](repeating: 0, count: 4)
            CIContext(options: [.workingColorSpace: NSNull()]).render(upright, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: 0, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return p
        }
        XCTAssertEqual(pixel(y: 1).prefix(3).map { $0 }, [255, 0, 0], "red is at the top (CIImage y grows upward)")
        XCTAssertEqual(pixel(y: 0).prefix(3).map { $0 }, [0, 0, 255])
    }

    func testTheFrameGridIsThirtyPerSecondOfSourceTime() {
        XCTAssertEqual(MatteSet.index(forSourceSeconds: 0), 0)
        XCTAssertEqual(MatteSet.index(forSourceSeconds: 1), 30)
        XCTAssertEqual(MatteSet.index(forSourceSeconds: 1.0 / 60 + 0.001), 1, "half a grid step rounds up")
        XCTAssertEqual(MatteSet.index(forSourceSeconds: -3), 0)
    }

    func testAMatteSurvivesTheCodecAndIsMuchSmallerThanRaw() throws {
        let data = try XCTUnwrap(MatteSet.encode(floatMask()))
        XCTAssertLessThan(data.count, 20_000, "a flat matte compresses to a few KB (raw is 262 144 bytes)")
        let image = try XCTUnwrap(MatteSet.decode(data))
        XCTAssertEqual(image.extent.size, CGSize(width: 512, height: 512))
        XCTAssertEqual(value(of: image, x: 256, y: 256), 255, "inside the box")
        XCTAssertEqual(value(of: image, x: 5, y: 5), 0, "outside the box")
    }

    func testEmptySegmentationMatteKeepsTheOriginalFrame() throws {
        let image = try XCTUnwrap(MatteSet.decode(try XCTUnwrap(MatteSet.encode(floatMask(boxFraction: 0)))))
        XCTAssertEqual(value(of: image, x: 256, y: 256), 255, "a frame with no detected subject must not become transparent black")
    }

    func testFramesPersistAndComeBackFromDisk() throws {
        let directory = temporaryDirectory()
        let set = MatteSet(directory: directory)
        let data = try XCTUnwrap(MatteSet.encode(floatMask()))
        set.store(index: 3, compressed: data)
        set.store(index: 4, compressed: data)
        XCTAssertEqual(set.missing(in: 2...5), [2, 5])
        let reopened = MatteSet(directory: directory)
        XCTAssertEqual(reopened.count, 0, "nothing is read until asked")
        reopened.loadFromDisk()
        XCTAssertEqual(reopened.missing(in: 2...5), [2, 5])
        XCTAssertNotNil(reopened.matte(atSourceSeconds: 3.0 / 30))
    }

    func testALookupFallsBackToANeighbourFrameOnly() throws {
        let set = MatteSet(directory: temporaryDirectory())
        set.store(index: 10, compressed: try XCTUnwrap(MatteSet.wholeFrameMatte()))
        XCTAssertNotNil(set.matte(atSourceSeconds: 10.0 / 30))
        XCTAssertNotNil(set.matte(atSourceSeconds: 11.0 / 30), "one frame away")
        XCTAssertNil(set.matte(atSourceSeconds: 14.0 / 30), "further away: no matte, the frame shows whole")
    }

    // MARK: The job (iPhone only)

    func testTheJobCutsRealFootageFromThePlayheadAndCanBeCancelled() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision finds nothing on the simulator (no Neural Engine); run this on the iPhone")
        #else
        let url = try XCTUnwrap(bundledURL(filename: "demo-nguoi1.MOV"), "copy public/preview/video/demo-nguoi1.MOV into the app's Documents/ImportedMedia")
        let set = MatteSet(directory: temporaryDirectory())
        let result = await VideoMatteJob.run(asset: url, set: set, range: 2.0...3.0, focus: 2.5, isCancelled: { false }, progress: { _, _ in })
        let wanted = MatteSet.index(forSourceSeconds: 2.0)...MatteSet.index(forSourceSeconds: 3.0)
        XCTAssertEqual(set.missing(in: wanted), [], "every frame of the stretch has a matte")
        XCTAssertEqual(result.frames, wanted.count)
        NSLog("VIDEOMATTE 1 s of footage: %d frames in %.2f s, per frame median %.0f ms", result.frames, result.seconds, result.visionMs.sorted()[result.visionMs.count / 2])
        // A selfie: the person is in the middle of the picture, the top corner is wall.
        let matte = try XCTUnwrap(set.matte(atSourceSeconds: 2.5))
        XCTAssertGreaterThan(value(of: matte, x: 256, y: 256), 200, "the subject is kept")
        // CIImage y grows upward: y 500 is the top of the upright picture (the wall behind the head); the bottom corners are the shoulders.
        XCTAssertLessThan(value(of: matte, x: 8, y: 500), 40, "the background is cut")

        // A second run on the same set has nothing left to do; a run cancelled at once does nothing.
        let again = await VideoMatteJob.run(asset: url, set: set, range: 2.0...3.0, focus: 2.0, isCancelled: { false }, progress: { _, _ in })
        XCTAssertEqual(again.frames, 0)
        let fresh = MatteSet(directory: temporaryDirectory())
        let stopped = await VideoMatteJob.run(asset: url, set: fresh, range: 4.0...5.0, focus: 4.0, isCancelled: { true }, progress: { _, _ in })
        XCTAssertEqual(stopped.frames, 0)
        XCTAssertTrue(stopped.cancelled)
        #endif
    }

    /// The UI test's flow without the UI: start the job, cancel it, start it again and let it finish (iPhone only).
    @MainActor
    func testCancelThenRestartCarriesOnAndFinishes() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision finds nothing on the simulator; run this on the iPhone")
        #else
        let uri = "demo-nguoi2.MOV"
        _ = try XCTUnwrap(bundledURL(filename: uri))
        let set = VideoMatteStore.shared.set(forAssetURI: uri)
        try? FileManager.default.removeItem(at: set.directory)
        let jobs = SegmentationJobs.shared
        let range = 0.0...6.0
        jobs.ensure(layerId: "restart-test", assetURI: uri, range: range, focus: 0)
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertNotNil(jobs.running["restart-test"])
        jobs.cancel("restart-test")
        XCTAssertNil(jobs.running["restart-test"])
        jobs.ensure(layerId: "restart-test", assetURI: uri, range: range, focus: 3)
        var waited = 0.0
        while jobs.running["restart-test"] != nil, waited < 60 { try await Task.sleep(for: .milliseconds(200)); waited += 0.2 }
        XCTAssertNil(jobs.running["restart-test"], "the restarted job finished")
        let wanted = MatteSet.index(forSourceSeconds: 0)...MatteSet.index(forSourceSeconds: 6)
        XCTAssertEqual(set.missing(in: wanted).count, 0, "every frame has a matte after the restart")
        try? FileManager.default.removeItem(at: set.directory)
        #endif
    }

    /// The whole 21 s selfie (about 630 frames) through the job: the app's memory must stay flat (a real run was lost on the iPhone mid-job). iPhone only.
    func testAWholeClipDoesNotGrowTheMemoryFootprint() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision finds nothing on the simulator; run this on the iPhone")
        #else
        let url = try XCTUnwrap(bundledURL(filename: "demo-nguoi1.MOV"))
        let set = MatteSet(directory: temporaryDirectory())
        let result = await VideoMatteJob.run(asset: url, set: set, range: 0.0...21.0, focus: 0, isCancelled: { false }, progress: { _, _ in })
        NSLog("VIDEOMATTE whole clip: %d frames in %.1f s; footprint %.0f MB at start, peak %.0f MB", result.frames, result.seconds, result.startFootprintMB, result.peakFootprintMB)
        XCTAssertGreaterThan(result.frames, 600)
        XCTAssertLessThan(result.peakFootprintMB - result.startFootprintMB, 400, "memory grew while the job ran")
        #endif
    }
}
