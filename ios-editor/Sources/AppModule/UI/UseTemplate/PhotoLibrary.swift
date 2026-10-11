import AVFoundation
import Observation
import Photos
import UIKit

/// Photos access for the slot picker: authorization, the asset list (All / Videos / Photos) and thumbnails.
@MainActor
@Observable
final class PhotoLibrary {
    enum Access { case unknown, denied, ready }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", videos = "Videos", photos = "Photos"
        var id: String { rawValue }
    }

    private(set) var access: Access = .unknown
    private(set) var result: PHFetchResult<PHAsset>?
    var filter: Filter = .all { didSet { if filter != oldValue { fetch() } } }

    private let imageManager = PHCachingImageManager()

    var count: Int { result?.count ?? 0 }

    func asset(at index: Int) -> PHAsset? {
        guard let result, index < result.count else { return nil }
        return result.object(at: index)
    }

    func requestAccess() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        switch status {
        case .authorized, .limited:
            access = .ready
            fetch()
        default:
            access = .denied
        }
    }

    private func fetch() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch filter {
        case .all: options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        case .videos: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        case .photos: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }
        result = PHAsset.fetchAssets(with: options)
    }

    func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var resumed = false
            imageManager.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// Streams a video straight from the library (no copy) for the crop preview.
    func avAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: avAsset)
            }
        }
    }
}

/// Copies the chosen library item into the app's media folder (like every other imported media) and describes it as a
/// Protocol V2 asset.
enum PhotoImporter {
    enum ImportError: LocalizedError {
        case noResource
        var errorDescription: String? { "Couldn't read that photo or video" }
    }

    static func importMedia(_ asset: PHAsset, kind: MediaKind, assetId: String) async throws -> V2Asset {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = kind == .video ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        guard let resource = preferred.compactMap({ type in resources.first { $0.type == type } }).first else { throw ImportError.noResource }

        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        let name = "pick-\(UUID().uuidString.prefix(8)).\(ext.isEmpty ? (kind == .video ? "mov" : "jpg") : ext)"
        let destination = MediaImportService.importedMediaDirectory.appendingPathComponent(name)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)

        switch kind {
        case .photo:
            return .image(V2ImageAsset(id: assetId, uri: name, width: Double(asset.pixelWidth), height: Double(asset.pixelHeight)))
        case .video:
            let avAsset = AVURLAsset(url: destination)
            let duration = try await avAsset.load(.duration).seconds * 1000
            var width = Double(asset.pixelWidth), height = Double(asset.pixelHeight)
            if let track = try await avAsset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
                width = abs(size.width); height = abs(size.height)
            }
            return .video(V2VideoAsset(id: assetId, uri: name, width: width, height: height, duration: duration))
        }
    }
}
