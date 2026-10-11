import Compression
import Foundation

enum ZipError: LocalizedError {
    case notAZip
    case unsupported(String)
    case unsafePath(String)
    case tooLarge
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .notAZip: return "Not a zip file"
        case .unsupported(let what): return "Unsupported zip feature: \(what)"
        case .unsafePath(let path): return "Unsafe path in zip: \(path)"
        case .tooLarge: return "Zip is too large"
        case .corrupt(let what): return "Corrupt zip: \(what)"
        }
    }
}

/// Minimal zip extractor (stored + deflate, no zip64, no encryption) built on the Compression framework,
/// so template packages unpack without a third-party dependency. Hostile input is expected: names that
/// escape the target folder, oversized entries and truncated files are rejected.
struct ZipReader {
    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    static let maxEntries = 5_000
    static let maxTotalBytes = 512 * 1024 * 1024

    private let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        guard let eocd = Self.findEndOfCentralDirectory(in: data) else { throw ZipError.notAZip }
        let count = Int(data.u16(eocd + 10))
        let size = Int(data.u32(eocd + 12))
        let offset = Int(data.u32(eocd + 16))
        guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else { throw ZipError.unsupported("zip64") }
        guard count <= Self.maxEntries else { throw ZipError.tooLarge }
        guard offset >= 0, offset + size <= data.count else { throw ZipError.corrupt("central directory out of range") }

        var entries: [Entry] = []
        var cursor = offset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data.u32(cursor) == 0x0201_4B50 else { throw ZipError.corrupt("bad central directory entry") }
            let flags = data.u16(cursor + 8)
            let method = Int(data.u16(cursor + 10))
            let compressed = Int(data.u32(cursor + 20))
            let uncompressed = Int(data.u32(cursor + 24))
            let nameLength = Int(data.u16(cursor + 28))
            let extraLength = Int(data.u16(cursor + 30))
            let commentLength = Int(data.u16(cursor + 32))
            let localOffset = Int(data.u32(cursor + 42))
            guard flags & 1 == 0 else { throw ZipError.unsupported("encryption") }
            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF else { throw ZipError.unsupported("zip64") }
            guard cursor + 46 + nameLength <= data.count else { throw ZipError.corrupt("name out of range") }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let name = String(data: nameData, encoding: .utf8) else { throw ZipError.corrupt("name is not UTF-8") }
            entries.append(Entry(name: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard entries.reduce(0, { $0 + $1.uncompressedSize }) <= Self.maxTotalBytes else { throw ZipError.tooLarge }
        self.entries = entries
    }

    /// Unpacks every entry under `directory`.
    func extract(to directory: URL) throws {
        let root = directory.standardizedFileURL
        for entry in entries {
            let target = try Self.safeTarget(for: entry.name, in: root)
            if entry.isDirectory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            let bytes = try contents(of: entry)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target)
        }
    }

    func contents(of entry: Entry) throws -> Data {
        let header = entry.localHeaderOffset
        guard header >= 0, header + 30 <= data.count, data.u32(header) == 0x0403_4B50 else { throw ZipError.corrupt("bad local header for \(entry.name)") }
        let start = header + 30 + Int(data.u16(header + 26)) + Int(data.u16(header + 28))
        guard start >= 0, start + entry.compressedSize <= data.count else { throw ZipError.corrupt("data out of range for \(entry.name)") }
        let payload = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0:
            guard payload.count == entry.uncompressedSize else { throw ZipError.corrupt("size mismatch for \(entry.name)") }
            return payload
        case 8:
            if entry.uncompressedSize == 0 { return Data() }
            var output = Data(count: entry.uncompressedSize)
            let written = output.withUnsafeMutableBytes { out in
                payload.withUnsafeBytes { input in
                    compression_decode_buffer(
                        out.bindMemory(to: UInt8.self).baseAddress!, entry.uncompressedSize,
                        input.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == entry.uncompressedSize else { throw ZipError.corrupt("inflate failed for \(entry.name)") }
            return output
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    /// Rejects absolute paths, backslashes and `..` so an entry can never land outside `root`.
    static func safeTarget(for name: String, in root: URL) throws -> URL {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
              !name.split(separator: "/").contains("..") else { throw ZipError.unsafePath(name) }
        let target = root.appendingPathComponent(name).standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else { throw ZipError.unsafePath(name) }
        return target
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var index = data.count - 22
        while index >= lowest {
            if data.u32(index) == 0x0605_4B50 { return index }
            index -= 1
        }
        return nil
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }
}
