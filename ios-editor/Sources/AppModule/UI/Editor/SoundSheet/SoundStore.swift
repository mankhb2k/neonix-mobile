import AVFoundation
import Foundation
import Observation

/// The sound-effect library on the device: the catalogue from the API (kept on disk so the list still opens offline), the files
/// (downloaded once into Caches - listening to a sound downloads it, so Use never waits), and the copy a used sound gets in
/// `ImportedMedia` so a project can reference it like any imported audio.
@MainActor
@Observable
final class SoundStore {
    enum State: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: State = .idle
    private(set) var catalogue: APISoundCatalogue?
    /// Ids whose file is already on the phone (the list shows a cloud badge on the others).
    private(set) var downloadedIds: Set<String> = []

    @ObservationIgnored var client: NeonixAPIClient
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private var inFlight: [String: Task<URL?, Never>] = [:]

    /// Cheap on purpose: the shell creates one as a `@State` default, which runs on every re-init of the shell. The disk work waits for `bootstrap()`.
    init(client: NeonixAPIClient = NeonixAPIClient(config: .current), session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.client = client
        self.session = session
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds", isDirectory: true)
    }

    @ObservationIgnored private var bootstrapped = false
    #if DEBUG
    @ObservationIgnored private nonisolated(unsafe) static var fixtureCacheWiped = false
    #endif

    /// First use: the cache folder, the catalogue kept from last time (so the list opens offline) and which files are already here.
    private func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        #if DEBUG
        // UI tests: no server needed, the catalogue and files come from a folder on the Mac (`public/preview/sounds`), with an empty cache (once per launch).
        if Self.fixtureDirectory != nil, !Self.fixtureCacheWiped { try? FileManager.default.removeItem(at: cacheDirectory); Self.fixtureCacheWiped = true }
        #endif
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if catalogue == nil { catalogue = loadCachedCatalogue() }
        if catalogue != nil, state == .idle { state = .loaded }
        refreshDownloaded()
    }

    // MARK: Catalogue

    /// Fetches the catalogue (always, so the file URLs are fresh); a cached copy keeps the list usable if that fails.
    func load() async {
        bootstrap()
        if catalogue == nil { state = .loading }
        do {
            #if DEBUG
            let fresh: APISoundCatalogue
            if let fixture = Self.fixtureDirectory { fresh = try Self.fixtureCatalogue(fixture) } else { fresh = try await client.sounds() }
            #else
            let fresh = try await client.sounds()
            #endif
            catalogue = fresh
            state = .loaded
            if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: catalogueFile, options: .atomic) }
            refreshDownloaded()
        } catch {
            state = catalogue == nil ? .failed((error as? APIError).map { "\($0)" } ?? error.localizedDescription) : .loaded
        }
    }

    private var catalogueFile: URL { cacheDirectory.appendingPathComponent("catalogue.json") }

    private func loadCachedCatalogue() -> APISoundCatalogue? {
        guard let data = try? Data(contentsOf: catalogueFile) else { return nil }
        return try? JSONDecoder().decode(APISoundCatalogue.self, from: data)
    }

    // MARK: Files

    private func diskFile(for sound: APISoundCatalogue.Sound) -> URL { cacheDirectory.appendingPathComponent("\(sound.id).m4a") }

    private func refreshDownloaded() {
        downloadedIds = Set((catalogue?.sounds ?? []).filter { FileManager.default.fileExists(atPath: diskFile(for: $0).path) }.map(\.id))
    }

    func isDownloaded(_ sound: APISoundCatalogue.Sound) -> Bool { downloadedIds.contains(sound.id) }

    /// The sound's local file: from the cache, otherwise downloaded first (one request per sound at a time). nil when it could not be fetched.
    func localURL(for sound: APISoundCatalogue.Sound) async -> URL? {
        bootstrap()
        let file = diskFile(for: sound)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if let running = inFlight[sound.id] { return await running.value }
        let session = session
        let url = sound.url
        let task = Task<URL?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  !data.isEmpty
            else { return nil }
            try? data.write(to: file, options: .atomic)
            guard (try? AVAudioFile(forReading: file)) != nil else { try? FileManager.default.removeItem(at: file); return nil }
            return file
        }
        inFlight[sound.id] = task
        let result = await task.value
        inFlight[sound.id] = nil
        if result != nil { downloadedIds.insert(sound.id) }
        return result
    }

    // MARK: Use in a project

    static func assetId(for sound: APISoundCatalogue.Sound) -> String { "\(soundAssetIdPrefix)\(sound.id)" }

    /// Makes sure the file is in `ImportedMedia` (where project assets are resolved from) and returns its asset.
    func importAsset(for sound: APISoundCatalogue.Sound) async throws -> V2AudioAsset {
        let filename = "\(Self.assetId(for: sound)).m4a"
        let destination = MediaImportService.importedMediaDirectory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: destination.path) {
            guard let source = await localURL(for: sound) else { throw APIError.invalidResponse }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return V2AudioAsset(id: Self.assetId(for: sound), uri: filename, mimeType: sound.mimeType, duration: sound.durationMs, sampleRate: nil, channels: nil, integrity: nil)
    }

    #if DEBUG
    static var fixtureDirectory: URL? {
        ProcessInfo.processInfo.environment["SOUNDS_FIXTURE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// `sounds.json` as `scripts/generate_sfx.py` writes it, turned into a catalogue whose URLs are local files.
    private static func fixtureCatalogue(_ directory: URL) throws -> APISoundCatalogue {
        struct Local: Decodable {
            struct Sound: Decodable { let id: String, name: String, category: String, file: String, durationMs: Double, peaks: [Double] }
            struct Category: Decodable { let id: String, title: String }
            let categories: [Category]
            let sounds: [Sound]
        }
        let local = try JSONDecoder().decode(Local.self, from: Data(contentsOf: directory.appendingPathComponent("sounds.json")))
        return APISoundCatalogue(
            categories: local.categories.map { .init(id: $0.id, title: $0.title) },
            sounds: local.sounds.map {
                .init(id: $0.id, name: $0.name, category: $0.category,
                      url: directory.appendingPathComponent($0.file.replacingOccurrences(of: "sounds/", with: "")),
                      durationMs: $0.durationMs, mimeType: "audio/mp4", peaks: $0.peaks)
            }
        )
    }
    #endif
}
