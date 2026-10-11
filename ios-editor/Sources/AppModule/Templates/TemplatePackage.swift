import Foundation

enum TemplatePackageError: LocalizedError {
    case missingFile(String)
    case unsupportedFormat(Int)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name): return "Template is missing \(name)"
        case .unsupportedFormat: return "This template needs a newer version of the app"
        case .invalid(let reason): return "Invalid template: \(reason)"
        }
    }
}

/// An unpacked, validated template: its slots plus the document they point into.
struct TemplatePackage {
    let manifest: TemplateManifest
    let document: EditorDocument
    /// Folder the package was unpacked into; `assets/…` URIs resolve against it.
    let directory: URL
}

enum TemplatePackageLoader {
    /// Highest `manifest.formatVersion` this build understands.
    static let supportedFormatVersion = 2

    static func load(directory: URL) throws -> TemplatePackage {
        let decoder = JSONDecoder()
        let manifest = try decode(TemplateManifest.self, "manifest.json", in: directory, decoder)
        guard manifest.formatVersion <= supportedFormatVersion else {
            throw TemplatePackageError.unsupportedFormat(manifest.formatVersion)
        }
        let document = try decode(EditorDocument.self, "document.json", in: directory, decoder)
        try validate(manifest: manifest, document: document, directory: directory)
        return TemplatePackage(manifest: manifest, document: document, directory: directory)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ name: String, in directory: URL, _ decoder: JSONDecoder) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { throw TemplatePackageError.missingFile(name) }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw TemplatePackageError.invalid("\(name): \(error.localizedDescription)") }
    }

    /// Slots must point at real layers of a matching kind, no asset may reach outside the package or the network,
    /// every `assets/…` file must exist, and the audio must reference audio assets that exist.
    /// `directory` is nil when only the documents are being checked.
    static func validate(manifest: TemplateManifest, document: EditorDocument, directory: URL? = nil) throws {
        var seenSlots = Set<String>()
        for slot in manifest.slots {
            guard seenSlots.insert(slot.id).inserted else { throw TemplatePackageError.invalid("duplicate slot \(slot.id)") }
            guard let layer = document.layers.first(where: { $0.id == slot.layerId }) else {
                throw TemplatePackageError.invalid("slot \(slot.id) points at missing layer \(slot.layerId)")
            }
            switch slot.kind {
            case "media":
                guard layer.kind == "image" || layer.kind == "video" else {
                    throw TemplatePackageError.invalid("media slot \(slot.id) needs an image or video layer, not \(layer.kind)")
                }
                guard let duration = slot.durationMs, duration > 0 else {
                    throw TemplatePackageError.invalid("media slot \(slot.id) needs a durationMs")
                }
            case "text":
                guard layer.kind == "text" else { throw TemplatePackageError.invalid("text slot \(slot.id) points at a \(layer.kind) layer") }
            default:
                throw TemplatePackageError.invalid("slot \(slot.id) has unknown kind \(slot.kind)")
            }
        }
        for asset in document.assets {
            guard isSafeAssetURI(asset.uri) else { throw TemplatePackageError.invalid("unsafe asset path \(asset.uri)") }
            if let directory, asset.uri.hasPrefix("assets/"),
               !FileManager.default.fileExists(atPath: directory.appendingPathComponent(asset.uri).path) {
                throw TemplatePackageError.missingFile(asset.uri)
            }
        }
        let audioAssetIds = Set(document.assets.compactMap { asset -> String? in asset.kind == "audio" ? asset.id : nil })
        for clip in (document.audio?.tracks ?? []).flatMap(\.clips) where !audioAssetIds.contains(clip.assetId) {
            throw TemplatePackageError.invalid("audio clip \(clip.id) uses unknown audio asset \(clip.assetId)")
        }
    }

    /// A bare bundled filename or a relative path inside the package: no scheme, no absolute path, no "..".
    static func isSafeAssetURI(_ uri: String) -> Bool {
        guard !uri.isEmpty, !uri.contains("://"), !uri.hasPrefix("/"), !uri.contains("\\") else { return false }
        return !uri.split(separator: "/").contains("..")
    }
}

enum TemplateInstaller {
    static var rootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Templates", isDirectory: true)
    }

    /// Unpacks a downloaded zip into `Templates/{templateId}/v{version}/` (replacing any earlier copy), validates it,
    /// and makes its `assets/…` files (music, stickers) resolvable like any other media: they are copied into the
    /// app's media folder under a unique name and the document's asset paths are rewritten to that name.
    static func install(
        zip: Data, templateId: String, version: Int,
        root: URL = rootDirectory, mediaDirectory: URL = MediaImportService.importedMediaDirectory
    ) throws -> TemplatePackage {
        let directory = root.appendingPathComponent(templateId, isDirectory: true).appendingPathComponent("v\(version)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try ZipReader(data: zip).extract(to: directory)
            let package = try TemplatePackageLoader.load(directory: directory)
            return try relocatingAssets(of: package, templateId: templateId, version: version, into: mediaDirectory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func relocatingAssets(of package: TemplatePackage, templateId: String, version: Int, into mediaDirectory: URL) throws -> TemplatePackage {
        var document = package.document
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        document.assets = try document.assets.map { asset in
            guard asset.uri.hasPrefix("assets/") else { return asset }
            let name = "tpl-\(templateId.prefix(8))-v\(version)-" + asset.uri.dropFirst("assets/".count).replacingOccurrences(of: "/", with: "_")
            let destination = mediaDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: package.directory.appendingPathComponent(asset.uri), to: destination)
            return asset.withURI(name)
        }
        return TemplatePackage(manifest: package.manifest, document: document, directory: package.directory)
    }
}

extension V2Asset {
    func withURI(_ uri: String) -> V2Asset {
        switch self {
        case .image(var a): a.uri = uri; return .image(a)
        case .video(var a): a.uri = uri; return .video(a)
        case .audio(var a): a.uri = uri; return .audio(a)
        case .font(var a): a.uri = uri; return .font(a)
        case .lut(var a): a.uri = uri; return .lut(a)
        }
    }
}
