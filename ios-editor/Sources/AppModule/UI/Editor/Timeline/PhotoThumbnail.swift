import ImageIO
import UIKit

/// The little square pictures a photo clip shows on the timeline (like the video filmstrip, but one picture repeated): cut from the file with
/// ImageIO at the size they are drawn (never the full photo), off the main thread, once per file and size.
enum PhotoThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    /// A square, centre-cropped `side` x `side` pt picture (at the screen's scale), or nil if the file cannot be read.
    static func tile(for url: URL, side: CGFloat) async -> UIImage? {
        let scale = await MainActor.run { UIScreen.main.scale }
        let key = "\(url.path)|\(Int(side * scale))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image: UIImage? = await Task.detached(priority: .utility) {
            let pixels = Int((side * scale).rounded())
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels * 3,
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            // Centre-crop to a square, then scale to the tile.
            let side = min(thumb.width, thumb.height)
            let crop = CGRect(x: (thumb.width - side) / 2, y: (thumb.height - side) / 2, width: side, height: side)
            guard let square = thumb.cropping(to: crop),
                  let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.interpolationQuality = .medium
            context.draw(square, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            return context.makeImage().map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
