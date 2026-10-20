import CoreImage
import Observation
import Vision

/// Remove BG's engine: Vision finds the subject, Core Image turns the matte into a cut-out picture. The matte is **derived data** - never stored in the project, kept
/// in memory (`SegmentationStore`) and computed again when missing. Photo only so far (a video needs a matte per frame - the planned second step).
enum SegmentationService {
    /// A subject mask as a Core Image image the size of the picture (white = keep), or nil when Vision found nothing (or cannot run here).
    /// `mode`: "auto" (every foreground instance), "point" (the instance under `at`, fractions of the picture, top-left origin; falls back to auto when the point is on
    /// the background), "people" (every person).
    static func matte(for image: CGImage, mode: String, at: CGPoint?) -> CIImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let handler = VNImageRequestHandler(cgImage: image)
        if mode == "people" {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            guard (try? handler.perform([request])) != nil, let buffer = request.results?.first?.pixelBuffer else { return nil }
            return scaled(CIImage(cvPixelBuffer: buffer), to: extent)
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        var instances = observation.allInstances
        if mode == "point", let at, let label = instance(at: at, in: observation.instanceMask), instances.contains(label) { instances = IndexSet(integer: label) }
        if let buffer = try? observation.generateScaledMaskForImage(forInstances: instances, from: handler) { return scaled(CIImage(cvPixelBuffer: buffer), to: extent) }
        if let buffer = try? observation.generateMask(forInstances: instances) { return scaled(CIImage(cvPixelBuffer: buffer), to: extent) }
        return nil
    }

    /// The instance number (1...; 0 is the background) at a point of the picture, read out of Vision's label map.
    static func instance(at point: CGPoint, in labels: CVPixelBuffer) -> Int? {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(labels) == kCVPixelFormatType_OneComponent8, let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let width = CVPixelBufferGetWidth(labels), height = CVPixelBufferGetHeight(labels), stride = CVPixelBufferGetBytesPerRow(labels)
        let x = min(max(Int(point.x * CGFloat(width)), 0), width - 1), y = min(max(Int(point.y * CGFloat(height)), 0), height - 1)
        let value = Int(base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)[x])
        return value == 0 ? nil : value
    }

    private static func scaled(_ matte: CIImage, to extent: CGRect) -> CIImage {
        guard matte.extent.width > 0, matte.extent.height > 0, matte.extent.size != extent.size else { return matte }
        return matte.transformed(by: CGAffineTransform(scaleX: extent.width / matte.extent.width, y: extent.height / matte.extent.height))
    }

    /// The picture with its background cut away: alpha = the matte, softened by `feather` px (a Gaussian sigma) and flipped by `invert`.
    static func cutout(of image: CGImage, matte: CIImage, feather: Double, invert: Bool, context: CIContext) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var mask = matte
        if invert { mask = mask.applyingFilter("CIColorInvert") }
        if feather > 0.01 { mask = mask.clampedToExtent().applyingGaussianBlur(sigma: feather).cropped(to: extent) }
        let clear = CIImage(color: .clear).cropped(to: extent)
        let output = CIImage(cgImage: image).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask]).cropped(to: extent)
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    }
}

/// The matte and cut-out caches, and which pictures are being worked on (the tool shows a spinner for those). Vision and Core Image run off the main thread.
@MainActor
@Observable
final class SegmentationStore {
    static let shared = SegmentationStore()

    /// Keys of the cut-outs being computed now.
    private(set) var working: Set<String> = []

    @ObservationIgnored private var mattes: [String: CIImage] = [:]
    @ObservationIgnored private var matteOrder: [String] = []
    @ObservationIgnored private let cutouts = NSCache<NSString, CGImage>()
    @ObservationIgnored private var inFlight: [String: Task<CGImage?, Never>] = [:]
    @ObservationIgnored private let context = CIContext(options: [.workingColorSpace: NSNull()])

    var isWorking: Bool { !working.isEmpty }

    init() { cutouts.countLimit = 8 }

    /// The cut-out of `source` (the picture `sourceKey` names) for a segmentation mask, nil when nothing was found. `featherPx` is in the picture's own pixels.
    func cutout(of source: CGImage, sourceKey: String, segmentation: V2MaskSegmentation, featherPx: Double, invert: Bool) async -> CGImage? {
        let mode = segmentation.mode ?? "auto"
        let at = segmentation.at.map { CGPoint(x: $0.x, y: $0.y) }
        let matteKey = "\(sourceKey)|\(mode)|\(at.map { String(format: "%.3f,%.3f", $0.x, $0.y) } ?? "-")"
        let key = "\(matteKey)|\(String(format: "%.2f", featherPx))|\(invert)"
        if let hit = cutouts.object(forKey: key as NSString) { return hit }
        if let running = inFlight[key] { return await running.value }
        let cachedMatte = mattes[matteKey]
        let context = context
        working.insert(key)
        let task = Task.detached(priority: .userInitiated) { () -> (CGImage?, CIImage?) in
            let matte = cachedMatte ?? SegmentationService.matte(for: source, mode: mode, at: at)
            guard let matte else { return (nil, nil) }
            return (SegmentationService.cutout(of: source, matte: matte, feather: featherPx, invert: invert, context: context), matte)
        }
        let flight = Task<CGImage?, Never> { await task.value.0 }
        inFlight[key] = flight
        let (image, matte) = await task.value
        inFlight[key] = nil
        working.remove(key)
        if let matte, mattes[matteKey] == nil {
            mattes[matteKey] = matte
            matteOrder.append(matteKey)
            if matteOrder.count > 6 { mattes[matteOrder.removeFirst()] = nil }
        }
        if let image { cutouts.setObject(image, forKey: key as NSString) }
        return image
    }
}
