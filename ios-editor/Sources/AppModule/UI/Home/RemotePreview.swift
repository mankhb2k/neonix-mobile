import AVFoundation
import SwiftUI
import UIKit

/// A template's preview: an image, or a still frame of a preview video. Loaded in `.task`, never inline
/// from `body` (CLAUDE.md, "Rendering notes"); the gradient shows while it loads or if it fails.
struct RemotePreview: View {
    let url: URL?
    var gradient: [Color] = [.gray, .black]

    @State private var image: UIImage?

    var body: some View {
        // The picture is an overlay so its own size never decides the layout: the gradient takes whatever
        // space the parent offers and the image is cropped to it.
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) { image = await RemotePreviewLoader.shared.image(for: url) }
    }
}

actor RemotePreviewLoader {
    static let shared = RemotePreviewLoader()
    private var cache: [URL: UIImage] = [:]

    func image(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = cache[url] { return cached }
        let loaded = url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov"
            ? await videoFrame(url) : await downloadImage(url)
        if let loaded { cache[url] = loaded }
        return loaded
    }

    private func downloadImage(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    /// A frame about a second in (the very first frame is often black).
    private func videoFrame(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 900)
        guard let cgImage = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
