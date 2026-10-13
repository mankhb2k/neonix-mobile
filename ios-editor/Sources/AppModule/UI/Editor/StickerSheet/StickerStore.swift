import Foundation
import Observation
import UIKit

/// The sticker library on the device: the catalogue from the API (kept on disk so the grid still opens offline), the
/// pictures (downloaded once, kept in Caches), and the file a picked sticker is copied to so a project can use it
/// (`ImportedMedia`, like every other imported asset).
@MainActor
@Observable
final class StickerStore {
    enum State: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: State = .idle
    private(set) var catalogue: APIStickerCatalogue?

    @ObservationIgnored var client: NeonixAPIClient
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let memory = NSCache<NSString, UIImage>()
    @ObservationIgnored private var inFlight: [String: Task<Data?, Never>] = [:]

    init(client: NeonixAPIClient = NeonixAPIClient(config: .current), session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.client = client
        self.session = session
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Stickers", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        catalogue = loadCachedCatalogue()
        if catalogue != nil { state = .loaded }
    }

    // MARK: Catalogue

    /// Fetches the catalogue (always, so the picture URLs are fresh); a cached copy keeps the grid usable if that fails.
    func load() async {
        if catalogue == nil { state = .loading }
        do {
            let fresh = try await client.stickers()
            catalogue = fresh
            state = .loaded
            saveCatalogue(fresh)
        } catch {
            state = catalogue == nil ? .failed(Self.message(for: error)) : .loaded
        }
    }

    private var catalogueFile: URL { cacheDirectory.appendingPathComponent("catalogue.json") }

    private func loadCachedCatalogue() -> APIStickerCatalogue? {
        guard let data = try? Data(contentsOf: catalogueFile) else { return nil }
        return try? NeonixAPIClient.decoder.decode(APIStickerCatalogue.self, from: data)
    }

    private func saveCatalogue(_ value: APIStickerCatalogue) {
        guard let data = try? JSONEncoder().encode(CatalogueBox(value)) else { return }
        try? data.write(to: catalogueFile, options: .atomic)
    }

    /// `APIStickerCatalogue` only decodes; this writes the same JSON shape back for the disk copy.
    private struct CatalogueBox: Encodable {
        let value: APIStickerCatalogue
        init(_ value: APIStickerCatalogue) { self.value = value }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(["name": value.license.name, "holder": value.license.holder, "source": value.license.source, "file": value.license.file], forKey: .license)
            try c.encode(value.categories.map { ["id": $0.id, "title": $0.title] }, forKey: .categories)
            try c.encode(value.stickers.map { StickerBox($0) }, forKey: .stickers)
        }
        enum Keys: String, CodingKey { case license, categories, stickers }
        struct StickerBox: Encodable {
            let id: String, name: String, category: String, url: String, width: Double, height: Double
            init(_ s: APIStickerCatalogue.Sticker) { id = s.id; name = s.name; category = s.category; url = s.url.absoluteString; width = s.width; height = s.height }
        }
    }

    // MARK: Pictures

    func image(for sticker: APIStickerCatalogue.Sticker) async -> UIImage? {
        if let hit = memory.object(forKey: sticker.id as NSString) { return hit }
        guard let data = await data(for: sticker), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: sticker.id as NSString)
        return image
    }

    private func diskFile(for sticker: APIStickerCatalogue.Sticker) -> URL { cacheDirectory.appendingPathComponent("\(sticker.id).png") }

    /// The picture's bytes: from disk if downloaded before, otherwise downloaded (one request per sticker at a time).
    private func data(for sticker: APIStickerCatalogue.Sticker) async -> Data? {
        if let cached = try? Data(contentsOf: diskFile(for: sticker)) { return cached }
        if let running = inFlight[sticker.id] { return await running.value }
        let file = diskFile(for: sticker)
        let session = session
        let task = Task<Data?, Never> {
            guard let (data, response) = try? await session.data(from: sticker.url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  UIImage(data: data) != nil
            else { return nil }
            try? data.write(to: file, options: .atomic)
            return data
        }
        inFlight[sticker.id] = task
        let result = await task.value
        inFlight[sticker.id] = nil
        return result
    }

    // MARK: Use in a project

    static func assetId(for sticker: APIStickerCatalogue.Sticker) -> String { "\(stickerAssetIdPrefix)\(sticker.id)" }

    /// Makes sure the picture is in `ImportedMedia` (where project assets are resolved from) and returns its asset.
    func importAsset(for sticker: APIStickerCatalogue.Sticker) async throws -> V2ImageAsset {
        let filename = "\(Self.assetId(for: sticker)).png"
        let destination = MediaImportService.importedMediaDirectory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: destination.path) {
            guard let data = await data(for: sticker) else { throw APIError.invalidResponse }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return V2ImageAsset(id: Self.assetId(for: sticker), uri: filename, mimeType: "image/png", width: sticker.width, height: sticker.height, integrity: nil)
    }

    private static func message(for error: Error) -> String {
        (error as? APIError).map { "\($0)" } ?? error.localizedDescription
    }
}
