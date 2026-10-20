import Accelerate
import CoreImage
import Foundation

/// The subject masks (mattes) of one video, one per frame on a fixed 30 fps grid of the *source* time, for Remove BG on video (CLAUDE.md "Remove BG"). A matte is Vision's
/// own 512 x 512 soft mask as 8-bit grey, LZFSE-compressed (a mostly flat picture: a few KB), kept in memory and one file per frame under `Caches/SegmentationMattes/<set>/`,
/// so a cancelled job keeps what it did and a later one only fills the gaps. Derived data: deleting the folder only costs a recompute. The folder name ends in the matte
/// format (`auto4` = upright frames with no-subject frames preserving the source; earlier formats held wrongly turned clips, early frames or transparent no-subject mattes).
final class MatteSet: @unchecked Sendable {
    static let fps = 30.0
    static let side = 512

    let directory: URL
    private let lock = NSLock()
    private var frames: [Int: Data] = [:]
    private var decodedIndex = -1
    private var decoded: CIImage?

    init(directory: URL) { self.directory = directory }

    static func index(forSourceSeconds seconds: Double) -> Int { Int((max(seconds, 0) * fps).rounded()) }

    var count: Int { lock.withLock { frames.count } }

    func has(_ index: Int) -> Bool { lock.withLock { frames[index] != nil } }

    func compressed(_ index: Int) -> Data? { lock.withLock { frames[index] }}

    /// Reads the frames already on disk into memory (call off the main thread).
    func loadFromDisk() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(".m") {
            guard let index = Int(name.dropLast(2)), let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { continue }
            lock.withLock { frames[index] = data }
        }
    }

    func store(index: Int, compressed: Data) {
        lock.withLock { frames[index] = compressed }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? compressed.write(to: directory.appendingPathComponent("\(index).m"))
    }

    /// Frames of `range` that have no matte yet.
    func missing(in range: ClosedRange<Int>) -> [Int] { lock.withLock { range.filter { frames[$0] == nil } } }

    /// The matte for the frame nearest `seconds` (the frame itself, else a neighbour one step away), nil when neither is there. Decoded once per frame and kept.
    func matte(atSourceSeconds seconds: Double) -> CIImage? {
        let index = Self.index(forSourceSeconds: seconds)
        return lock.withLock {
            if index == decodedIndex, let decoded { return decoded }
            for candidate in [index, index - 1, index + 1] {
                guard let data = frames[candidate] else { continue }
                let image = Self.decode(data)
                if candidate == index { decodedIndex = index; decoded = image }
                return image
            }
            return nil
        }
    }

    // MARK: Codec

    /// Vision's soft mask (OneComponent32Float, 512 x 512) -> 8-bit grey -> LZFSE.
    static func encode(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width == side, height == side, CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var source = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        var grey = Data(count: width * height)
        let status: vImage_Error = grey.withUnsafeMutableBytes { bytes in
            var destination = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
            return vImageConvert_PlanarFtoPlanar8(&source, &destination, 1, 0, vImage_Flags(kvImageNoFlags))
        }
        guard status == kvImageNoError else { return nil }
        if !grey.contains(where: { $0 > 0 }) { return wholeFrameMatte() }
        return try? (grey as NSData).compressed(using: .lzfse) as Data
    }

    /// A full-foreground matte keeps the source frame visible when Vision cannot find a subject.
    static func wholeFrameMatte() -> Data? { try? (Data(repeating: 255, count: side * side) as NSData).compressed(using: .lzfse) as Data }

    static func decode(_ compressed: Data) -> CIImage? {
        guard let grey = try? (compressed as NSData).decompressed(using: .lzfse) as Data, grey.count == side * side else { return nil }
        return CIImage(bitmapData: grey, bytesPerRow: side, size: CGSize(width: side, height: side), format: .L8, colorSpace: nil)
    }
}

/// The mattes of every video that has Remove BG, by source file.
@MainActor
final class VideoMatteStore {
    static let shared = VideoMatteStore()
    private var sets: [String: MatteSet] = [:]

    init() {
        #if DEBUG
        // UI tests: `REMOVEBG_CLEAR_MATTES=1` starts from an empty cache, so the job really runs.
        if ProcessInfo.processInfo.environment["REMOVEBG_CLEAR_MATTES"] != nil { try? FileManager.default.removeItem(at: Self.root) }
        #endif
    }

    static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SegmentationMattes", isDirectory: true)
    }

    /// The set of one video file (made on first ask; no disk work here). The folder name carries the file's size, so a replaced file does not reuse old mattes.
    func set(forAssetURI uri: String) -> MatteSet {
        if let known = sets[uri] { return known }
        let size = (bundledURL(filename: uri)).flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? 0
        let safe = uri.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        let set = MatteSet(directory: Self.root.appendingPathComponent("\(safe)-\(size)-auto4", isDirectory: true))
        sets[uri] = set
        return set
    }
}
