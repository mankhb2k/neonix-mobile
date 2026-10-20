import CoreImage
import Foundation

/// Shared runtime for Protocol V2 `feChromaKey`. The editable definition stays small and renderer-neutral; this
/// runtime builds the device-specific 3D matte LUT and caches it by its serialized parameters.
enum ChromaKeyRenderer {
    private static let cubeSize = 32
    private static let cubeLock = NSLock()
    private static var cubeCache: [String: Data] = [:]
    private static var cubeCacheOrder: [String] = []

    static func apply(
        to image: CIImage,
        keyColor: String,
        similarity: Double,
        smoothness: Double,
        shadow: Double,
        edgeCleanup: Double
    ) -> CIImage {
        guard let key = RGB(hex: keyColor) else { return image }
        let similarity = min(max(similarity, 0), 1)
        let smoothness = min(max(smoothness, 0), 1)
        let shadow = min(max(shadow, 0), 1)
        let edgeCleanup = min(max(edgeCleanup, 0), 1)

        let cubeKey = String(format: "%@|%.4f|%.4f|%.4f", keyColor.uppercased(), similarity, smoothness, shadow)
        let data = cubeData(for: cubeKey, key: key, similarity: similarity, smoothness: smoothness, shadow: shadow)
        guard let cube = CIFilter(name: "CIColorCube") else { return image }
        cube.setValue(image, forKey: kCIInputImageKey)
        cube.setValue(cubeSize, forKey: "inputCubeDimension")
        cube.setValue(data, forKey: "inputCubeData")
        guard var matte = cube.outputImage?.cropped(to: image.extent) else { return image }

        if edgeCleanup > 0.01, let shrink = CIFilter(name: "CIMorphologyMinimum") {
            shrink.setValue(matte.clampedToExtent(), forKey: kCIInputImageKey)
            shrink.setValue(edgeCleanup * 4, forKey: kCIInputRadiusKey)
            matte = (shrink.outputImage ?? matte).cropped(to: image.extent)
        }

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        blend.setValue(matte, forKey: kCIInputMaskImageKey)
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }

    private static func cubeData(for cacheKey: String, key: RGB, similarity: Double, smoothness: Double, shadow: Double) -> Data {
        cubeLock.lock()
        if let cached = cubeCache[cacheKey] {
            cubeLock.unlock()
            return cached
        }
        cubeLock.unlock()

        let count = cubeSize * cubeSize * cubeSize * 4
        var values = [Float](repeating: 0, count: count)
        let step = 1.0 / Double(cubeSize - 1)
        let keyY = 0.2126 * key.r + 0.7152 * key.g + 0.0722 * key.b
        let keyU = key.b - keyY, keyV = key.r - keyY
        let chromaticKey = hypot(keyU, keyV) > 0.10
        let inner = 0.025 + similarity * 0.40
        let outer = inner + 0.008 + smoothness * 0.16
        var offset = 0

        for b in 0..<cubeSize {
            for g in 0..<cubeSize {
                for r in 0..<cubeSize {
                    let red = Double(r) * step, green = Double(g) * step, blue = Double(b) * step
                    let y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                    let du = (blue - y) - keyU, dv = (red - y) - keyV
                    let dy = y - keyY
                    let ordinaryDistance = sqrt(2.2 * (du * du + dv * dv) + dy * dy)
                    let normalizedDistance: Double
                    if chromaticKey {
                        let scale = max(y, 0.06), keyScale = max(keyY, 0.06)
                        let nu = (blue - y) / scale - keyU / keyScale
                        let nv = (red - y) / scale - keyV / keyScale
                        normalizedDistance = hypot(nu, nv) * 0.4
                    } else {
                        normalizedDistance = ordinaryDistance
                    }
                    let distance = ordinaryDistance * (1 - shadow) + normalizedDistance * shadow
                    let t = min(max((distance - inner) / (outer - inner), 0), 1)
                    let alpha = Float(t * t * (3 - 2 * t))
                    values[offset] = alpha
                    values[offset + 1] = alpha
                    values[offset + 2] = alpha
                    values[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = values.withUnsafeBytes { Data($0) }

        cubeLock.lock()
        if cubeCache[cacheKey] == nil {
            cubeCache[cacheKey] = data
            cubeCacheOrder.append(cacheKey)
            if cubeCacheOrder.count > 12 {
                let evicted = cubeCacheOrder.removeFirst()
                cubeCache.removeValue(forKey: evicted)
            }
        }
        cubeLock.unlock()
        return data
    }

    private struct RGB {
        let r: Double
        let g: Double
        let b: Double

        init?(hex: String) {
            let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
            r = Double((number >> 16) & 0xff) / 255
            g = Double((number >> 8) & 0xff) / 255
            b = Double(number & 0xff) / 255
        }
    }
}
