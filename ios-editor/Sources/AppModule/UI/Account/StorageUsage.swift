import Foundation

/// What the app keeps on the phone, split the way Account › Storage shows it. Only the app's own sandbox can be
/// measured or cleared (iOS shows nothing of other apps).
struct StorageLocations {
    var documents: URL
    var library: URL
    var tmp: URL
    /// Imported media: the user's content, never cleared from here.
    var media: URL
    /// Unpacked template packages: downloaded again whenever a template is opened.
    var templates: URL
    /// `Library/Caches`: everything in it is rebuilt on demand.
    var caches: URL

    static var app: StorageLocations {
        let fm = FileManager.default
        return StorageLocations(
            documents: fm.urls(for: .documentDirectory, in: .userDomainMask)[0],
            library: fm.urls(for: .libraryDirectory, in: .userDomainMask)[0],
            tmp: fm.temporaryDirectory,
            media: MediaImportService.importedMediaDirectory,
            templates: TemplateInstaller.rootDirectory,
            caches: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        )
    }
}

struct StorageSnapshot: Equatable {
    var total: Int64
    var media: Int64
    var templates: Int64
    var cache: Int64
    /// Whatever else the app keeps (preferences, debug logs…).
    var other: Int64 { max(total - media - templates - cache, 0) }
    /// Free space on the whole phone, as iOS would let this app use it.
    var deviceFree: Int64?
}

enum StorageUsage {
    /// Disk space the folder takes (allocated blocks, like iPhone Storage counts), 0 if it doesn't exist.
    static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func measure(_ locations: StorageLocations = .app) -> StorageSnapshot {
        let cache = size(of: locations.caches) + size(of: locations.tmp)
        let total = size(of: locations.documents) + size(of: locations.library) + size(of: locations.tmp)
        let free = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        return StorageSnapshot(total: total, media: size(of: locations.media), templates: size(of: locations.templates), cache: cache, deviceFree: free)
    }

    /// Empties `Caches` and `tmp`. Folders directly inside `Caches` stay (empty): a store that made its folder at
    /// launch (stickers, waveforms) would otherwise fail to write until the next launch.
    static func clearCache(_ locations: StorageLocations = .app) {
        emptyKeepingFolders(locations.caches)
        removeChildren(of: locations.tmp)
    }

    /// Removes the unpacked template packages. Owned templates stay owned; opening one downloads it again.
    static func removeDownloadedTemplates(_ locations: StorageLocations = .app) {
        removeChildren(of: locations.templates)
    }

    private static func emptyKeepingFolders(_ directory: URL) {
        let fm = FileManager.default
        for child in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                removeChildren(of: child)
            } else {
                try? fm.removeItem(at: child)
            }
        }
    }

    private static func removeChildren(of directory: URL) {
        let fm = FileManager.default
        for child in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: child)
        }
    }
}
