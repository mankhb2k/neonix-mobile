import CoreImage
import ImageIO

/// A video track's `preferredTransform` as an EXIF-style orientation, applied to a `CIImage`. `CIImage` has its origin bottom-left, `preferredTransform` assumes top-left,
/// so applying the matrix to a CIImage directly turns a portrait iPhone clip 180 degrees the wrong way up (seen on the filtered / Remove BG video path).
enum VideoOrientation {
    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): return .right    // portrait, home button down (the usual iPhone clip)
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }

    /// `image` turned upright, its extent starting at the origin again.
    static func upright(_ image: CIImage, transform: CGAffineTransform) -> CIImage {
        let turned = image.oriented(orientation(for: transform))
        return turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
    }
}
